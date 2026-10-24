{-# LANGUAGE ScopedTypeVariables #-}
-- Installation input is data, parsed by Read; it is never evaluated as Haskell.
-- Deliberately no Show instance: the record contains credentials and private keys.
module InstallConfig (InstallConfig(..),readInstallConfig,readInstallConfigUpdate,backupSetupUpdate,validateOperationalUpdate,validateInstallConfig,updateSettings) where
import Bridge.AdminKey (readPrivate)
import Bridge.Domain (parseCoins,units)
import Bridge.Error
import Bridge.Identity (publicKey)
import Bridge.RPC (independentHttps)
import Bridge.NativeKey (validOwnerDestination)
import Bridge.Wallet (nativeDescriptors,walletKey,protectWalletProcess)
import Control.Exception (catch)
import Control.Monad (forM_,unless,when)
import Crypto.Error (CryptoFailable(..))
import qualified Crypto.PubKey.Ed25519 as Ed
import qualified Data.ByteArray as BA
import Data.List (isPrefixOf,stripPrefix,intercalate)
import Data.Char (isSpace)
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
import Text.Read (readMaybe)

data InstallConfig = InstallConfig
  { serverIp :: String, domain :: String
  , websiteDirectory :: Maybe FilePath
  , cloudflareTunnelToken :: Maybe String
  , ecxSeedBip39 :: String, solSeedBip39 :: String, assetMintAddress :: String
  , feeRateWrapBps :: Int, feeRateUnwrapBps :: Int
  , payoutThresholdEcx :: String, payoutThresholdWrappedEcx :: String
  , minimumPayoutIntervalHours :: Integer
  , ownerEcxXpub :: String, ownerSolPubkey :: String -- ECX receive address or legacy xpub
  , externalLinkSolscan :: String, externalLinkOrca :: String
  , solanaRpcUrl :: String, solanaVerifierRpcUrl :: String
  , backupRepositoryUrl :: String, backupPassword :: String
  , resticExecutable :: FilePath
  , updatePublicKey :: FilePath, updateReleaseDirectory :: FilePath, updateSetupDirectory :: FilePath
  , freshCustodyAttestation :: String, initialFundingOwnership :: String
  } deriving (Read,Eq)

readInstallConfig :: FilePath -> IO (B.ByteString,InstallConfig)
readInstallConfig file=do
  protectWalletProcess
  bytes<-readPrivate file
  (config,_)<-either reject pure (parseInstallRecord False $ B8.unpack bytes)
  _<-validateInstallConfig config
  pure(bytes,config)

-- Read the candidate as the current schema only. Legacy key records are accepted
-- solely as the protected previous record for identity comparison; a key cannot
-- be converted back into recovery words. Return native/Solana rotation separately.
readInstallConfigUpdate :: FilePath -> FilePath -> IO (B.ByteString,InstallConfig,B.ByteString,(Bool,Bool))
readInstallConfigUpdate previous candidate=do
  protectWalletProcess
  bytes<-readPrivate candidate
  (config,_)<-either reject pure (parseInstallRecord False $ B8.unpack bytes)
  key<-validateInstallConfig config
  (old,oldKey)<-readPreviousInstallConfig previous
  oldNative<-nativeDescriptors False (ecxSeedBip39 old) >>= either reject pure
  newNative<-nativeDescriptors False (ecxSeedBip39 config) >>= either reject pure
  pure(bytes,config,key,(oldNative/=newNative,B.drop 32 oldKey/=B.drop 32 key))

readPreviousInstallConfig :: FilePath -> IO (InstallConfig,B.ByteString)
readPreviousInstallConfig previous=do
  oldBytes<-readPrivate previous
  readPreviousRecord oldBytes

readPreviousRecord :: B.ByteString -> IO (InstallConfig,B.ByteString)
readPreviousRecord oldBytes=do
  (old,legacy)<-either (reject . ("Saved installation: "<>)) pure (parseInstallRecord True $ B8.unpack oldBytes)
  key<-if legacy then validateWithSolanaKey old (readLegacyKey $ solSeedBip39 old) else validateInstallConfig old
  pure(old,key)

-- Only credential correction, not a runtime backup migration or custody change.
-- The caller must additionally prove that installation has not progressed.
backupSetupUpdate :: B.ByteString -> InstallConfig -> IO (Maybe InstallConfig)
backupSetupUpdate bytes config=do
  (old,_)<-readPreviousRecord bytes
  pure $ if old/=config && old {backupRepositoryUrl=backupRepositoryUrl config
    ,backupPassword=backupPassword config}==config then Just old else Nothing

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
        , ownerEcxXpub=ownerEcxXpub config,ownerSolPubkey=ownerSolPubkey config
        , externalLinkSolscan=externalLinkSolscan config,externalLinkOrca=externalLinkOrca config
        , updatePublicKey=updatePublicKey config,updateReleaseDirectory=updateReleaseDirectory config
        , updateSetupDirectory=updateSetupDirectory config }
  require (allowed==config) "operational_update_field_requires_review"

-- Read still decodes every value and the final record; no Haskell is evaluated.
-- Normalize only for parsing: preserve original private bytes in saved records.
-- Diagnostic text contains only static names/instructions and line numbers,
-- never values, unknown identifiers, or the underlying Read error.
parseInstallRecord :: Bool -> String -> Either T.Text (InstallConfig,Bool)
parseInstallRecord allowLegacy input=do
  tokens<-tokenize 1 input
  fields<-case unwrap tokens of
    (_,"InstallConfig"):(_,"{"):rest->assignments [] rest
    _->bad 1 "expected InstallConfig { field = value, ... }"
  let legacy=any ((=="solKeyB58").fst) fields
      normalized=[(if name=="solKeyB58" then "solSeedBip39" else name,value) | (name,value)<-fields]
      missing=[name | name<-fieldNames,not(isJust $ lookup name normalized)]
  unless (null missing) (bad 0 $ "missing fields: "<>intercalate ", " missing)
  when (legacy && isJust(lookup "solSeedBip39" fields)) (bad 0 "use only solSeedBip39, not both Solana key fields")
  let record="InstallConfig {"<>intercalate "," [name<>" = "<>value | name<-fieldNames,Just value<-[lookup name normalized]]<>"}"
  case readMaybe record of
    Just config->Right(config,legacy)
    Nothing->bad 0 "check field value types against example.conf"
 where
  -- Declaration order for derived Read. Every field remains mandatory; no
  -- missing credential, fee, or custody setting is silently defaulted.
  fieldNames=words $ "serverIp domain websiteDirectory cloudflareTunnelToken ecxSeedBip39 solSeedBip39 assetMintAddress "<>
    "feeRateWrapBps feeRateUnwrapBps payoutThresholdEcx payoutThresholdWrappedEcx minimumPayoutIntervalHours "<>
    "ownerEcxXpub ownerSolPubkey externalLinkSolscan externalLinkOrca solanaRpcUrl solanaVerifierRpcUrl "<>
    "backupRepositoryUrl backupPassword resticExecutable updatePublicKey updateReleaseDirectory updateSetupDirectory "<>
    "freshCustodyAttestation initialFundingOwnership"
  bad :: Int -> String -> Either T.Text a
  bad line message=Left $ T.pack $ "Invalid Haskell install record"<>
    (if line==0 then "" else " at line "<>show line)<>": "<>message<>". Config values are hidden."
  unwrap tokens@((_,"("):rest)=case reverse rest of
    (_, pin):more | pin==")"->unwrap(reverse more)
    _->tokens
  unwrap tokens=tokens
  assignments _ []=bad 0 "missing closing }"
  assignments fields [(_,"}")]=Right fields
  assignments fields ((line,name):(_,"="):rest)=do
    when (name=="solKeyB58" && not allowLegacy) $
      bad line "solKeyB58 is obsolete; use solSeedBip39 with your 12 recovery words (do not rename a base58 key value)"
    unless (name `elem` fieldNames || (allowLegacy && name=="solKeyB58")) (bad line "unknown field name; compare with example.conf")
    when (isJust $ lookup name fields) (bad line $ "duplicate field "<>name)
    (value,ending)<-valueTokens line name [] [] rest
    validateValue line name value
    case ending of
      (_,","):more@(_:_)->case more of
        (_,"}"):_ ->bad line "remove the trailing comma before }"
        _->assignments ((name,value):fields) more
      [(_,"}")]->Right ((name,value):fields)
      _->bad line "expected a comma between fields or a final } with no trailing text"
  assignments _ ((line,_):_)=bad line "expected field = value; check commas, quotes and braces"
  valueTokens line name _ _ []=bad line $ "missing closing delimiter after "<>name
  valueTokens line name stack values remaining@((position,token):rest)
    | null stack && token `elem` [",","}"]=Right(unwords $ reverse values,remaining)
    | token `elem` ["(","[","{"]=valueTokens line name (token:stack) (token:values) rest
    | token `elem` [")","]","}"]=case stack of
        open:more | (open,token) `elem` [("(",")"),("[","]"),("{","}")]->valueTokens line name more (token:values) rest
        _->bad position $ "mismatched delimiter in "<>name
    | otherwise=valueTokens line name stack (token:values) rest
  validateValue line name value
    | name `elem` ["websiteDirectory","cloudflareTunnelToken"]=
        unless (isJust(readMaybe value :: Maybe (Maybe String))) (bad line $ name<>" requires Nothing or Just \"text\"")
    | name `elem` ["feeRateWrapBps","feeRateUnwrapBps","minimumPayoutIntervalHours"]=do
        number<-maybe (bad line $ name<>" requires an unquoted whole number") Right (readMaybe value :: Maybe Integer)
        when (name/="minimumPayoutIntervalHours" && (number<toInteger(minBound::Int) || number>toInteger(maxBound::Int))) $
          bad line (name<>" is outside the supported integer range")
    | otherwise=unless (isJust(readMaybe value :: Maybe String)) (bad line $ name<>" requires a double-quoted string")
  tokenize line source=do
    let (space,rest)=span isSpace source
        current=line+length(filter (=='\n') space)
    case rest of
      []->Right []
      '-':'-':more->tokenize current (dropWhile (/='\n') more)
      '{':'-':more->do (next,remaining)<-comment current (1::Int) more;tokenize next remaining
      _->case lex rest of
        [(token,remaining)] | not(null token)->do
          let next=current+length(filter (=='\n') $ take (length rest-length remaining) rest)
          ((current,token):) <$> tokenize next remaining
        _->bad current "invalid token or unclosed string; use straight double quotes"
  comment line _ []=bad line "unclosed {- -} comment"
  comment line depth ('{':'-':rest)=comment line (depth+1) rest
  comment line depth ('-':'}':rest)=if depth==1 then Right(line,rest) else comment line (depth-1) rest
  comment line depth (c:rest)=comment (if c=='\n' then line+1 else line) depth rest

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
  validOwnerDestination False (T.pack $ ownerEcxXpub c) >>= (`require` "owner_ecx_address_or_xpub_required")
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
