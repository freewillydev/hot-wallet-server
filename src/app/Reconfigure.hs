{-# LANGUAGE ScopedTypeVariables #-}
-- Root-only configuration lifecycle. No keys are generated and no payment is sent.
module Reconfigure (updateConfig,backupCredentialChanges,validateBackupPhase) where
import Bridge.AdminKey (readPrivate,privateParent,withFamily)
import Bridge.Error
import Bridge.File (withHandle,readBounded)
import Bridge.Identity (digest)
import Bridge.Wallet (protectWalletProcess)
import Bridge.Domain (parseCoins)
import qualified Bridge.Config as C
import qualified Bridge.Wire as W
import qualified InstallConfig as I
import qualified Configure
import qualified Bootstrap
import qualified ReconfigureFiles as Files
import qualified ReconfigureServices as Services
import qualified WalletRotation
import qualified Data.ByteString as B
import qualified Data.ByteString.Char8 as B8
import qualified Data.ByteString.Lazy as L
import qualified Data.Text as T
import qualified Data.Aeson.KeyMap as M
import Data.Aeson
import Data.Aeson.Types (parseEither)
import Data.Bits ((.&.))
import Data.List (find,isPrefixOf)
import Control.Monad (forM,forM_,unless,when,filterM)
import Control.Exception (bracket,catch,throwIO)
import Crypto.Random (getRandomBytes)
import System.Directory (makeAbsolute)
import System.FilePath ((</>),takeDirectory)
import System.Info (os)
import System.Exit (ExitCode(..))
import System.IO.Error (tryIOError,isDoesNotExistError)
import System.Posix.User (getEffectiveUserID,getGroupEntryForName,groupID,getUserEntryForName,userID,userGroupID)
import qualified System.Posix.Directory as D
import System.Posix.Files
import System.Posix.IO hiding (sync)
import System.Posix.Types (FileMode,UserID,GroupID)
import System.Posix.Unistd (fileSynchronise)
import System.Process (rawSystem)

state,setup,pending,lifecycle,updates :: FilePath
state="/var/lib/hot-wallet-server"
setup=state</>".ecx-bridge"
pending=state</>"reconfigure.pending"
lifecycle="/var/lib/ecx-bridge-upgrade"
updates=state</>"config-updates"

type View = FilePath -> IO (Maybe B.ByteString)

updateConfig :: FilePath -> IO ()
updateConfig input=updateLocked input `catch` \failure@(BridgeError reason)->do
  -- Only this proven read-only retirement refusal has cleared its interlocks
  -- without changing custody. Resume the old setup after both locks are released.
  if reason=="wallet_replacement_refused_unresolved_work_old_wallets_preserved" then do
    Configure.start setup
    hosting<-exists(setup</>"hosting.json")
    when hosting $ do
      result<-rawSystem "/bin/sh" ["/opt/ecx-bridge/current/tunnel",setup]
      require (result==ExitSuccess) "wallet_replacement_refused_old_wallets_running_tunnel_resume_failed"
    throwIO failure
   else throwIO failure

updateLocked :: FilePath -> IO ()
updateLocked input=do
  protectWalletProcess
  uid<-getEffectiveUserID
  require (uid==0 && os=="linux") "configuration_update_requires_root_on_ubuntu"
  privateParent (state</>"server.conf")
  ensurePrivate lifecycle
  file<-makeAbsolute input
  withFamily (lifecycle</>"lifecycle") $ withFamily (setup<>"-configure") $ do
    forM_ [lifecycle</>"pending","/var/lib/ecx-bridge-restore/pending"] $ \path->
      exists path >>= \present->require (not present) "finish_pending_upgrade_or_restore_first"
    (bytes,settings)<-I.readInstallConfig file
    active<-exists pending
    signerBlocked<-exists(state</>"reconfigure.signer-blocked")
    require (active || not signerBlocked) "configuration_update_signer_block_without_pending"
    currentRecord<-readExisting (state</>"server.conf")
    prior<-case currentRecord of
      Just saved->pure(Just saved)
      Nothing->do
        imported<-readExisting(setup</>"install.conf")
        -- Older bundled installers retained only this exact private import.
        -- Recover its provenance; never adopt the new candidate as the old input.
        forM_ imported (Files.savePrivateRecord $ state</>"server.conf")
        pure imported
    if not active && prior==Just bytes then
      putStrLn "Configuration already matches the saved record."
     else do
      ensurePrivate updates
      journal<-if active then do
        saved<-B8.unpack <$> readPrivate pending
        let suffix=drop (length updates+1) saved
        require (saved==updates</>suffix && length suffix==64
          && all (`elem` ("0123456789abcdef"::String)) suffix) "invalid_configuration_update_journal"
        pure saved
       else do
        nonce<-getRandomBytes 32
        pure $ updates</>T.unpack(digest $ bytes<>nonce)
      ensurePrivate journal
      exact (journal</>"input.conf") bytes
      let candidate=journal</>"input.conf"
      rotation<-exists(journal</>"rotation")
      if rotation then WalletRotation.rotateWallets candidate journal settings bytes (True,True) else do
        prepared<-exists(journal</>"pending")
        if prepared then do
          saved<-Files.loadConfigFiles journal
          forM_ saved validateTarget
          (initialized,installed)<-readPrivate(journal</>"mode.json") >>= decodeBytes
          currentInstalled<-exists "/etc/ecx-bridge/installed"
          require (installed==currentInstalled) "configuration_update_installation_changed"
          let old=beforeView saved
          expected<-configurationFiles old bytes settings initialized installed
          require (saved==expected) "configuration_update_plan_changed"
          publish journal saved settings initialized installed
         else do
          initialized<-exists setup
          installed<-exists "/etc/ecx-bridge/installed"
          require (not installed || initialized) "installed_setup_missing_requires_recovery"
          changed<-case prior of
            Nothing->require (not initialized) "saved_installation_record_missing" >> pure(False,False)
            Just old->do
              exact (journal</>"previous.conf") old
              if not initialized then pure(False,False) else do
                (_,_,_,result)<-I.readInstallConfigUpdate (journal</>"previous.conf") candidate
                pure result
          if initialized && changed/=(False,False) then do
            WalletRotation.rotateWallets candidate journal settings bytes changed
           else do
            changingBackup<-if initialized then backupChanged readExisting settings else pure False
            when initialized $ do
              I.validateOperationalUpdate (journal</>"previous.conf") candidate
              bound<-exists(setup</>"bootstrap-bound.json")
              require (not bound || installed || changingBackup) "bootstrap_in_progress_finish_original_configuration_first"
            exact (journal</>"mode.json") (L.toStrict $ encode (initialized,installed))
            files<-configurationFiles readExisting bytes settings initialized installed
            Files.stageConfigFiles journal files
            publish journal files settings initialized installed
 where
  publish journal files settings initialized installed=do
    changingBackup<-if initialized then backupChanged (beforeView files) settings else pure False
    resuming<-exists pending
    -- A killed checkpoint may leave only the signer running. Re-block and stop
    -- it before any potentially slow network preflight on an interrupted update.
    when (changingBackup && installed && resuming) $ Services.beginBackupUpdate journal
    when changingBackup $ do
      -- Test private candidate files before taking the current service offline.
      -- A replay uses the same immutable journal, including after partial publish.
      let repository=journal</>"backup.repository";password=journal</>"backup.password"
      exact repository (repositoryBytes settings)
      exact password (B8.pack $ I.backupPassword settings)
      spec<-readJSON (beforeView files) (setup</>"setup.json")
      Bootstrap.checkBackupAccess spec repository password
    if installed then
      if changingBackup then unless resuming (Services.beginBackupUpdate journal) else Services.beginUpdate journal >> pure ()
     else Services.setPending journal
    Files.publishConfigFiles journal files
    verifySetup readExisting initialized installed
    let verifyFiles=forM_ files $ \item->readExisting (Files.configPath item) >>= \actual->
          require (actual==Just(Files.configAfter item)) "configuration_update_publication_changed"
    verifyFiles
    when (changingBackup && installed) $ do
      putStrLn "Verifying a fresh custody backup on the new server; payments remain stopped..."
      Services.completeBackupUpdate journal
      verifyFiles
    Services.finishUpdate journal
    putStrLn "Configuration updated; previous settings are retained privately in config-updates."

afterView,beforeView :: [Files.ConfigFile] -> View
afterView files path=case find ((==path).Files.configPath) files of
  Just file->pure $ Just $ Files.configAfter file
  Nothing->readExisting path
beforeView files path=case find ((==path).Files.configPath) files of
  Just file->pure $ Files.configBefore file
  Nothing->readExisting path

backupChanged :: View -> I.InstallConfig -> IO Bool
backupChanged old settings=do
  previous<-required old (state</>"server.conf") >>= I.readPreviousRecord
  let prior=fst previous
  pure (I.backupRepositoryUrl prior/=I.backupRepositoryUrl settings || I.backupPassword prior/=I.backupPassword settings)

repositoryBytes :: I.InstallConfig -> B.ByteString
repositoryBytes config=B8.pack $ let url=I.backupRepositoryUrl config in
  if "https://" `isPrefixOf` url then "rest:"<>url else url

-- A partial low-level installer seals source file contents. Do not invalidate
-- that receipt or reset its database; completed installations use checkpoints.
validateBackupPhase :: (FilePath -> IO Bool) -> Bool -> IO ()
validateBackupPhase present installed=unless installed $
  forM_ ["/var/lib/ecx-bridge-install","/etc/ecx-bridge","/var/lib/ecx-bridge-setup/installed-directory.json"] $ \path->
    present path >>= \partial->require (not partial) "finish_partial_installation_before_changing_backup"

-- The only backup write set: retained setup credentials plus the installed
-- signer's copies. Sources and runtime backup configuration must name those
-- exact files; no wallet, ledger or historical snapshot is rewritten.
backupCredentialChanges :: View -> Bool -> I.InstallConfig -> IO [(FilePath,B.ByteString)]
backupCredentialChanges old installed settings=do
  (prior,_)<-required old (state</>"server.conf") >>= I.readPreviousRecord
  sources<-readJSON old (setup</>"sources.json")
  let repository=setup</>"backup.repository"
      password=setup</>"backup.password"
      field value key=case value of Object fields->M.lookup key fields; _->Nothing
      signer="/etc/ecx-bridge/signer"
      directories=[setup]<>[signer | installed]
  require (field sources "backup.repository"==Just(toJSON repository)
    && field sources "backup.password"==Just(toJSON password)) "backup_update_source_paths_changed"
  when installed $ do
    actual<-readJSON old (signer</>"backup.json")
    require (actual==object ["restic" .= ("/opt/ecx-bridge/current/bin/restic"::String)
      ,"repositoryFile" .= (signer</>"backup.repository"),"passwordFile" .= (signer</>"backup.password")])
      "backup_update_runtime_paths_changed"
  forM_ directories $ \directory->do
    required old (directory</>"backup.repository") >>= \saved->
      require (saved==repositoryBytes prior) "backup_setup_credentials_changed"
    required old (directory</>"backup.password") >>= \saved->
      require (saved==B8.pack(I.backupPassword prior)) "backup_setup_credentials_changed"
  pure $ concat [[(directory</>"backup.repository",repositoryBytes settings)
    ,(directory</>"backup.password",B8.pack $ I.backupPassword settings)] | directory<-directories]

configurationFiles :: View -> B.ByteString -> I.InstallConfig -> Bool -> Bool -> IO [Files.ConfigFile]
configurationFiles old bytes settings initialized installed=do
  verifySetup old initialized installed
  native<-either reject pure (parseCoins $ T.pack $ I.payoutThresholdEcx settings)
  wrapped<-either reject pure (parseCoins $ T.pack $ I.payoutThresholdWrappedEcx settings)
  gasTopUp<-either reject pure (I.installGasTopUp settings)
  let policy=W.PayoutPolicy native wrapped (fromInteger $ 3600*I.minimumPayoutIntervalHours settings)
      configChange value=case value of
        Object fields->Object $ M.union (M.fromList
          ["solanaRpc" .= I.solanaRpcUrl settings,"solanaVerifierRpc" .= I.solanaVerifierRpcUrl settings
          ,"payoutPolicy" .= policy,"gasTopUpOffer" .= gasTopUp
          ,"ownerFeeRecipients" .= C.OwnerFeeRecipients (T.pack $ I.ownerEcxXpub settings) (T.pack $ I.ownerSolPubkey settings)]) fields
        _->value
      interfaceChange value=case value of
        Object fields->Object $ M.union (M.fromList
          ["publicOrigin" .= (case I.cloudflareTunnelToken settings of Nothing->Nothing; Just _->Just $ "https://"<>I.domain settings)
          ,"orcaUrl" .= I.externalLinkOrca settings,"tokenExplorerUrl" .= I.externalLinkSolscan settings]) fields
        _->value
      hosting=object ["serverIp" .= I.serverIp settings,"domain" .= I.domain settings
        ,"tunnel" .= maybe False (const True) (I.cloudflareTunnelToken settings)]
      changeJSON path change=readJSON old path >>= replacement old path . L.toStrict . encode . change
      selected paths=filterM (fmap maybePresent . old) paths
      maybePresent=maybe False (const True)
  first<-replacement old (state</>"server.conf") bytes
  files<-if not initialized then pure [first] else do
    imported<-replacement old (setup</>"install.conf") bytes
    changingBackup<-backupChanged old settings
    credentials<-if not changingBackup then pure [] else do
      validateBackupPhase exists installed
      backupCredentialChanges old installed settings >>= mapM (uncurry $ replacement old)
    paths<-selected $ map (setup</>) ["bootstrap.json","bootstrap-complete.json","worker.json","signer.json"]
      <> if installed then ["/etc/ecx-bridge/worker/config.json","/etc/ecx-bridge/signer/config.json"] else []
    configs<-forM paths $ \path->do
      previous<-readJSON old path
      priorConfig<-decodeValue previous
      nextConfig<-decodeValue(configChange previous)
      C.validateSetupConfig nextConfig
      require (C.fingerprint priorConfig==C.fingerprint nextConfig) "operational_update_changed_custody"
      replacement old path (L.toStrict $ encode $ configChange previous)
    interfaces<-selected $ [setup</>"interface.json"]<>if installed then ["/etc/ecx-bridge/worker/interface.json"] else []
    links<-mapM (\path->changeJSON path interfaceChange) interfaces
    host<-replacement old (setup</>"hosting.json") (L.toStrict $ encode hosting)
    tunnel<-exists "/etc/ecx-bridge/tunnel"
    tunnelHost<-if installed && tunnel then pure <$> replacement old "/etc/ecx-bridge/tunnel/hosting.json" (L.toStrict $ encode hosting) else pure []
    tokens<-case I.cloudflareTunnelToken settings of
      Nothing->pure []
      Just token->do
        local<-replacement old (setup</>"tunnel.token") (B8.pack token)
        if installed && tunnel then do
          target<-replacement old "/etc/ecx-bridge/tunnel/token" (B8.pack token)
          pure [local,target]
         else pure [local]
    bound<-old(setup</>"bootstrap-bound.json")
    seals<-case bound of
      Nothing->pure []
      Just _->do
        values<-mapM (readJSON old . (setup</>)) ["bootstrap.json","setup.json","sources.json","interface.json"]
        case values of
          [c,s,r,i]->pure <$> replacement old (setup</>"bootstrap-bound.json")
            (L.toStrict $ encode [configChange c,s,r,interfaceChange i])
          _->reject "invalid_setup_binding"
    pure $ [first,imported,host]<>configs<>links<>tokens<>tunnelHost<>seals<>credentials
  verifySetup (afterView files) initialized installed
  pure files

-- Validate the retained and candidate setup on every replay, including the exact
-- pre-bootstrap seal and role-specific source-to-installed path rewrites.
verifySetup :: View -> Bool -> Bool -> IO ()
verifySetup view initialized installed=when initialized $ do
  saved<-required view (state</>"server.conf")
  imported<-required view (setup</>"install.conf")
  require (saved==imported) "saved_installation_record_mismatch"
  bootstrap<-readJSON view (setup</>"bootstrap.json") >>= decodeValue
  C.validateSetupConfig bootstrap
  links<-readJSON view (setup</>"interface.json") >>= decodeValue
  C.validateInterface bootstrap links
  bound<-view(setup</>"bootstrap-bound.json")
  forM_ bound $ \bytes->do
    sealed<-decodeBytes bytes
    values<-mapM (readJSON view . (setup</>)) ["bootstrap.json","setup.json","sources.json","interface.json"]
    require (sealed==toJSON values) "bootstrap_saved_configuration_changed"
  when installed $ do
    registry<-readPrivate "/var/lib/ecx-bridge-setup/installed-directory.json" >>= decodeBytes
    require ((registry::FilePath)==setup) "configuration_update_setup_registry_mismatch"
    completed<-readJSON view (setup</>"bootstrap-complete.json") >>= decodeValue
    C.validateConfig completed
    require (completed {C.solanaHistoryStart="",C.solanaOperatingHistoryStart=""}==bootstrap)
      "bootstrap_identity_changed"
    forM_ ["worker","signer"] $ \role->do
      source<-readJSON view (setup</>(role<>".json")) >>= decodeValue
      actual<-readJSON view ("/etc/ecx-bridge"</>role</>"config.json") >>= decodeValue
      C.validateConfig source;C.validateConfig actual
      let normalized=source {C.nativeCookie=C.nativeCookie actual,C.nativeUnlockFile=C.nativeUnlockFile actual
            ,C.signerAuthFile=C.signerAuthFile actual,C.fenceDirectory=C.fenceDirectory actual
            ,C.solanaSdkLibrary=C.solanaSdkLibrary actual}
          completion=source {C.nativeCookie=C.nativeCookie completed,C.nativeUnlockFile=C.nativeUnlockFile completed}
      require (normalized==actual && completion==completed) "configuration_update_source_runtime_mismatch"
    sourceInterface<-required view (setup</>"interface.json")
    actualInterface<-required view "/etc/ecx-bridge/worker/interface.json"
    require (sourceInterface==actualInterface) "configuration_update_source_interface_mismatch"

replacement :: View -> FilePath -> B.ByteString -> IO Files.ConfigFile
replacement old path bytes=do
  previous<-old path
  (permissions,owner,group)<-metadata path
  pure $ Files.ConfigFile path previous bytes permissions owner group

validateTarget :: Files.ConfigFile -> IO ()
validateTarget file=do
  require (Files.configPath file `elem` writablePaths) "configuration_update_target_outside_scope"
  expected<-metadata(Files.configPath file)
  require ((Files.configMode file,Files.configOwner file,Files.configGroup file)==expected)
    "configuration_update_metadata_changed"

writablePaths :: [FilePath]
writablePaths=[state</>"server.conf"]<>map (setup</>)
  ["install.conf","bootstrap.json","bootstrap-complete.json","worker.json","signer.json","interface.json"
  ,"hosting.json","tunnel.token","bootstrap-bound.json","backup.repository","backup.password"]
  <>["/etc/ecx-bridge/worker/config.json","/etc/ecx-bridge/signer/config.json","/etc/ecx-bridge/worker/interface.json"
    ,"/etc/ecx-bridge/tunnel/token","/etc/ecx-bridge/tunnel/hosting.json"
    ,"/etc/ecx-bridge/signer/backup.repository","/etc/ecx-bridge/signer/backup.password"]

metadata :: FilePath -> IO (FileMode,UserID,GroupID)
metadata path=do
  require (path `elem` (writablePaths<>map (setup</>) ["setup.json","sources.json"]<>["/etc/ecx-bridge/signer/backup.json"])) "configuration_update_target_outside_scope"
  if path `elem` ["/etc/ecx-bridge/worker/config.json","/etc/ecx-bridge/worker/interface.json"]
    then do group<-groupID <$> getGroupEntryForName "ecxbridgew";pure(0o640,0,group)
    else if path=="/etc/ecx-bridge/signer/config.json"
      then do group<-groupID <$> getGroupEntryForName "ecxbridges";pure(0o640,0,group)
      else if path `elem` map ("/etc/ecx-bridge/signer"</>) ["backup.repository","backup.password","backup.json"]
        then do
          user<-getUserEntryForName "ecxbridges"
          pure(0o600,userID user,userGroupID user)
        else pure(0o600,0,0)

readExisting :: View
readExisting path=do
  (permissions,owner,group)<-metadata path
  present<-exists path
  if not present then pure Nothing else do
    checkDirectory(takeDirectory path)
    bracket (openFd path ReadOnly defaultFileFlags {nofollow=True,nonBlock=True,cloexec=True}) closeFd $ \fd->do
      status<-getFdStatus fd
      require (isRegularFile status && linkCount status==1 && fileOwner status==owner && fileGroup status==group
        && fileMode status .&. 0o7777==permissions) "unsafe_configuration_update_file"
      bytes<-withHandle fd (readBounded 32768) >>= maybe (reject "configuration_update_file_too_large") pure
      pure(Just bytes)

required :: View -> FilePath -> IO B.ByteString
required view path=view path >>= maybe (reject "configuration_update_material_missing") pure
readJSON :: View -> FilePath -> IO Value
readJSON view path=required view path >>= decodeBytes

decodeBytes :: FromJSON a => B.ByteString -> IO a
decodeBytes=either (const $ reject "invalid_configuration_update_record") pure . eitherDecodeStrict'
decodeValue :: FromJSON a => Value -> IO a
decodeValue=either (const $ reject "invalid_configuration_update_record") pure . parseEither parseJSON

ensurePrivate :: FilePath -> IO ()
ensurePrivate path=do
  checkDirectory(takeDirectory path)
  present<-exists path
  unless present $ D.createDirectory path 0o700 >> sync(takeDirectory path)
  privateParent(path</>"probe")
checkDirectory :: FilePath -> IO ()
checkDirectory path=do
  status<-getSymbolicLinkStatus path
  require (isDirectory status && fileOwner status==0 && fileMode status .&. 0o022==0) "unsafe_configuration_update_parent"
  when (path/="/") $ checkDirectory(takeDirectory path)
exists :: FilePath -> IO Bool
exists path=do
  result<-tryIOError(getSymbolicLinkStatus path)
  case result of
    Right _->pure True
    Left failure | isDoesNotExistError failure->pure False
    Left failure->ioError failure
exact :: FilePath -> B.ByteString -> IO ()
exact=Files.savePrivateRecord
sync :: FilePath -> IO ()
sync path=bracket (openFd path ReadOnly defaultFileFlags {nofollow=True,cloexec=True,directory=True}) closeFd fileSynchronise
