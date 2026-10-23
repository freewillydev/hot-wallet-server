{-# LANGUAGE ScopedTypeVariables #-}
-- Installation input is data, parsed by Read; it is never evaluated as Haskell.
-- Deliberately no Show instance: the record contains credentials and private keys.
module InstallConfig (InstallConfig(..),readInstallConfig,readInstallConfigUpdate,validateOperationalUpdate,validateInstallConfig,updateSettings) where
import Bridge.AdminKey (readPrivate)
import Bridge.Domain (parseCoins,units)
import Bridge.Error
import Bridge.Identity (publicKey)
import Bridge.RPC (independentHttps)
import Bridge.NativeKey (validMainnetXpub)
import Bridge.Wallet (nativeDescriptors,walletKey,protectWalletProcess)
import Control.Exception (catch)
import Control.Monad (forM_,guard)
import Crypto.Error (CryptoFailable(..))
import qualified Crypto.PubKey.Ed25519 as Ed
import qualified Data.ByteArray as BA
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

-- Read the candidate as the current schema only. Legacy key records are accepted
-- solely as the protected previous record for identity comparison; a key cannot
-- be converted back into recovery words. Return native/Solana rotation separately.
readInstallConfigUpdate :: FilePath -> FilePath -> IO (B.ByteString,InstallConfig,B.ByteString,(Bool,Bool))
readInstallConfigUpdate previous candidate=do
  protectWalletProcess
  bytes<-readPrivate candidate
  config<-either (const $ reject "invalid_haskell_install_record") pure (readEither $ B8.unpack bytes)
  key<-validateInstallConfig config
  (old,oldKey)<-readPreviousInstallConfig previous
  oldNative<-nativeDescriptors False (ecxSeedBip39 old) >>= either reject pure
  newNative<-nativeDescriptors False (ecxSeedBip39 config) >>= either reject pure
  pure(bytes,config,key,(oldNative/=newNative,B.drop 32 oldKey/=B.drop 32 key))

readPreviousInstallConfig :: FilePath -> IO (InstallConfig,B.ByteString)
readPreviousInstallConfig previous=do
  oldBytes<-readPrivate previous
  case readMaybe (B8.unpack oldBytes) of
    Just current->do
      currentKey<-validateInstallConfig current
      pure(current,currentKey)
    Nothing->do
      legacy<-maybe (reject "invalid_previous_install_record") pure (legacyInstallConfig $ B8.unpack oldBytes)
      legacyKey<-validateWithSolanaKey legacy (readLegacyKey $ solSeedBip39 legacy)
      pure(legacy,legacyKey)

-- Runtime publication currently supports this explicit operational subset. Other
-- changes need their own custody/backup/recipient/website workflow, even when the
-- replacement record is individually valid.
validateOperationalUpdate :: FilePath -> FilePath -> IO ()
validateOperationalUpdate previous candidate=do
  (_,config,_,changed)<-readInstallConfigUpdate previous candidate
  require (changed==(False,False)) "operational_update_wallet_identity_changed"
  (old,_)<-readPreviousInstallConfig previous
  let allowed=old
        { serverIp=serverIp config,domain=domain config,cloudflareTunnelToken=cloudflareTunnelToken config
        , ecxSeedBip39=ecxSeedBip39 config,solSeedBip39=solSeedBip39 config
        , solanaRpcUrl=solanaRpcUrl config,solanaVerifierRpcUrl=solanaVerifierRpcUrl config
        , payoutThresholdEcx=payoutThresholdEcx config,payoutThresholdWrappedEcx=payoutThresholdWrappedEcx config
        , minimumPayoutIntervalHours=minimumPayoutIntervalHours config
        , externalLinkSolscan=externalLinkSolscan config,externalLinkOrca=externalLinkOrca config
        , updatePublicKey=updatePublicKey config,updateReleaseDirectory=updateReleaseDirectory config
        , updateSetupDirectory=updateSetupDirectory config }
  require (allowed==config) "operational_update_field_requires_review"

-- Tokenize before translating the single old field name: strings, including
-- passwords and ownership statements, must never be searched/replaced as text.
-- The temporary record stays private to this module; its renamed field contains
-- the old key only until validation/comparison, and is never used as a mnemonic.
legacyInstallConfig :: String -> Maybe InstallConfig
legacyInstallConfig input=do
  tokens<-tokenize input
  guard (length(filter (=="solKeyB58") tokens)==1 && "solSeedBip39" `notElem` tokens)
  readMaybe $ unwords [if token=="solKeyB58" then "solSeedBip39" else token | token<-tokens]
 where
  tokenize remaining=case lex remaining of
    [("","")]->Just []
    [(token,rest)] | not(null token)->(token:) <$> tokenize rest
    _->Nothing

readLegacyKey :: String -> IO B.ByteString
readLegacyKey encoded=do
  let bytes=TE.encodeUtf8 (T.pack encoded)
  key<-maybe (reject "invalid_previous_solana_key") pure (B58.decodeBase58 B58.bitcoinAlphabet bytes)
  require (B.length key==64 && B58.encodeBase58 B58.bitcoinAlphabet key==bytes) "invalid_previous_solana_key"
  case Ed.secretKey (B.take 32 key) of
    CryptoPassed secret->require (B.drop 32 key==(BA.convert (Ed.toPublic secret)::B.ByteString)) "invalid_previous_solana_key"
    CryptoFailed _->reject "invalid_previous_solana_key"
  pure key

-- Export only non-secret update paths; never source/evaluate the record as shell.
updateSettings :: FilePath -> IO Value
updateSettings file=do
  protectWalletProcess
  (_,config)<-readInstallConfig file
  pure $ object ["publicKey" .= updatePublicKey config,"release" .= updateReleaseDirectory config
    ,"setup" .= updateSetupDirectory config]

-- Validate the entire input before creating any installation material. Return
-- only the derived Solana key bytes to the private configuration publisher.
validateInstallConfig :: InstallConfig -> IO B.ByteString
validateInstallConfig c=validateWithSolanaKey c (either reject pure $ walletKey $ solSeedBip39 c)

validateWithSolanaKey :: InstallConfig -> IO B.ByteString -> IO B.ByteString
validateWithSolanaKey c readSolanaKey=do
  require (freshCustodyAttestation c=="NEW_UNUSED_KEYS_WITH_NO_EXISTING_BRIDGE_LEDGER") "fresh_unused_custody_attestation_required"
  require (not(null $ initialFundingOwnership c) && length(initialFundingOwnership c)<=512) "initial_funding_ownership_statement_required"
  _<-nativeDescriptors False (ecxSeedBip39 c) >>= either reject pure
  key<-readSolanaKey
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
  forM_ [updatePublicKey c,updateReleaseDirectory c,updateSetupDirectory c] $ \path->
    require (isAbsolute path && normalise path==path && length path<=4096
      && all (\character->character>=' ' && character/='\DEL') path) "absolute_update_paths_required"
  pure key

-- Configuration publication uses ASCII URI bytes. Require percent-encoding for
-- non-ASCII input, and never include credential-bearing parser errors in output.
validateHttps :: String -> IO ()
validateHttps url=do
  require ("https://" `isPrefixOf` url && all (\c->c>' ' && c<='~') url) "https_url_required"
  request<-parseRequest url `catch` (\(_::HttpException)->reject "invalid_https_url")
  require (secure request && not(B.null $ host request)) "invalid_https_url"
