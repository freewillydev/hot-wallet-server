{-# LANGUAGE DeriveGeneric #-}
-- Private directory retirement only. The root lifecycle caller owns the fixed
-- path whitelist, service stops and database retirement; no file is discarded.
module RotationFiles
  (RotationDirectory(..),stageRotationDirectories,loadRotationDirectories,publishRotationDirectories) where
import Bridge.AdminKey (readPrivate)
import ReconfigureFiles (savePrivateRecord)
import Bridge.Error (require,reject)
import Control.Exception (bracket)
import Control.Monad (forM,forM_,unless,when)
import Data.Aeson (FromJSON,ToJSON,encode,eitherDecodeStrict')
import Data.Bits ((.&.))
import Data.List (nub,isPrefixOf)
import qualified Data.ByteString as B
import qualified Data.ByteString.Lazy as L
import GHC.Generics (Generic)
import System.Directory (renameDirectory)
import System.FilePath ((</>),isAbsolute,normalise,takeDirectory,splitDirectories)
import System.IO.Error (tryIOError,isDoesNotExistError)
import qualified System.Posix.Directory as P
import System.Posix.Files
import System.Posix.IO (openFd,closeFd,OpenMode(ReadOnly),defaultFileFlags,OpenFileFlags(..))
import System.Posix.Unistd (fileSynchronise)
import System.Posix.User (getEffectiveUserID,getEffectiveGroupID)

data RotationDirectory = RotationDirectory
  { rotationSource :: FilePath, rotationDestination :: FilePath
  , rotationDevice :: Integer, rotationInode :: Integer
  , rotationOwner :: Integer, rotationGroup :: Integer, rotationMode :: Integer
  } deriving (Eq,Generic)
instance ToJSON RotationDirectory
instance FromJSON RotationDirectory
data Manifest = Manifest
  { version :: Int, journalOwner :: Integer, journalGroup :: Integer
  , suffix :: String, directories :: [RotationDirectory]
  } deriving (Eq,Generic)
instance ToJSON Manifest
instance FromJSON Manifest

-- The primitive uses its effective UID for disposable local verification. The
-- production Reconfigure entry must require root before calling it.
stageRotationDirectories :: FilePath -> String -> [FilePath] -> IO [RotationDirectory]
stageRotationDirectories journal tag paths=do
  ensureJournal journal
  let manifestPath=journal</>"rotation-directories.json"
  saved<-statusMaybe manifestPath
  case saved of
    Just _->do
      manifest<-loadManifest journal
      require (suffix manifest==tag && map rotationSource (directories manifest)==paths)
        "rotation_directory_plan_changed"
      complete<-completed journal
      mapM_ (checkEntry manifest complete) (directories manifest)
      pure (directories manifest)
    Nothing->do
      requireTag tag
      uid<-getEffectiveUserID;gid<-getEffectiveGroupID
      entries<-forM paths $ \source->do
        checkParents source
        status<-getSymbolicLinkStatus source
        checkSource status
        parent<-getSymbolicLinkStatus(takeDirectory source)
        require (deviceID status==deviceID parent) "rotation_source_mountpoint_refused"
        let target=source<>".retired-"<>tag
        statusMaybe target >>= \existing->require (maybe True (const False) existing) "rotation_archive_exists"
        pure $ RotationDirectory source target (toInteger $ deviceID status) (toInteger $ fileID status)
          (toInteger $ fileOwner status) (toInteger $ fileGroup status) (toInteger $ fileMode status .&. 0o7777)
      let manifest=Manifest 1 (toInteger uid) (toInteger gid) tag entries
      validateManifest journal manifest
      completed journal >>= \done->require (not done) "rotation_manifest_missing"
      let bytes=L.toStrict $ encode manifest
      require (B.length bytes<=8192) "rotation_directory_manifest_too_large"
      savePrivateRecord manifestPath bytes
      -- Verify the same inodes after durable publication, before any rename.
      mapM_ (checkEntry manifest False) entries
      pure entries

loadRotationDirectories :: FilePath -> IO [RotationDirectory]
loadRotationDirectories journal=directories <$> loadManifest journal

-- The caller supplies the exact previously selected whitelist again. A retry
-- never captures the inode of a newly created installation as an archive input.
publishRotationDirectories :: FilePath -> [FilePath] -> IO ()
publishRotationDirectories journal paths=do
  manifest<-loadManifest journal
  require (map rotationSource (directories manifest)==paths) "rotation_directory_plan_changed"
  complete<-completed journal
  mapM_ (checkEntry manifest complete) (directories manifest)
  unless complete $ do
    forM_ (directories manifest) $ \entry->do
      checkEntry manifest False entry
      old<-statusMaybe(rotationSource entry)
      when (maybe False (const True) old) $ do
        -- Both parents are protected and the lifecycle caller holds its lock.
        -- The destination must remain absent; never replace a directory.
        target<-statusMaybe(rotationDestination entry)
        require (maybe True (const False) target) "rotation_archive_exists"
        renameDirectory (rotationSource entry) (rotationDestination entry)
        syncDirectory (takeDirectory $ rotationSource entry)
        syncDirectory (takeDirectory $ rotationDestination entry)
      protectArchive manifest entry
      checkEntry manifest False entry
    -- Completion precedes permission for any source path to be reused.
    forM_ (directories manifest) $ \entry->do
      source<-statusMaybe(rotationSource entry)
      require (maybe True (const False) source) "rotation_source_recreated_before_completion"
      checkArchive manifest True entry =<< getSymbolicLinkStatus(rotationDestination entry)
    savePrivateRecord (journal</>"rotation-directories.complete") completion
  mapM_ (checkEntry manifest True) (directories manifest)

completion :: B.ByteString
completion="rotation-directories-v1\n"

completed :: FilePath -> IO Bool
completed journal=do
  let path=journal</>"rotation-directories.complete"
  exists<-statusMaybe path
  case exists of
    Nothing->pure False
    Just _->readPrivate path >>= \bytes->require (bytes==completion) "invalid_rotation_directory_completion" >> pure True

loadManifest :: FilePath -> IO Manifest
loadManifest journal=do
  checkJournal journal
  bytes<-readPrivate(journal</>"rotation-directories.json")
  manifest<-either (const $ reject "invalid_rotation_directory_manifest") pure (eitherDecodeStrict' bytes)
  require (bytes==L.toStrict(encode manifest)) "invalid_rotation_directory_manifest"
  validateManifest journal manifest
  pure manifest

validateManifest :: FilePath -> Manifest -> IO ()
validateManifest journal manifest=do
  uid<-getEffectiveUserID;gid<-getEffectiveGroupID
  require (version manifest==1 && journalOwner manifest==toInteger uid && journalGroup manifest==toInteger gid)
    "invalid_rotation_directory_manifest"
  requireTag (suffix manifest)
  let entries=directories manifest
      sources=map rotationSource entries
      targets=map rotationDestination entries
      identities=[(rotationDevice entry,rotationInode entry)|entry<-entries]
      contains parent child=parent==child || (parent<>"/") `isPrefixOf` child
  require (not(null entries) && length entries<=16 && length(nub sources)==length sources
    && length(nub targets)==length targets && length(nub identities)==length identities)
    "invalid_rotation_directory_targets"
  forM_ entries $ \entry->do
    let source=rotationSource entry;target=rotationDestination entry
    validPath source;validPath target
    require (target==source<>".retired-"<>suffix manifest
      && rotationDevice entry>=0 && rotationInode entry>0
      && rotationOwner entry `elem` [0,toInteger uid] && rotationGroup entry>=0
      && rotationMode entry>=0 && rotationMode entry<=0o777
      && rotationMode entry .&. 0o022==0
      && not(contains source journal) && not(contains target journal)) "invalid_rotation_directory_target"
    forM_ entries $ \other->when (rotationSource other/=source) $
      require (not(contains source (rotationSource other)) && not(contains source (rotationDestination other))
        && not(contains target (rotationSource other)) && not(contains target (rotationDestination other)))
        "overlapping_rotation_directories"

checkEntry :: Manifest -> Bool -> RotationDirectory -> IO ()
checkEntry manifest complete entry=do
  checkParents(rotationSource entry);checkParents(rotationDestination entry)
  source<-statusMaybe(rotationSource entry)
  target<-statusMaybe(rotationDestination entry)
  case (source,target) of
    (Just original,Nothing)->do
      require (not complete) "rotation_archive_missing"
      checkSource original
      require (sameInode entry original && toInteger(fileOwner original)==rotationOwner entry
        && toInteger(fileGroup original)==rotationGroup entry
        && toInteger(fileMode original .&. 0o7777)==rotationMode entry) "rotation_source_changed"
    (Nothing,Just archived)->checkArchive manifest complete entry archived
    (Just replacement,Just archived)->do
      require complete "rotation_source_recreated_before_completion"
      checkArchive manifest True entry archived
      checkSource replacement
      require (not $ sameInode entry replacement) "rotation_source_identity_reused"
    (Nothing,Nothing)->reject "rotation_directory_missing"

sameInode :: RotationDirectory -> FileStatus -> Bool
sameInode entry status=toInteger(deviceID status)==rotationDevice entry && toInteger(fileID status)==rotationInode entry

checkArchive :: Manifest -> Bool -> RotationDirectory -> FileStatus -> IO ()
checkArchive manifest complete entry status=do
  require (isDirectory status && sameInode entry status) "rotation_archive_changed"
  let owner=toInteger(fileOwner status);group=toInteger(fileGroup status)
      mode=toInteger(fileMode status .&. 0o7777)
      hardened=owner==journalOwner manifest && group==journalGroup manifest && mode==0o700
      partial=owner `elem` [rotationOwner entry,journalOwner manifest]
        && group `elem` [rotationGroup entry,journalGroup manifest] && mode `elem` [rotationMode entry,0o700]
  require (if complete then hardened else partial) "unsafe_rotation_archive"

protectArchive :: Manifest -> RotationDirectory -> IO ()
protectArchive manifest entry=bracket
  (openFd (rotationDestination entry) ReadOnly defaultFileFlags {nofollow=True,cloexec=True,directory=True}) closeFd $ \fd->do
    status<-getFdStatus fd
    checkArchive manifest False entry status
    -- Change the archived root only. Credential owners and file modes below it
    -- are retained exactly, while this parent prevents old services accessing it.
    setFdOwnerAndGroup fd (fromInteger $ journalOwner manifest) (fromInteger $ journalGroup manifest)
    setFdMode fd 0o700
    fileSynchronise fd
    syncDirectory(takeDirectory $ rotationSource entry)
    syncDirectory(takeDirectory $ rotationDestination entry)

checkSource :: FileStatus -> IO ()
checkSource status=do
  uid<-getEffectiveUserID
  require (isDirectory status && fileOwner status `elem` [0,uid]
    && fileMode status .&. 0o7022==0) "unsafe_rotation_source"

requireTag :: String -> IO ()
requireTag tag=require (length tag==32 && all (`elem` ("0123456789abcdef"::String)) tag) "invalid_rotation_suffix"

validPath :: FilePath -> IO ()
validPath path=require (isAbsolute path && normalise path==path && path/="/" && length path<=4096
  && all (\c->c>=' ' && c/='\DEL') path && all (`notElem` [".",".."]) (splitDirectories path))
  "invalid_rotation_directory_path"

checkParents :: FilePath -> IO ()
checkParents path=do
  validPath path
  uid<-getEffectiveUserID
  let ancestors directory=if directory=="/" then ["/"] else ancestors(takeDirectory directory)<>[directory]
  forM_ (ancestors $ takeDirectory path) $ \directory->do
    status<-getSymbolicLinkStatus directory
    require (isDirectory status && fileOwner status `elem` [0,uid] && fileMode status .&. 0o022==0)
      "unsafe_rotation_directory_parent"

ensureJournal :: FilePath -> IO ()
ensureJournal journal=do
  checkParents journal
  existing<-statusMaybe journal
  case existing of
    Nothing->P.createDirectory journal 0o700 >> syncDirectory(takeDirectory journal)
    Just _->pure ()
  checkJournal journal

checkJournal :: FilePath -> IO ()
checkJournal journal=do
  checkParents journal
  uid<-getEffectiveUserID
  status<-getSymbolicLinkStatus journal
  require (isDirectory status && fileOwner status==uid && fileMode status .&. 0o7777==0o700)
    "unsafe_rotation_directory_journal"

statusMaybe :: FilePath -> IO (Maybe FileStatus)
statusMaybe path=do
  result<-tryIOError (getSymbolicLinkStatus path)
  case result of
    Right status->pure(Just status)
    Left errorValue | isDoesNotExistError errorValue->pure Nothing
    Left errorValue->ioError errorValue

syncDirectory :: FilePath -> IO ()
syncDirectory path=bracket (openFd path ReadOnly defaultFileFlags {nofollow=True,cloexec=True,directory=True}) closeFd fileSynchronise
