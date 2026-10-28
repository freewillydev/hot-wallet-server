-- One-time local node provisioning, never a worker/signer runtime capability.
module NodeSetup (credentials,checkConfig,withConfig,serviceName,provision,persistRestoredWallet,signerPolicy,refreshSignerPolicy) where
import Bridge.AdminKey (savePrivate,readPrivate,withFamily)
import qualified ReconfigureFiles as ConfigFiles
import qualified SetupPaths
import Bridge.File (withHandle,readBounded)
import System.IO (hFlush)
import System.IO.Error (catchIOError,isDoesNotExistError)
import Bridge.Error
import Bridge.RPC (fieldValue)
import Bridge.SolanaMessage (base58)
import Crypto.Random (getRandomBytes)
import Crypto.MAC.HMAC (hmac,HMAC)
import Crypto.Hash (SHA256)
import qualified Data.ByteArray.Encoding as Hex
import qualified Data.ByteString as B
import qualified Data.ByteString.Char8 as B8
import qualified Data.Text as T
import Data.Aeson (Value,eitherDecodeStrict',withObject,(.:?),(.!=))
import Data.Aeson.Types (parseEither)
import Control.Exception (bracket,onException)
import System.Posix.IO (openFdAt,closeFd,OpenMode(ReadOnly,WriteOnly),defaultFileFlags,OpenFileFlags(..))
import System.Posix.Types (Fd(..))
import System.Posix.User (getEffectiveUserID)
import Foreign.C.String (CString,withCString)
import Foreign.C.Types (CInt(..))
import Foreign.C.Error (throwErrnoIfMinus1_)
import System.Posix.Unistd (fileSynchronise)
import Control.Monad (forM,forM_,unless,when)
import System.Directory (doesFileExist)
import System.FilePath ((</>),takeDirectory,takeFileName,splitDirectories,normalise,isAbsolute)
import System.Posix.Files
import System.Process (readProcessWithExitCode,rawSystem)
import System.Exit (ExitCode(..))
import Data.Bits ((.&.))

serviceName :: String -> IO String
serviceName name=do
  require (not(null name) && take 1 name/="-" && length name<128
    && all (`elem` ("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.@"::String)) name) "invalid_node_service"
  pure name

checkConfig :: FilePath -> IO ()
checkConfig path=withConfig path (\_ _->pure ())

-- Pin every directory and the source file. Node-owned directories are allowed,
-- but symlink substitution cannot redirect root's read or publication. Bytes
-- and publication metadata come from the SAME descriptor, never a later stat.
withConfig :: FilePath -> (B.ByteString -> (B.ByteString -> IO ()) -> IO a) -> IO a
withConfig path action=do
  require (isAbsolute path && normalise path==path) "unsafe_node_configuration"
  uid<-getEffectiveUserID
  directories uid Nothing Nothing (splitDirectories $ takeDirectory path) $ \parent owner->
    bracket (openFdAt (Just parent) name ReadOnly flags) closeFd $ \fd->do
      status<-getFdStatus fd
      require (isRegularFile status && linkCount status==1 && fileMode status .&. 0o022==0
        && maybe True (==fileOwner status) owner && fileSize status<=8192) "unsafe_node_configuration"
      bytes<-withHandle fd (readBounded 8192) >>= maybe (reject "unsafe_node_configuration") pure
      action bytes $ \next->do
        nonce<-base58 <$> getRandomBytes 8
        let staging=name<>".ecx-bridge-"<>T.unpack nonce
            cleanup=relative "unlink node staging" c_unlinkat parent staging `catchIOError` \e->
              unless (isDoesNotExistError e) (ioError e)
        bracket (openFdAt (Just parent) staging WriteOnly flags {creat=Just 0o600,exclusive=True}) closeFd $ \out->do
          (do
            withHandle out $ \handle->B.hPut handle next >> hFlush handle
            setFdOwnerAndGroup out (fileOwner status) (fileGroup status)
            setFdMode out (fileMode status .&. 0o777)
            fileSynchronise out
            withCString staging $ \old->withCString name $ \new->
              let Fd dir=parent in throwErrnoIfMinus1_ "rename node configuration" (c_renameat dir old dir new)
            fileSynchronise parent) `onException` cleanup
 where
  name=takeFileName path
  flags=defaultFileFlags {nofollow=True,nonBlock=True,cloexec=True}
  -- Once a service user controls an ancestor, only that user's descendants are
  -- trusted. Moving a root-owned secret directory under it cannot elevate access.
  directories uid owner parent (part:rest) done=bracket
    (openFdAt parent part ReadOnly flags {directory=True}) closeFd $ \fd->do
      status<-getFdStatus fd
      require (isDirectory status && fileMode status .&. 0o022==0
        && maybe True (==fileOwner status) owner) "unsafe_node_configuration_parent"
      let next=case owner of
            Nothing | fileOwner status `notElem` [0,uid]->Just(fileOwner status)
            _->owner
      if null rest then done fd next else directories uid next (Just fd) rest done
  directories _ _ _ [] _=reject "unsafe_node_configuration"
  relative label call (Fd dir) name=withCString name $ \leaf->throwErrnoIfMinus1_ label (call dir leaf 0)

foreign import ccall unsafe "renameat" c_renameat :: CInt -> CString -> CInt -> CString -> IO CInt
foreign import ccall unsafe "unlinkat" c_unlinkat :: CInt -> CString -> CInt -> IO CInt

credentials :: FilePath -> IO (FilePath,FilePath,FilePath)
credentials directory=do
  let roles=[("admin",adminMethods),("worker",workerMethods),("signer",signerMethods)]
      files=[directory</>("native-"<>role<>".auth") | (role,_)<-roles]
      config=directory</>"native-rpc.conf"
  complete<-doesFileExist config
  if complete then mapM_ readPrivate (config:files) else do
    rows<-forM roles $ \(role,methods)->do
      let credential=directory</>("native-"<>role<>".auth")
      exists<-doesFileExist credential
      auth<-if exists then readPrivate credential else do
        password<-base58 <$> getRandomBytes 32
        suffix<-base58 <$> getRandomBytes 8
        let bytes=B8.pack $ "ecx_"<>role<>"_"<>T.unpack suffix<>":"<>T.unpack password
        ConfigFiles.savePrivateRecord credential bytes
        pure bytes
      let (user,tailBytes)=B8.break (==':') auth
          password=B.drop 1 tailBytes
      require ((B8.pack $ "ecx_"<>role<>"_") `B.isPrefixOf` user && B.length password>=40
        && not(B8.any (`elem` ['\n','\r',':']) password)) "invalid_generated_credentials"
      salt<-base58 <$> getRandomBytes 16
      let digest=B8.unpack (Hex.convertToBase Hex.Base16 (hmac (B8.pack $ T.unpack salt) password::HMAC SHA256))
      pure $ "rpcauth="<>B8.unpack user<>":"<>T.unpack salt<>"$"<>digest<>"\nrpcwhitelist="<>B8.unpack user<>":"<>methods<>"\n"
    ConfigFiles.savePrivateRecord config (B8.pack $ concat rows)
  case files of
    [admin,worker,signer]->pure(admin,worker,signer)
    _->reject "invalid_generated_credentials"

-- Preserve the node's existing configuration and authority defaults. Refuse
-- complex include trees instead of silently changing another RPC user's rights.
provision :: FilePath -> IO ()
provision directory=do
  setup<-decode =<< readPrivate (directory</>"setup.json")
  generated<-doesFileExist (directory</>"native-rpc.conf")
  when generated $ withFamily (directory</>"node-provision") $ do
    path<-fieldValue "nodeConfig" setup
    service<-fieldValue "nodeService" setup >>= serviceName
    managed<-either (const $ reject "invalid_setup_json") pure
      (parseEither (withObject "setup" (\o->o .:? "managedNode" .!= False)) setup)
    when managed $ do
      require (path=="/var/lib/ecx-betanet/bitcoin.conf" && service=="ecx-betanet.service") "managed_node_identity_changed"
      bootstrap<-decode =<< readPrivate (directory</>"bootstrap.json")
      endpoint<-fieldValue "nativeRpc" bootstrap :: IO String
      require (endpoint=="http://127.0.0.1:28532") "managed_node_requires_guarded_rpc"
      method<-fieldValue "method" setup :: IO String
      root<-fieldValue "sourceRoot" setup
      installer<-SetupPaths.nodeInstaller method root
      putStrLn $ "Using managed ECX node installer: "<>installer
      result<-rawSystem "/bin/sh" [installer]
      require (result==ExitSuccess) "managed_node_install_failed_retry_start"
    (loaded,_,_)<-readProcessWithExitCode "systemctl" ["cat",service] ""
    require (loaded==ExitSuccess) "node_service_not_found_edit_setup_before_start"
    withConfig path $ \current publish->do
      let original=directory</>"node-config.before"
      saved<-doesFileExist original
      unless saved $ do
        require (not $ any ((=="includeconf") . option) $ B8.lines current) "node_include_tree_requires_advanced_configuration"
        savePrivate original current
      before<-readPrivate original
      originalRules<-readPrivate (directory</>"native-rpc.conf")
      signerAuth<-readPrivate (directory</>"native-signer.auth")
      (migrating,rules)<-either reject pure (signerPolicy signerAuth originalRules)
      let settings=map option $ B8.lines before
          priorWhitelist="rpcwhitelist" `elem` settings
          explicitDefault="rpcwhitelistdefault" `elem` settings
          -- Without any prior whitelist the old node allowed authenticated users;
          -- preserve that default while explicitly restricting all three new users.
          preserve=if not priorWhitelist && not explicitDefault then "rpcwhitelistdefault=0\n" else ""
          header="# Generated ECX bridge RPC roles\n"<>preserve
          updated=header<>rules<>"\n"<>before
          legacyExpected=header<>originalRules<>"\n"<>before
          -- Recovery may have appended one wallet autoload line after provisioning.
          -- Preserve that existing line; never invent a wallet or accept other edits.
          retained=case [extra | prefix<-[legacyExpected,updated],Just extra<-[B.stripPrefix prefix current]
            ,Just line<-[B.stripPrefix "\nwallet=" extra],Just wallet<-[B.stripSuffix "\n" line]
            ,not(B.null wallet),B8.all (`elem` ("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"::String)) wallet] of
              extra:_->extra
              []->B.empty
          expected=updated<>retained
          suffix=if migrating then "-signer-validation" else ""
          marker=directory</>("node-rpc-installed"<>suffix)
      require (current `elem` [before,legacyExpected<>retained,expected]) "node_configuration_changed_review_before_retry"
      restarted<-doesFileExist marker
      when (migrating && (current/=expected || not restarted)) $ forM_ ["ecx-bridge-worker","ecx-bridge-signer"] $ \unit->do
        (result,state,_)<-readProcessWithExitCode "systemctl" ["show",unit,"--property=MainPID,ActiveState,LoadState"] ""
        require (result==ExitSuccess && ("LoadState=not-found" `elem` lines state ||
          ("MainPID=0" `elem` lines state && any (`elem` lines state) ["ActiveState=inactive","ActiveState=failed"]))) "stop_custody_before_native_policy_refresh"
      let candidate=directory</>("node-config.after"<>suffix)
      candidateExists<-doesFileExist candidate
      if candidateExists then readPrivate candidate >>= \bytes->require (bytes==expected) "node_configuration_candidate_changed"
        else savePrivate candidate expected
      when (current/=expected) (publish expected)
      unless (restarted && current==expected) $ do
        putStrLn "Installing distinct node RPC roles; restarting the configured ECX node service."
        (result,_,_)<-readProcessWithExitCode "systemctl" ["restart",service] ""
        require (result==ExitSuccess) "node_restart_failed_original_configuration_preserved"
        unless restarted $ savePrivate marker "installed\n"
 where
  option=B8.strip . B8.takeWhile (/='=')
  decode bytes=either (const $ reject "invalid_setup_json") pure (eitherDecodeStrict' bytes::Either String Value)

-- Existing installations need the same narrow policy correction. New policies
-- skip provisioning, including its original pre-autoload configuration binding.
refreshSignerPolicy :: FilePath -> IO ()
refreshSignerPolicy directory=do
  exists<-doesFileExist(directory</>"native-rpc.conf")
  when exists $ do
    auth<-readPrivate(directory</>"native-signer.auth")
    rules<-readPrivate(directory</>"native-rpc.conf")
    (legacy,_)<-either reject pure (signerPolicy auth rules)
    when legacy $ provision directory

readMethods,workerMethods,signerMethods,adminMethods :: String
readMethods="getblockchaininfo,getblockhash,getblockheader,getnetworkinfo,getconnectioncount,getwalletinfo,getbalances,getaddressinfo,gettransaction,gettxout,gettxspendingprevout,getmempoolentry,listsinceblock,listunspent,listlockunspent,decodepsbt,decoderawtransaction,decodescript,estimatesmartfee,getmempoolinfo"
workerMethods=readMethods<>",getdescriptorinfo,deriveaddresses"<>",getnewaddress,getaddressesbylabel,getrawchangeaddress,walletcreatefundedpsbt,lockunspent,createpsbt,testmempoolaccept,sendrawtransaction"
signerMethods=readMethods<>",lockunspent,testmempoolaccept,walletcreatefundedpsbt,createpsbt,walletprocesspsbt,finalizepsbt,walletpassphrase,walletlock,backupwallet,listdescriptors"
adminMethods=readMethods<>",getdescriptorinfo,deriveaddresses,listwalletdir,createwallet,importdescriptors,listdescriptors,getnewaddress,walletpassphrase,walletlock"

-- Only the exact historically generated signer policy can be refreshed. All
-- passwords, rpcauth salts, other users and original binding files stay intact.
signerPolicy :: B.ByteString -> B.ByteString -> Either T.Text (Bool,B.ByteString)
signerPolicy credential rules=do
  let username=B8.takeWhile (/=':') credential
      prefix="rpcwhitelist="<>username<>":"
      old=prefix<>B8.pack (readMethods<>",walletcreatefundedpsbt,createpsbt,walletprocesspsbt,finalizepsbt,walletpassphrase,walletlock,backupwallet,listdescriptors")
      current=prefix<>B8.pack signerMethods
      rows=B8.lines rules
  unless (not(B.null username) && B8.unlines rows==rules) $ Left "unrecognized_native_signer_policy"
  case filter (B.isPrefixOf prefix) rows of
    [line] | line==current->Right(False,rules)
           | line==old->Right(True,B8.unlines $ map (\row->if row==old then current else row) rows)
    _->Left "unrecognized_native_signer_policy"

-- Managed recovery only, with custody services stopped by the activation journal.
-- Preserve all RPC restrictions; an unfamiliar scoped config requires review.
persistRestoredWallet :: T.Text -> IO ()
persistRestoredWallet wallet=do
  let path="/var/lib/ecx-betanet/bitcoin.conf"
      record=B8.pack $ "wallet="<>T.unpack wallet
  require (not(T.null wallet) && T.all (`elem` ("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"::String)) wallet) "invalid_recovered_wallet_name"
  withConfig path $ \bytes publish->do
    require (not $ any (B8.isPrefixOf "[" . B8.strip) $ B8.lines bytes) "scoped_node_configuration_requires_review"
    unless (record `elem` map B8.strip (B8.lines bytes)) $ do
      let candidate=bytes<>"\n"<>record<>"\n"
      publish candidate
  (code,_,_)<-readProcessWithExitCode "systemctl" ["restart","ecx-betanet.service"] ""
  require (code==ExitSuccess) "recovered_node_restart_failed"
