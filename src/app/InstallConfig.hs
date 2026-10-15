{-# LANGUAGE ScopedTypeVariables #-}
-- Installation input is data, parsed by Read; it is never evaluated as Haskell.
-- Deliberately no Show instance: the record contains credentials and private keys.
module InstallConfig (InstallConfig(..),InstallPlan(..),SidechainInstall(..),readInstallPlan,readInstallConfig,validateInstallConfig,validateInstallPlan,updateSettings) where
import Bridge.AdminKey (readPrivate)
import Bridge.Domain (Asset(..),parseCoins,units)
import Bridge.Wire (Profile(..))
import Bridge.Error
import Bridge.Identity (publicKey)
import Bridge.RPC (independentHttps)
import Bridge.NativeKey (validNetworkXpub)
import Bridge.Wallet (nativeDescriptors,protectWalletProcess)
import Control.Exception (catch)
import Control.Monad (forM_)
import Data.List (isPrefixOf,stripPrefix,nub)
import Data.Maybe (fromMaybe,isJust)
import Data.IP (IP)
import Data.Aeson (Value,object,(.=))
import Crypto.Error (CryptoFailable(..))
import qualified Crypto.PubKey.Ed25519 as Ed
import qualified Data.ByteArray as BA
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
  , ecxSeedBip39 :: String, solKeyB58 :: String, assetMintAddress :: String
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

-- An optional wrapper selects real ECX Signet and its receiving nodes. The
-- original record remains the canonical wrap/unwrap-only configuration.
data InstallPlan = InstallPlan
  { installNetwork :: Profile, installBridge :: InstallConfig
  , installSidechains :: [SidechainInstall] } deriving (Read,Eq)
data SidechainInstall = SidechainInstall
  { sidechain :: Asset, sidechainSeedBip39 :: String
  , fastWithdrawalFeeBps :: Int, ecxConfirmations :: Int } deriving (Read,Eq)

readInstallPlan :: FilePath -> IO (B.ByteString,InstallPlan)
readInstallPlan file=do
  bytes<-readPrivate file
  plan<-case readEither (B8.unpack bytes) of
    Right value->pure value
    Left _->case readEither (B8.unpack bytes) of
      Right value->pure(InstallPlan CanonicalBeta value [])
      Left _->reject "invalid_haskell_install_record"
  _<-validateInstallPlan plan
  pure(bytes,plan)
readInstallConfig :: FilePath -> IO (B.ByteString,InstallConfig)
readInstallConfig file=do
  (bytes,plan)<-readInstallPlan file
  pure(bytes,installBridge plan)

validateInstallPlan :: InstallPlan -> IO B.ByteString
validateInstallPlan (InstallPlan network settings chains)=do
  require (network `elem` [CanonicalBeta,L2LSignetDevnet]) "unsupported_install_network"
  require (null chains || network==L2LSignetDevnet) "sidechains_require_ecx_signet"
  require (length chains<=2 && length(nub $ map sidechain chains)==length chains) "duplicate_sidechain"
  forM_ chains $ \chain->do
    require (sidechain chain `elem` [Thunder,BitNames] && ecxConfirmations chain>=6
      && ecxConfirmations chain<=1008 && fastWithdrawalFeeBps chain>=0 && fastWithdrawalFeeBps chain<10000) "invalid_sidechain_policy"
    -- Same BIP39 validator used for native import; no generated fallback seed.
    _<-nativeDescriptors True (sidechainSeedBip39 chain) >>= either reject pure
    pure ()
  require (length(nub $ map sidechainSeedBip39 chains)==length chains
    && all ((/=ecxSeedBip39 settings).sidechainSeedBip39) chains) "distinct_sidechain_seeds_required"
  validateInstallFor network settings

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
-- only the decoded Solana key bytes to the private configuration publisher.
validateInstallConfig :: InstallConfig -> IO B.ByteString
validateInstallConfig=validateInstallFor CanonicalBeta

validateInstallFor :: Profile -> InstallConfig -> IO B.ByteString
validateInstallFor network c=do
  require (freshCustodyAttestation c=="NEW_UNUSED_KEYS_WITH_NO_EXISTING_BRIDGE_LEDGER") "fresh_unused_custody_attestation_required"
  require (not(null $ initialFundingOwnership c) && length(initialFundingOwnership c)<=512) "initial_funding_ownership_statement_required"
  _<-nativeDescriptors (network==L2LSignetDevnet) (ecxSeedBip39 c) >>= either reject pure
  key<-case B58.decodeBase58 B58.bitcoinAlphabet (TE.encodeUtf8 $ T.pack $ solKeyB58 c) of
    Just bytes | B.length bytes==64->pure bytes
    _->reject "expected_base58_solana_64_byte_private_key"
  secret<-case Ed.secretKey(B.take 32 key) of
    CryptoPassed value->pure value
    _->reject "invalid_imported_key"
  require ((BA.convert(Ed.toPublic secret)::B.ByteString)==B.drop 32 key) "imported_key_public_half_mismatch"
  require (network/=CanonicalBeta || assetMintAddress c=="EVHqNdzjCupKi4rQkbuYw52sa1m8A7jeUAMP23S9AVVq") "canonical_mint_required"
  _<-either reject pure (publicKey $ T.pack $ assetMintAddress c)
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
  validNetworkXpub (network==L2LSignetDevnet) (T.pack $ ownerEcxXpub c) >>= (`require` "owner_ecx_xpub_required")
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
