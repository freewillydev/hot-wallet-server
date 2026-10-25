-- Build-tree fallbacks support developers; installed setup uses its own bundle.
module SetupPaths (bundleRoot,sdkPath,nodeInstaller) where
import Bridge.SDKBuild (sdkLibraryPath,sdkSourceDirectory)
import Bridge.Error (reject)
import System.Environment (getExecutablePath)
import System.Directory (canonicalizePath,doesFileExist)
import System.FilePath ((</>),takeDirectory)

bundleRoot :: IO (Maybe FilePath)
bundleRoot=do
  root<-takeDirectory . takeDirectory <$> (getExecutablePath >>= canonicalizePath)
  exists<-doesFileExist(root</>"manifest.sha256")
  pure(if exists then Just root else Nothing)

sdkPath :: IO FilePath
sdkPath=maybe sdkLibraryPath (</>"lib/libecx_solana_sdk.so") <$> bundleRoot

-- Source updates must run the helper from the current build, even when resuming
-- a setup whose sealed sourceRoot records an older checkout. Bundle setup keeps
-- its original manifest-verified helper; never fall back across trust modes.
nodeInstaller :: String -> FilePath -> IO FilePath
nodeInstaller "source" _=(</>"build/install/node") <$> canonicalizePath (sdkSourceDirectory</>"../..")
nodeInstaller "bundle" root=pure(root</>"node")
nodeInstaller _ _=reject "managed_node_release_bootstrap_required"
