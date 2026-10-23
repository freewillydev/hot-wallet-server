{-# LANGUAGE DeriveGeneric #-}
-- Offline installation retirement. Old custody is never swept or deleted.
module WalletRotation (rotateWallets,verifyReplacement) where
import Bridge.AdminKey (readPrivate,privateParent)
import Bridge.Error
import Bridge.Identity (digest)
import qualified Bridge.Config as C
import qualified Bridge.Wire as W
import qualified Configure
import qualified InstallConfig as I
import qualified RotationFiles as R
import qualified ReconfigureFiles as F
import qualified ReconfigureServices as Services
import Control.Monad (forM,forM_,unless,when)
import Control.Exception (bracket)
import Data.Aeson hiding (decode)
import Data.List (isPrefixOf)
import Data.Maybe (maybeToList)
import qualified Data.ByteString as B
import qualified Data.ByteString.Char8 as B8
import qualified Data.ByteString.Lazy as L
import qualified Data.Text as T
import GHC.Generics (Generic)
import System.Directory (doesFileExist,doesDirectoryExist,canonicalizePath)
import System.Environment (getExecutablePath)
import System.Exit (ExitCode(..))
import System.FilePath ((</>),takeDirectory,takeFileName,addTrailingPathSeparator)
import qualified System.Posix.Directory as D
import System.Posix.IO (openFd,closeFd,OpenMode(ReadOnly),defaultFileFlags)
import System.Posix.Unistd (fileSynchronise)
import System.Posix.User
import System.Process (readProcessWithExitCode)

data Rotation = Rotation
  { installed :: Bool, suffix :: String, inputHash :: T.Text
  , originalDatabase :: String, originalIdentity :: T.Text
  , accounts :: [(String,Integer,Integer)]
  } deriving (Eq,Generic)
instance ToJSON Rotation
instance FromJSON Rotation

state,setup,worker :: FilePath
state="/var/lib/hot-wallet-server"
setup=state</>".ecx-bridge"
worker="/etc/ecx-bridge/worker/config.json"

-- Called under the global configuration/lifecycle locks. The immutable plan is
-- saved before external effects, so a retry never infers custody from new files.
rotateWallets :: FilePath -> FilePath -> I.InstallConfig -> B.ByteString -> (Bool,Bool) -> IO ()
rotateWallets _input journal settings bytes changed=do
  uid<-getEffectiveUserID
  require (uid==0) "wallet_replacement_requires_root"
  executable<-getExecutablePath >>= canonicalizePath
  require (not ("/opt/ecx-bridge/" `isPrefixOf` executable)) "run_wallet_replacement_from_update_config_script"
  present<-doesFileExist(journal</>"rotation")
  plan<-if present then readPrivate(journal</>"rotation") >>= decode else do
    active<-doesFileExist "/etc/ecx-bridge/installed"
    bound<-doesFileExist(setup</>"bootstrap-bound.json")
    partial<-doesDirectoryExist "/var/lib/ecx-bridge-install"
    -- An unfinished ATA remains archived with its original key and exact bytes;
    -- it is never resigned or replayed for new custody. A partial ledger needs
    -- completion/recovery first because it may already have financial state.
    require (active || not partial) "finish_partial_ledger_installation_before_replacing_wallets"
    when (active || bound) $ require (changed==(True,True)) "initialized_wallet_replacement_requires_two_new_wallets"
    unless active $ forM_ ["/etc/ecx-bridge","/var/lib/ecx-bridge","/opt/ecx-bridge"] $ \path->
      doesDirectoryExist path >>= \found->require (not found) "existing_runtime_requires_completed_installation"
    if active then do
      registered<-readPrivate "/var/lib/ecx-bridge-setup/installed-directory.json" >>= decode
      require ((registered::FilePath)==setup) "wallet_replacement_requires_original_setup_directory"
      original<-C.loadConfig worker
      requested<-C.loadConfig(setup</>"worker.json")
      require (C.fingerprint original==C.fingerprint requested) "wallet_replacement_setup_identity_mismatch"
      db<-B8.unpack . B8.strip <$> readPrivate "/var/lib/ecx-bridge-install/database"
      token<-readPrivate "/var/lib/ecx-bridge-install/owner"
      identities<-serviceAccounts
      let next=Rotation True (take 32 $ takeFileName journal) (digest bytes) db (C.fingerprint original) identities
      mark (journal</>"installation-token") token
      pure next
     else pure $ Rotation False (take 32 $ takeFileName journal) (digest bytes) "" "" []
  require (inputHash plan==digest bytes && length(suffix plan)==32
    && all (`elem` ("0123456789abcdef"::String)) (suffix plan)) "wallet_replacement_input_changed"
  -- External setup inputs must survive retirement, including symlink targets.
  -- An old installed website/restic binary is not a durable new setup input.
  forM_ (I.resticExecutable settings : maybeToList (I.websiteDirectory settings)) $ \path->do
    resolved<-canonicalizePath path
    forM_ (archivePaths $ installed plan) $ \retiring->
      require (resolved/=retiring && not (addTrailingPathSeparator retiring `isPrefixOf` resolved))
        "replacement_dependency_inside_retired_installation"
  -- Exercise the complete importer (including website, destination and SDK
  -- checks) before stopping the old installation or retiring its database.
  -- This private staging area imports the supplied seeds; it cannot start a node,
  -- sign, broadcast, or replace the currently installed configuration.
  Configure.configureFile (journal</>"input.conf") (journal</>"validated-setup")
  mark (journal</>"rotation") (L.toStrict $ encode plan)
  let paths=archivePaths (installed plan)
  _<-R.stageRotationDirectories journal (suffix plan) paths
  -- Save original record separately: all directory archives retain their exact
  -- path mapping even after the new installation occupies the original paths.
  hasOld<-doesFileExist(journal</>"old.conf")
  unless hasOld $ readPrivate(state</>"server.conf") >>= mark(journal</>"old.conf")
  retired<-doesFileExist(journal</>"database-retired.json")
  when (installed plan && not retired) $ do
    receipt<-Services.beginUpdate journal
    require (W.receiptIdentity receipt==originalIdentity plan) "wallet_replacement_checkpoint_identity_mismatch"
    token<-readPrivate(journal</>"installation-token")
    preflight<-doesFileExist(journal</>"archive-checked.json")
    unless preflight $ do
      (code,reply,_)<-databaseCommand executable plan token "check-installation-archive" receipt []
      if code==ExitSuccess then do
        proof<-decode(B8.pack reply) :: IO Value
        require (proof==object ["fingerprint" .= originalIdentity plan,"criticalSequence" .= W.receiptSequence receipt
          ,"readyToArchive" .= True]) "wallet_replacement_preflight_mismatch"
        mark (journal</>"archive-checked.json") (L.toStrict $ encode proof)
       else do
        -- The closed preflight has no writes. Restore service availability using
        -- the unchanged old config; no key or database has yet been replaced.
        Services.finishUpdate journal
        command "systemctl" ["start","ecx-bridge-signer.service","ecx-bridge-worker.service"]
        reject "wallet_replacement_refused_unresolved_work_old_wallets_preserved"
    result<-databaseCommand executable plan token "archive-installation-database" receipt [suffix plan]
    receiptBytes<-case result of
      (ExitSuccess,reply,_)->pure(B8.pack reply)
      _->reject "wallet_replacement_archive_incomplete_rerun_same_script"
    proof<-decode receiptBytes :: IO Value
    require (proof==object ["database" .= ("ecx_archive_"<>suffix plan),"fingerprint" .= originalIdentity plan
      ,"criticalSequence" .= W.receiptSequence receipt,"retired" .= True]) "wallet_replacement_archive_mismatch"
    mark (journal</>"database-retired.json") (L.toStrict $ encode proof)
  Services.setPending journal
  when (installed plan) $ do
    -- No exporter may keep using the retired bundle or wallet binding.
    command "systemctl" ["stop","ecx-native-backup.socket","ecx-native-backup@*.service"]
    (_,running,_)<-readProcessWithExitCode "systemctl"
      ["list-units","--all","--state=active,activating,deactivating","--no-legend","ecx-native-backup@*.service"] ""
    require (null $ words running) "native_backup_exporter_still_running"
  R.publishRotationDirectories journal paths
  let oldSetup=setup<>".retired-"<>suffix plan
  ensurePrivate setup
  -- Keep the node's original RPC roles and exact provisioning bindings. The old
  -- node/wallet database stays in place; only the bridge custody is replaced.
  forM_ nodeBindings $ \name->do
    exists<-doesFileExist(oldSetup</>name)
    when exists $ readPrivate(oldSetup</>name) >>= mark(setup</>name)
  Configure.configureFile (journal</>"input.conf") setup
  binding<-setupBinding
  mark (journal</>"replacement-binding.json") (L.toStrict $ encode binding)
  when (installed plan) $ mark (setup</>"wallet-replacement.json") (L.toStrict $ encode journal)
  old<-readPrivate(journal</>"old.conf")
  let file=F.ConfigFile (state</>"server.conf") (Just old) bytes 0o600 0 0
      record=journal</>"configuration"
  F.stageConfigFiles record [file]
  F.publishConfigFiles record [file]
  mark (journal</>"rotation-complete") "wallet-replacement-v1\n"
  Services.finishUpdate journal
  putStrLn "Old wallet keys, ledger and recovery records are archived privately; no balances were transferred."
  putStrLn $ "Archive index: "<>journal
  putStrLn "The replacement installation will use only the seeds supplied in your config."

-- The installer alone uses this narrow authorization to reuse the existing OS
-- service identities. This does not waive the fresh-ledger or supplied-key checks.
verifyReplacement :: FilePath -> IO ()
verifyReplacement directory=do
  getEffectiveUserID >>= \uid->require (uid==0 && directory==setup) "invalid_wallet_replacement_directory"
  journal<-readPrivate(setup</>"wallet-replacement.json") >>= decode
  require (takeDirectory journal==state</>"config-updates" && length(takeFileName journal)==64
    && all (`elem` ("0123456789abcdef"::String)) (takeFileName journal)) "invalid_wallet_replacement_journal"
  plan<-readPrivate(journal</>"rotation") >>= decode
  require (installed plan) "wallet_replacement_not_an_installed_rotation"
  readPrivate(journal</>"rotation-complete") >>= \value->require (value=="wallet-replacement-v1\n") "wallet_replacement_incomplete"
  receipt<-readPrivate(journal</>"checkpoint.json") >>= decode
  require (W.receiptIdentity receipt==originalIdentity plan) "wallet_replacement_checkpoint_identity_mismatch"
  proof<-readPrivate(journal</>"database-retired.json") >>= (decode :: B.ByteString -> IO Value)
  require (proof==object ["database" .= ("ecx_archive_"<>suffix plan),"fingerprint" .= originalIdentity plan
    ,"criticalSequence" .= W.receiptSequence receipt,"retired" .= True]) "wallet_replacement_archive_mismatch"
  R.publishRotationDirectories journal (archivePaths True)
  current<-serviceAccounts
  require (current==accounts plan) "wallet_replacement_service_accounts_changed"
  (_,settings)<-I.readInstallConfig(setup</>"install.conf")
  _<-I.validateInstallConfig settings
  saved<-readPrivate(journal</>"replacement-binding.json") >>= decode
  actual<-setupBinding
  require (actual==(saved::Value)) "wallet_replacement_material_changed"
  readPrivate(setup</>"install.conf") >>= \value->require (digest value==inputHash plan) "wallet_replacement_config_changed"

archivePaths :: Bool -> [FilePath]
archivePaths active=[setup,setup<>"-keys"]<>if active then
  ["/etc/ecx-bridge","/var/lib/ecx-bridge","/opt/ecx-bridge","/var/lib/ecx-bridge-install"
  ,"/var/lib/ecx-bridge-setup","/etc/ecx-native-backup"] else []

nodeBindings :: [FilePath]
nodeBindings=["native-rpc.conf","native-admin.auth","native-worker.auth","native-signer.auth"
  ,"node-config.before","node-config.after","node-config.after-signer-validation"
  ,"node-rpc-installed","node-rpc-installed-signer-validation"]

setupBinding :: IO Value
setupBinding=toJSON <$> mapM (\path->do bytes<-readPrivate path; pure(path,digest bytes))
  ([setup</>name|name<-["install.conf","setup.json","sources.json","bootstrap.json","interface.json"]]
    <>[setup<>"-keys"</>name|name<-["solana.keypair.json","ecx-recovery.txt","native-unlock"]])

serviceAccounts :: IO [(String,Integer,Integer)]
serviceAccounts=forM [("ecxbridgew","worker"),("ecxbridges","signer")] $ \(name,role)->do
  account<-getUserEntryForName name
  group<-getGroupEntryForName name
  require (homeDirectory account=="/var/lib/ecx-bridge/"<>role && userShell account=="/usr/sbin/nologin"
    && userGroupID account==groupID group) "wallet_replacement_service_account_changed"
  (_,memberships,_)<-readProcessWithExitCode "id" ["-Gn",name] ""
  require (words memberships==[name]) "wallet_replacement_service_groups_changed"
  pure(name,toInteger $ userID account,toInteger $ userGroupID account)

databaseCommand :: FilePath -> Rotation -> B.ByteString -> String -> W.BackupReceipt -> [String] -> IO (ExitCode,String,String)
databaseCommand binary plan token operation receipt extra=readProcessWithExitCode "runuser"
  (["-u","postgres","--","env","PGHOST=/var/run/postgresql","PGPORT=5432","PGUSER=postgres"
    ,"PGDATABASE="<>originalDatabase plan,"ecx_bridge_datadir=/opt/ecx-bridge/current/share"
    ,binary,operation,T.unpack $ originalIdentity plan,show $ W.receiptSequence receipt]<>extra) (B8.unpack token)

ensurePrivate :: FilePath -> IO ()
ensurePrivate path=do
  exists<-doesDirectoryExist path
  unless exists $ D.createDirectory path 0o700 >> sync(takeDirectory path)
  privateParent(path</>"probe")
mark :: FilePath -> B.ByteString -> IO ()
mark=F.savePrivateRecord
sync :: FilePath -> IO ()
sync path=bracket (openFd path ReadOnly defaultFileFlags) closeFd fileSynchronise
decode :: FromJSON a => B.ByteString -> IO a
decode=either (const $ reject "invalid_wallet_replacement_record") pure . eitherDecodeStrict'
command :: FilePath -> [String] -> IO ()
command program arguments=do
  (code,_,_)<-readProcessWithExitCode program arguments ""
  require (code==ExitSuccess) "wallet_replacement_step_failed_rerun_same_script"
