{-# LANGUAGE DeriveGeneric #-}
-- Durable private file publication only. Callers own service/database ordering
-- and must validate the reconstructed target list against their fixed scope.
module ReconfigureFiles
  (ConfigFile(..),stageConfigFiles,loadConfigFiles,publishConfigFiles,savePrivateRecord) where
import Bridge.AdminKey (readPrivate,withFamily)
import Bridge.Error (require,reject)
import Bridge.File (withHandle,readBounded)
import Bridge.Identity (digest)
import Control.Exception (bracket,finally)
import Control.Monad (forM,forM_,unless)
import Crypto.Random (getRandomBytes)
import Data.Aeson (FromJSON,ToJSON,encode,eitherDecodeStrict')
import Data.Bits ((.&.))
import Data.List (nub,isPrefixOf)
import qualified Data.ByteString as B
import qualified Data.ByteString.Lazy as L
import qualified Data.Text as T
import GHC.Generics (Generic)
import System.Directory (renameFile,removeFile)
import System.FilePath ((</>),isAbsolute,normalise,takeDirectory,splitDirectories)
import System.IO (hFlush)
import System.IO.Error (tryIOError,isDoesNotExistError)
import qualified System.Posix.Directory as P
import System.Posix.Files
import System.Posix.IO
import System.Posix.Types (FileMode,GroupID,UserID)
import System.Posix.Unistd (fileSynchronise)
import System.Posix.User (getEffectiveUserID)

-- Deliberately no Show: both snapshots may contain credentials or private keys.
data ConfigFile = ConfigFile
  { configPath :: FilePath,configBefore :: Maybe B.ByteString,configAfter :: B.ByteString
  , configMode :: FileMode,configOwner :: UserID,configGroup :: GroupID
  } deriving Eq

data Entry = Entry
  { target :: FilePath,before :: Maybe T.Text,after :: T.Text
  , mode :: Integer,owner :: Integer,group :: Integer
  } deriving (Eq,Generic)
instance ToJSON Entry
instance FromJSON Entry
data Manifest = Manifest
  { version :: Int,journalOwner :: Integer,entries :: [Entry]
  } deriving (Eq,Generic)
instance ToJSON Manifest
instance FromJSON Manifest

marker :: B.ByteString
marker="configuration-update-v1\n"

-- A complete immutable manifest and every snapshot are durable before pending
-- becomes visible. Interrupted staging resumes only with the identical input.
stageConfigFiles :: FilePath -> [ConfigFile] -> IO ()
stageConfigFiles journal files=do
  validateFiles journal files
  ensureJournal journal
  pending<-optionalPrivate (journal</>"pending")
  require (maybe True (==marker) pending) "invalid_configuration_update_marker"
  forM_ files $ \file->do
    actual<-readTarget file
    require (actual==configBefore file || (pending==Just marker && actual==Just(configAfter file)))
      "configuration_update_target_changed"
  manifest<-manifestFor files
  let bytes=L.toStrict $ encode manifest
  require (B.length bytes<=8192) "configuration_update_manifest_too_large"
  savePrivateRecord (journal</>"manifest.json") bytes
  forM_ (zip [0::Int ..] files) $ \(index,file)->do
    forM_ (configBefore file) $ savePrivateRecord (snapshot journal index "old")
    savePrivateRecord (snapshot journal index "new") (configAfter file)
  savePrivateRecord (journal</>"pending") marker

-- Snapshot names are derived from bounded list positions, never from manifest
-- paths. Loading does not read or mutate the recorded external targets.
loadConfigFiles :: FilePath -> IO [ConfigFile]
loadConfigFiles journal=do
  checkJournal journal
  bytes<-readPrivate (journal</>"manifest.json")
  manifest<-either (const $ reject "invalid_configuration_update_manifest") pure (eitherDecodeStrict' bytes)
  uid<-getEffectiveUserID
  require (version manifest==1 && journalOwner manifest==toInteger uid
    && bytes==L.toStrict(encode manifest) && not(null $ entries manifest) && length(entries manifest)<=64)
    "invalid_configuration_update_manifest"
  files<-forM (zip [0::Int ..] $ entries manifest) $ \(index,entry)->do
    require (mode entry `elem` [0o600,0o640]
      && owner entry>=0 && toInteger(fromInteger(owner entry)::UserID)==owner entry
      && group entry>=0 && toInteger(fromInteger(group entry)::GroupID)==group entry)
      "invalid_configuration_update_metadata"
    old<-traverse (readSnapshot $ snapshot journal index "old") (before entry)
    new<-readSnapshot (snapshot journal index "new") (after entry)
    pure $ ConfigFile (target entry) old new (fromInteger $ mode entry)
      (fromInteger $ owner entry) (fromInteger $ group entry)
  validateShape journal files
  pure files
 where
  readSnapshot path expected=do
    bytes<-readRegular path 0o600 Nothing Nothing
    require (digest bytes==expected) "configuration_update_snapshot_changed"
    pure bytes

-- The supplied list must exactly match the staged journal. Recheck all targets
-- before the first mutation, then each target immediately before its rename.
-- A partial publication can replay only exact old/new bytes with exact metadata.
publishConfigFiles :: FilePath -> [ConfigFile] -> IO ()
publishConfigFiles journal files=do
  validateFiles journal files
  saved<-loadConfigFiles journal
  require (saved==files) "configuration_update_plan_changed"
  pending<-readPrivate (journal</>"pending")
  require (pending==marker) "invalid_configuration_update_marker"
  complete<-optionalPrivate (journal</>"complete")
  require (maybe True (==marker) complete) "invalid_configuration_update_marker"
  forM_ files $ \file->do
    actual<-readTarget file
    require (actual==Just(configAfter file) || (complete==Nothing && actual==configBefore file))
      "configuration_update_target_changed"
  forM_ files $ \file->do
    actual<-readTarget file
    unless (actual==Just(configAfter file)) (publish file)
  forM_ files $ \file->do
    actual<-readTarget file
    require (actual==Just(configAfter file)) "configuration_update_publication_failed"
  savePrivateRecord (journal</>"complete") marker

manifestFor :: [ConfigFile] -> IO Manifest
manifestFor files=do
  uid<-getEffectiveUserID
  pure $ Manifest 1 (toInteger uid)
    [Entry (configPath file) (digest <$> configBefore file) (digest $ configAfter file)
      (toInteger $ configMode file) (toInteger $ configOwner file) (toInteger $ configGroup file) | file<-files]

validateShape :: FilePath -> [ConfigFile] -> IO ()
validateShape journal files=do
  validPath journal
  require (not(null files) && length files<=64 && length(nub $ map configPath files)==length files)
    "invalid_configuration_update_targets"
  forM_ files $ \file->do
    validPath (configPath file)
    require (configPath file/=journal && not((journal<>"/") `isPrefixOf` configPath file)
      && configMode file `elem` [0o600,0o640]
      && B.length(configAfter file)<=32768 && maybe True ((<=32768).B.length) (configBefore file))
      "invalid_configuration_update_target"

validateFiles :: FilePath -> [ConfigFile] -> IO ()
validateFiles journal files=do
  validateShape journal files
  checkParents journal
  forM_ files (checkParents . configPath)

validPath :: FilePath -> IO ()
validPath path=require (isAbsolute path && normalise path==path && path/="/" && length path<=4096
  && all (\c->c>=' ' && c/='\DEL') path && all (`notElem` [".",".."]) (splitDirectories path))
  "invalid_configuration_update_path"

-- Every ancestor is a real directory owned by root/current euid and protected
-- from group/other writes. The immediate publication parent belongs to euid.
checkParents :: FilePath -> IO ()
checkParents path=do
  validPath path
  uid<-getEffectiveUserID
  let parent=takeDirectory path
      ancestors directory=if directory=="/" then ["/"] else ancestors(takeDirectory directory)<>[directory]
  forM_ (ancestors parent) $ \directory->do
    status<-getSymbolicLinkStatus directory
    require (isDirectory status && fileOwner status `elem` [0,uid] && fileMode status .&. 0o022==0
      && (directory/=parent || fileOwner status==uid)) "unsafe_configuration_update_parent"

ensureJournal :: FilePath -> IO ()
ensureJournal journal=do
  checkParents journal
  exists<-statusMaybe journal
  case exists of
    Nothing->P.createDirectory journal 0o700 >> syncParent journal
    Just _->pure ()
  checkJournal journal

checkJournal :: FilePath -> IO ()
checkJournal journal=do
  checkParents journal
  uid<-getEffectiveUserID
  status<-getSymbolicLinkStatus journal
  require (isDirectory status && fileOwner status==uid && fileMode status .&. 0o7777==0o700)
    "unsafe_configuration_update_journal"

statusMaybe :: FilePath -> IO (Maybe FileStatus)
statusMaybe path=do
  result<-tryIOError (getSymbolicLinkStatus path)
  case result of
    Right status->pure(Just status)
    Left errorValue | isDoesNotExistError errorValue->pure Nothing
    Left errorValue->ioError errorValue

readTarget :: ConfigFile -> IO (Maybe B.ByteString)
readTarget file=do
  checkParents (configPath file)
  exists<-statusMaybe (configPath file)
  case exists of
    Nothing->pure Nothing
    Just _->Just <$> readRegular (configPath file) (configMode file)
      (Just $ configOwner file) (Just $ configGroup file)

readRegular :: FilePath -> FileMode -> Maybe UserID -> Maybe GroupID -> IO B.ByteString
readRegular path expectedMode expectedOwner expectedGroup=do
  checkParents path
  bracket (openFd path ReadOnly defaultFileFlags {nofollow=True,cloexec=True,nonBlock=True}) closeFd $ \fd->do
    status<-getFdStatus fd
    uid<-getEffectiveUserID
    require (isRegularFile status && linkCount status==1
      && fileOwner status==maybe uid id expectedOwner && fileMode status .&. 0o7777==expectedMode
      && maybe True (==fileGroup status) expectedGroup) "unsafe_configuration_update_file"
    bytes<-withHandle fd (readBounded 32768) >>= maybe (reject "configuration_update_file_too_large") pure
    pure bytes

optionalPrivate :: FilePath -> IO (Maybe B.ByteString)
optionalPrivate path=do
  exists<-statusMaybe path
  traverse (const $ readPrivate path) exists

snapshot :: FilePath -> Int -> String -> FilePath
snapshot journal index suffix=journal</>(show index<>"."<>suffix)

-- New configuration-lifecycle records only, not signed-attempt publication.
-- A process killed before rename leaves an unreferenced private temporary file;
-- after rename the final record already has exactly one link. Per-record locking
-- prevents cooperating publishers replacing different bytes in the crash gap.
-- Locks are persistent and must never be unlinked. Readers with a smaller bound
-- (including AdminKey.readPrivate) retain that bound at their call sites.
savePrivateRecord :: FilePath -> B.ByteString -> IO ()
savePrivateRecord path bytes=do
  require (B.length bytes<=32768) "configuration_update_record_too_large"
  checkJournal (takeDirectory path)
  withFamily (path<>".record-publication") $ do
    exists<-statusMaybe path
    case exists of
      Just _->verifyExisting
      Nothing->do
        randomBytes<-getRandomBytes 16
        let staging=path<>".pending-"<>T.unpack(digest randomBytes)
            cleanup=do
              remaining<-statusMaybe staging
              forM_ remaining $ const $ removeFile staging >> syncParent staging
        (bracket (openFd staging WriteOnly defaultFileFlags
          {creat=Just 0o600,exclusive=True,nofollow=True,cloexec=True}) closeFd $ \fd->do
            withHandle fd $ \handle->B.hPut handle bytes >> hFlush handle
            fileSynchronise fd
            -- Protected parents plus the record lock exclude other lifecycle
            -- writers. Refuse an unexpected publication instead of overwriting.
            current<-statusMaybe path
            case current of
              Just _->verifyExisting
              Nothing->renameFile staging path
            syncParent path) `finally` cleanup
    syncParent path
 where
  verifyExisting=do
    actual<-readRegular path 0o600 Nothing Nothing
    require (actual==bytes) "configuration_update_snapshot_changed"
    syncFile path

publish :: ConfigFile -> IO ()
publish file=do
  randomBytes<-getRandomBytes 16
  let destination=configPath file
      staging=destination<>".configuration-update-"<>T.unpack(digest randomBytes)
      cleanup=do
        exists<-statusMaybe staging
        forM_ exists $ const $ removeFile staging >> syncParent staging
  (bracket (openFd staging WriteOnly defaultFileFlags {creat=Just 0o600,exclusive=True,nofollow=True,cloexec=True}) closeFd $ \fd->do
    withHandle fd $ \handle->B.hPut handle (configAfter file) >> hFlush handle
    setFdOwnerAndGroup fd (configOwner file) (configGroup file)
    setFdMode fd (configMode file)
    fileSynchronise fd
    actual<-readTarget file
    require (actual==configBefore file || actual==Just(configAfter file)) "configuration_update_target_changed"
    renameFile staging destination
    syncParent destination) `finally` cleanup

syncFile :: FilePath -> IO ()
syncFile path=bracket (openFd path ReadOnly defaultFileFlags {nofollow=True,cloexec=True,nonBlock=True}) closeFd fileSynchronise

syncParent :: FilePath -> IO ()
syncParent path=bracket (openFd (takeDirectory path) ReadOnly defaultFileFlags {nofollow=True,cloexec=True,directory=True}) closeFd fileSynchronise
