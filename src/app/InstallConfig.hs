{-# LANGUAGE ScopedTypeVariables #-}
-- Installation input is data, parsed by Read; it is never evaluated as Haskell.
-- Deliberately no Show instance: the record contains credentials and private keys.
module InstallConfig (InstallConfig(..),readInstallConfig,validateInstallConfig,updateSettings) where
import Bridge.AdminKey (readPrivate)
import Bridge.Domain (parseCoins,units)
import Bridge.Error
import Bridge.Identity (publicKey)
import Bridge.RPC (independentHttps)
import Bridge.NativeKey (validMainnetXpub)
import Bridge.Wallet (nativeDescriptors,walletKey,protectWalletProcess)
import Control.Exception (catch)
import Control.Monad (forM_)
import Data.List (isPrefixOf,stripPrefix)
import Data.Maybe (fromMaybe,isJust)
import Data.IP (IP)
import Data.Aeson (Value,object,(.=))
import qualified Data.ByteString as B
import qualified Data.ByteString.Base58 as B58
import qualified Data.ByteString.Char8 as B8
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Network.HTTP.Client (parseRequest,HttpException,secure,host)
import System.FilePath (isAbsolute,normalise)
import Text.Read (readEither,readMaybe)

data InstallConfig = InstallConfig
  { serverIp :: String, domain :: String
  , websiteDirectory :: Maybe FilePath
  , cloudflareTunnelToken :: Maybe String
  , ecxSeedBip39 :: String, solSeedBip39 :: String, assetMintAddress :: String
  , feeRateWrapBps :: Int, feeRateUnwrapBps :: Int
  , payoutThresholdEcx :: String, payoutThresholdWrappedEcx :: String
  , minimumPayoutIntervalHours :: Integer
  , ownerEcxXpub :: String, ownerSolPubkey :: String
  , externalLinkSolscan :: String, externalLinkOrca :: String
  , solanaRpcUrl :: String, solanaVerifierRpcUrl :: String
  , backupRepositoryUrl :: String, backupPassword :: String
  , resticExecutable :: FilePath
  , updatePublicKey :: FilePath, updateReleaseDirectory :: FilePath, updateSetupDirectory :: FilePath
  , freshCustodyAttestation :: String, initialFundingOwnership :: String
  } deriving (Read,Eq)

readInstallConfig :: FilePath -> IO (B.ByteString,InstallConfig)
readInstallConfig file=do
  bytes<-readPrivate file
  config<-either (const $ reject "invalid_haskell_install_record") pure (readEither $ B8.unpack bytes)
  _<-validateInstallConfig config
  pure(bytes,config)

-- Export only non-secret update paths; never source/evaluate the record as shell.
updateSettings :: FilePath -> IO Value
updateSettings file=do
  protectWalletProcess
  (_,config)<-readInstallConfig file
  let paths=[updatePublicKey config,updateReleaseDirectory config,updateSetupDirectory config]
  forM_ paths $ \path->require (isAbsolute path && normalise path==path && length path<=4096
    && all (\c->c>=' ' && c/='\DEL') path) "absolute_update_paths_required"
  pure $ object ["publicKey" .= updatePublicKey config,"release" .= updateReleaseDirectory config
    ,"setup" .= updateSetupDirectory config]

-- Validate the entire input before creating any installation material. Return
-- only the derived Solana key bytes to the private configuration publisher.
validateInstallConfig :: InstallConfig -> IO B.ByteString
validateInstallConfig c=do
  require (freshCustodyAttestation c=="NEW_UNUSED_KEYS_WITH_NO_EXISTING_BRIDGE_LEDGER") "fresh_unused_custody_attestation_required"
  require (not(null $ initialFundingOwnership c) && length(initialFundingOwnership c)<=512) "initial_funding_ownership_statement_required"
  _<-nativeDescriptors False (ecxSeedBip39 c) >>= either reject pure
  key<-either reject pure (walletKey $ solSeedBip39 c)
  require (assetMintAddress c=="EVHqNdzjCupKi4rQkbuYw52sa1m8A7jeUAMP23S9AVVq") "canonical_mint_required"
  require (feeRateWrapBps c==100 && feeRateUnwrapBps c==100) "supported_fee_is_100_basis_points"
  forM_ [payoutThresholdEcx c,payoutThresholdWrappedEcx c] $ \value->do
    amount<-either reject pure (parseCoins $ T.pack value)
    require (units amount>0) "positive_payout_threshold_required"
  require (minimumPayoutIntervalHours c>=0 && minimumPayoutIntervalHours c<=8760) "payout_interval_hours_out_of_range"
  forM_ [solanaRpcUrl c,solanaVerifierRpcUrl c,externalLinkSolscan c,externalLinkOrca c] validateHttps
  independentHttps (solanaRpcUrl c) (solanaVerifierRpcUrl c)
    `catch` (\(_::HttpException)->reject "invalid_rpc_endpoints")
  let backup=fromMaybe (backupRepositoryUrl c) (stripPrefix "rest:" $ backupRepositoryUrl c)
  validateHttps backup
  require ('#' `notElem` backup) "backup_repository_fragment_not_allowed"
  require (length(backupPassword c)>=16 && not(any (`elem` ['\n','\r','\0']) (backupPassword c))) "backup_password_minimum_16_characters"
  require (isAbsolute $ resticExecutable c) "absolute_reviewed_restic_path_required"
  _<-either reject pure (publicKey $ T.pack $ ownerSolPubkey c)
  require (TE.encodeUtf8 (T.pack $ ownerSolPubkey c)/=B58.encodeBase58 B58.bitcoinAlphabet (B.drop 32 key)) "bridge_owned_destination"
  validMainnetXpub (T.pack $ ownerEcxXpub c) >>= (`require` "owner_ecx_xpub_required")
  let labels=T.splitOn "." (T.pack $ domain c)
      alphanumeric character=character `elem` (['a'..'z']<>['0'..'9'])
      label value=not(T.null value) && T.length value<=63
        && alphanumeric(T.head value) && alphanumeric(T.last value)
        && T.all (\character->alphanumeric character || character=='-') value
  require (length(domain c)<=253 && all label labels) "invalid_domain"
  require (length(serverIp c)<=45 && all (`elem` ("0123456789abcdefABCDEF:."::String)) (serverIp c)
    && isJust (readMaybe (serverIp c) :: Maybe IP)) "invalid_server_ip"
  forM_ (cloudflareTunnelToken c) $ \token->require (length token>=32 && length token<=4096
    && all (`elem` (['a'..'z']<>['A'..'Z']<>['0'..'9']<>"+/=_-")) token) "invalid_cloudflare_tunnel_token"
  forM_ (websiteDirectory c) $ \path->require (isAbsolute path && normalise path==path && length path<=4096
    && all (\character->character>=' ' && character/='\DEL') path) "absolute_website_directory_required"
  pure key

-- Configuration publication uses ASCII URI bytes. Require percent-encoding for
-- non-ASCII input, and never include credential-bearing parser errors in output.
validateHttps :: String -> IO ()
validateHttps url=do
  require ("https://" `isPrefixOf` url && all (\c->c>' ' && c<='~') url) "https_url_required"
  request<-parseRequest url `catch` (\(_::HttpException)->reject "invalid_https_url")
  require (secure request && not(B.null $ host request)) "invalid_https_url"
