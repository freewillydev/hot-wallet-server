-- Fixed root service interlocks and checked custody checkpoints. No publication
-- or database reset occurs here; callers retain the shared lifecycle lock.
module ReconfigureServices
  (beginUpdate,setPending,finishUpdate,installInterlocks,stop,checkpoint,checkFence) where
import Bridge.AdminKey (readPrivate)
import Bridge.Error (require,reject)
import Bridge.File (withHandle,readBounded)
import Bridge.Identity (digest)
import qualified Bridge.Config as C
import qualified Bridge.Wire as W
import ReconfigureFiles (savePrivateRecord)
import Control.Exception (bracket,finally)
import Control.Monad (forM_,unless,when)
import Crypto.Random (getRandomBytes)
import Data.Aeson hiding (decode)
import Data.Aeson.Types (parseEither)
import Data.Bits ((.&.))
import Data.Int (Int64)
import qualified Data.ByteString as B
import qualified Data.ByteString.Char8 as B8
import qualified Data.ByteString.Lazy as L
import qualified Data.Text as T
import System.Directory (removeFile,renameFile)
import System.Exit (ExitCode(..))
import System.FilePath ((</>),takeDirectory)
import System.IO (hFlush)
import System.IO.Error (tryIOError,isDoesNotExistError)
import qualified System.Posix.Directory as D
import System.Posix.Files
import System.Posix.IO
import System.Posix.Types (FileMode,GroupID)
import System.Posix.Unistd (fileSynchronise)
import System.Posix.User (getGroupEntryForName,groupID)
import System.Process (readProcessWithExitCode)

state,pending,signerBlocked,worker,binary :: FilePath
state="/var/lib/hot-wallet-server"
pending=state</>"reconfigure.pending"
signerBlocked=state</>"reconfigure.signer-blocked"
worker="/etc/ecx-bridge/worker/config.json"
binary="/opt/ecx-bridge/current/bin/ecx-bridge"

beginUpdate :: FilePath -> IO W.BackupReceipt
beginUpdate journal=do
  installInterlocks
  setPending journal
  command "systemctl" ["daemon-reload"]
  stop "ecx-bridge-tunnel.service" True
  stop "ecx-bridge-worker.service" False
  receipt<-checkpoint journal
  mark signerBlocked (B8.pack journal)
  stop "ecx-bridge-signer.service" False
  checkFence receipt
  pure receipt

setPending :: FilePath -> IO ()
setPending journal=mark pending (B8.pack journal)

finishUpdate :: FilePath -> IO ()
finishUpdate journal=do
  readPrivate pending >>= \saved->require (saved==B8.pack journal) "configuration_update_pending_changed"
  blocked<-exists signerBlocked
  when blocked $ do
    readPrivate signerBlocked >>= \saved->require (saved==B8.pack journal) "configuration_update_signer_block_changed"
    removeFile signerBlocked
    syncDirectory state
  removeFile pending
  syncDirectory state

checkpoint :: FilePath -> IO W.BackupReceipt
checkpoint journal=do
  configBytes<-readWorkerConfig
  config<-decode configBytes :: IO C.Config
  let receiptPath=journal</>"checkpoint.json"
      configPath=journal</>"checkpoint-config.json"
  present<-exists receiptPath
  unless present $ do
    -- A reboot before the receipt may restart only the old signer. Intake remains
    -- blocked by the global pending marker throughout checkpoint creation.
    blocked<-exists signerBlocked
    require (not blocked) "configuration_update_signer_block_without_checkpoint"
    mark configPath configBytes
    command "systemctl" ["start","ecx-bridge-signer.service"]
    db<-B8.unpack . B8.strip <$> readPrivate "/var/lib/ecx-bridge-install/database"
    require (db=="ecx_bridge" || length db==44 && take 12 db=="ecx_restore_"
      && all (`elem` ("0123456789abcdef"::String)) (drop 12 db)) "invalid_installed_database"
    result<-output "runuser" ["-u","ecxbridgew","--","env","PGHOST=/var/run/postgresql","PGPORT=5432"
      ,"PGDATABASE="<>db,"PGUSER=ecxbridgew","PGREADUSER=ecxbridger",binary,"checkpoint",worker]
    receipt<-decode(B8.pack result)
    validateReceipt config receipt
    savePrivateRecord receiptPath (L.toStrict $ encode (receipt::W.BackupReceipt))
  savedConfig<-readPrivate configPath >>= decode
  require (C.fingerprint savedConfig==C.fingerprint config) "configuration_update_checkpoint_identity_changed"
  receipt<-readPrivate receiptPath >>= decode
  validateReceipt savedConfig receipt
  pure receipt

validateReceipt :: C.Config -> W.BackupReceipt -> IO ()
validateReceipt config receipt=require (W.receiptIdentity receipt==C.fingerprint config
  && W.receiptSequence receipt>=0 && hex (W.receiptArchiveHash receipt) && hex (W.receiptSnapshot receipt))
  "configuration_update_checkpoint_invalid"
 where
  hex value=T.length value==64 && T.all (`elem` ("0123456789abcdef"::String)) value

checkFence :: W.BackupReceipt -> IO ()
checkFence receipt=do
  value<-output "runuser" ["-u","ecxbridgew","--",binary,"check-fence",worker] >>= decode . B8.pack
  (identity,sequenceNo)<-either (const $ reject "invalid_configuration_update_fence") pure $
    parseEither (withObject "fence" $ \fields->(,) <$> fields .: "fingerprint" <*> fields .: "sequence") value
  require (identity==W.receiptIdentity receipt && (sequenceNo::Int64)==W.receiptSequence receipt)
    "configuration_update_fence_checkpoint_mismatch"

installInterlocks :: IO ()
installInterlocks=forM_ ["worker","signer","tunnel"] $ \role->do
  let directory="/etc/systemd/system/ecx-bridge-"<>role<>".service.d"
      path=directory</>"91-config-update.conf"
      blocker=if role=="signer" then signerBlocked else pending
      bytes=B8.pack $ "[Unit]\nConditionPathExists=!"<>blocker<>"\n"
  checkDirectory (takeDirectory directory)
  present<-exists directory
  unless present $ D.createDirectory directory 0o755 >> syncDirectory (takeDirectory directory)
  checkDirectory directory
  old<-exists path
  if old then do
    actual<-readRootFile path 0o644 0
    require (actual==bytes) "configuration_interlock_changed"
   else do
    randomBytes<-getRandomBytes 16
    let staged=path<>".pending-"<>T.unpack(digest randomBytes)
    bracket (openFd staged WriteOnly defaultFileFlags {creat=Just 0o600,exclusive=True,nofollow=True,cloexec=True})
      (\fd->closeFd fd `finally` cleanup staged) $ \fd->do
        withHandle fd $ \handle->B.hPut handle bytes >> hFlush handle
        setFdOwnerAndGroup fd 0 0
        setFdMode fd 0o644
        fileSynchronise fd
        -- The caller holds the lifecycle lock. Recheck before atomic publication;
        -- a killed writer must never leave the live interlock with two links.
        appeared<-exists path
        if appeared then do
          actual<-readRootFile path 0o644 0
          require (actual==bytes) "configuration_interlock_changed"
         else renameFile staged path
  -- Replay also completes directory durability if the earlier writer stopped
  -- after the rename (or after creating the drop-in directory).
  bracket (openFd path ReadOnly defaultFileFlags {nofollow=True,cloexec=True}) closeFd fileSynchronise
  syncDirectory directory
  syncDirectory (takeDirectory directory)
 where
  cleanup path=do
    result<-tryIOError(removeFile path)
    case result of
      Right ()->pure ()
      Left failure | isDoesNotExistError failure->pure ()
      Left failure->ioError failure

stop :: String -> Bool -> IO ()
stop service optional=do
  require (service `elem` ["ecx-bridge-worker.service","ecx-bridge-signer.service","ecx-bridge-tunnel.service"])
    "invalid_configuration_update_service"
  loaded<-output "systemctl" ["show",service,"--property=LoadState","--value"]
  unless (optional && words loaded==["not-found"]) $ do
    command "systemctl" ["stop",service]
    pid<-output "systemctl" ["show",service,"--property=MainPID","--value"]
    status<-output "systemctl" ["show",service,"--property=ActiveState","--value"]
    require (words pid==["0"] && words status `elem` [["inactive"],["failed"]]) "configuration_service_still_running"

readWorkerConfig :: IO B.ByteString
readWorkerConfig=do
  group<-groupID <$> getGroupEntryForName "ecxbridgew"
  readRootFile worker 0o640 group

readRootFile :: FilePath -> FileMode -> GroupID -> IO B.ByteString
readRootFile path permissions group=do
  checkDirectory (takeDirectory path)
  bracket (openFd path ReadOnly defaultFileFlags {nofollow=True,nonBlock=True,cloexec=True}) closeFd $ \fd->do
    status<-getFdStatus fd
    require (isRegularFile status && linkCount status==1 && fileOwner status==0
      && fileGroup status==group && fileMode status .&. 0o7777==permissions) "unsafe_configuration_update_file"
    withHandle fd (readBounded 8192) >>= maybe (reject "configuration_update_file_too_large") pure

checkDirectory :: FilePath -> IO ()
checkDirectory path=do
  status<-getSymbolicLinkStatus path
  require (isDirectory status && fileOwner status==0 && fileMode status .&. 0o022==0) "unsafe_configuration_update_parent"
  when (path/="/") $ checkDirectory(takeDirectory path)

mark :: FilePath -> B.ByteString -> IO ()
mark=savePrivateRecord
exists :: FilePath -> IO Bool
exists path=do
  result<-tryIOError(getSymbolicLinkStatus path)
  case result of
    Right _->pure True
    Left failure | isDoesNotExistError failure->pure False
    Left failure->ioError failure
syncDirectory :: FilePath -> IO ()
syncDirectory path=bracket (openFd path ReadOnly defaultFileFlags {nofollow=True,cloexec=True,directory=True}) closeFd fileSynchronise
decode :: FromJSON a => B.ByteString -> IO a
decode=either (const $ reject "invalid_configuration_update_record") pure . eitherDecodeStrict'
output :: FilePath -> [String] -> IO String
output program arguments=do
  (code,result,_)<-readProcessWithExitCode program arguments ""
  require (code==ExitSuccess) "configuration_update_step_failed_state_preserved"
  pure result
command :: FilePath -> [String] -> IO ()
command program arguments=output program arguments >> pure ()
