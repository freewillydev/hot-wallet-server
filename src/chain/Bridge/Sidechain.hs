{-# LANGUAGE DeriveAnyClass,ScopedTypeVariables #-}
-- Thunder/BitNames are ECX sidechains. RPC data is evidence, never payout authority.
module Bridge.Sidechain
  ( SidechainSettings(..),SidechainOutput(..),validateSidechains,findSidechain
  , sidechainCall,validatorCall,sidechainIdentityWith,sidechainHeadWith,readOutputsWith,verifyOutputWith
  , sidechainInstruction,decodeInstruction,outputId,validAddress,recoverAddressWith,verifySourceWith
  , sidechainWalletFile,readSidechainSeed,validateSidechainSeed
  ) where

import Bridge.Identity (digest)
import qualified Bridge.AdminKey as Key
import Bridge.Domain
import Bridge.Error
import Bridge.Wire (Profile(..),SidechainPolicy(..))
import qualified Bridge.Wire as W
import Bridge.Lifecycle (sourcePolicy)
import Text.Read (readMaybe)
import Bridge.NativePayment (NativeRPC,transactionId)
import Bridge.RPC
import Control.Monad (forM,forM_,when)
import Data.Aeson
import qualified Data.ByteString as BS
import qualified Data.ByteString.Base58 as B58
import Data.List (nub,sort,(\\))
import Data.Maybe (catMaybes)
import qualified Data.Aeson.KeyMap as KM
import qualified Data.Aeson.Key as K
import Data.Int (Int64)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import GHC.Generics (Generic)
import Network.HTTP.Client
import Network.HTTP.Types.Status (statusCode)
import Control.Exception (catch)
import System.FilePath (isAbsolute,normalise)

data SidechainSettings = SidechainSettings
  { sidechainPolicy :: !SidechainPolicy, sidechainRpc :: !String
  , sidechainPrivateRpc :: !String, sidechainValidatorRpc :: !String, sidechainSeedFile :: !FilePath }
  deriving (Eq,Show,Generic,ToJSON)
instance FromJSON SidechainSettings where
  parseJSON=genericParseJSON defaultOptions {rejectUnknownFields=True}
data SidechainOutput = SidechainOutput
  { outputKind :: !Text, outputTransaction :: !Text, outputIndex :: !Int, outputAddress :: !Text, outputAmount :: !Amount }
  deriving (Eq,Show)
type Call = Text -> [Value] -> IO Value

validateSidechains :: Profile -> [SidechainSettings] -> IO ()
validateSidechains profile settings = do
  require (length settings<=2 && length(nub assets)==length assets) "duplicate_sidechain"
  -- BitNames has no compatible betanet network in the pinned upstream build.
  require (null settings || profile==L2LSignetDevnet) "sidechains_require_ecx_signet"
  ports<-forM settings $ \setting->do
    let policy=sidechainPolicy setting; seed=sidechainSeedFile setting
    require (sidechainAsset policy `elem` [Thunder,BitNames] && sidechainDepth policy>=6
      && sidechainDepth policy<=1008 && sidechainFeeBps policy>=0 && sidechainFeeBps policy<10000
      && transactionId(sidechainCheckpoint policy) && transactionId(sidechainWalletIdentity policy)) "invalid_sidechain_policy"
    require (isAbsolute seed && normalise seed==seed) "absolute_sidechain_seed_path_required"
    forM [sidechainRpc setting,sidechainPrivateRpc setting,sidechainValidatorRpc setting] $ \url->do
      endpoint<-parseRequest url
      require (not(secure endpoint) && host endpoint=="127.0.0.1" && path endpoint=="/"
        && BS.null(queryString endpoint) && null(requestHeaders endpoint)
        && port endpoint>1024 && port endpoint<=65535) "private_sidechain_rpc_required"
      pure(port endpoint)
  let nodePorts=concatMap (take 2) ports; validatorPorts=map last ports
  require (length(nub nodePorts)==length nodePorts && all (`notElem` nodePorts) validatorPorts) "sidechain_ports_overlap"
 where assets=map (sidechainAsset . sidechainPolicy) settings
findSidechain :: [SidechainSettings] -> Asset -> IO SidechainSettings
findSidechain settings asset=case filter ((==asset).sidechainAsset.sidechainPolicy) settings of
  [setting]->pure setting
  _->reject "sidechain_not_configured"
sidechainCall :: Manager -> SidechainSettings -> Call
sidechainCall manager setting=rpc manager (sidechainRpc setting) Nothing

sidechainWalletFile :: Asset -> FilePath
sidechainWalletFile asset=T.unpack(T.toLower $ T.pack $ show asset)<>"-wallet.json"
validateSidechainSeed :: SidechainPolicy -> Text -> IO ()
validateSidechainSeed policy phrase=do
  require (T.length phrase<=256 && length(T.words phrase) `elem` [12,15,18,21,24]
    && T.unwords(T.words phrase)==phrase && T.all (\c->c==' ' || c>='a' && c<='z') phrase
    && digest(TE.encodeUtf8 phrase)==sidechainWalletIdentity policy) "invalid_sidechain_seed"
readSidechainSeed :: SidechainSettings -> IO Text
readSidechainSeed setting=do
  bytes<-Key.readPrivate (sidechainSeedFile setting)
  phrase<-either (const $ reject "invalid_sidechain_seed") (pure . T.strip) (TE.decodeUtf8' bytes)
  validateSidechainSeed (sidechainPolicy setting) phrase
  pure phrase

sidechainInstruction :: Asset -> Text -> Text
sidechainInstruction asset address=T.toLower(T.pack $ show asset)<>":"<>address
decodeInstruction :: Asset -> Text -> Either Text Text
decodeInstruction asset instruction=case T.stripPrefix (sidechainInstruction asset "") instruction of
  Just address | validAddress address->Right address
  _->Left "invalid_sidechain_instruction"
validAddress :: Text -> Bool
validAddress address=T.length address<=28 && case B58.decodeBase58 B58.bitcoinAlphabet (TE.encodeUtf8 address) of
  Just bytes->BS.length bytes==20 && B58.encodeBase58 B58.bitcoinAlphabet bytes==TE.encodeUtf8 address
  Nothing->False
outputId :: Asset -> SidechainOutput -> Text
outputId asset output=sidechainInstruction asset (kind<>outputTransaction output<>":"<>T.pack(show $ outputIndex output))
 where kind=if outputKind output=="Regular" then "" else T.toLower(outputKind output)<>":"

-- Connect RPC uses ordinary HTTP and bounded JSON; no protobuf runtime or proxy.
-- The endpoint is fixed configuration, never an order-supplied URL or method.
validatorCall :: Manager -> SidechainSettings -> Text -> Value -> IO Value
validatorCall manager setting operation payload=do
  require (operation `elem` ["GetChainTip","GetBmmHStarCommitment"]) "invalid_validator_read"
  base<-parseRequest (sidechainValidatorRpc setting)
  let request=base {method="POST",path="/cusf.mainchain.v1.ValidatorService/"<>TE.encodeUtf8 operation,
        redirectCount=0,checkResponse= \_ _->pure (),requestBody=RequestBodyLBS (encode payload),
        requestHeaders=[("Content-Type","application/json"),("Connect-Protocol-Version","1")]}
  (withResponse request manager $ \response->do
    bytes<-boundedBody 16384 (responseBody response)
    require (statusCode(responseStatus response)==200) "sidechain_validator_unavailable"
    either (const $ reject "invalid_validator_response") pure (eitherDecodeStrict' bytes))
    `catch` (\(_::HttpException)->reject "sidechain_validator_unavailable")

-- This is the validator's actual ECX sync tip, not the sidechain tip's BMM
-- commitment: a sidechain can legitimately be idle for many ECX blocks.
sidechainIdentityWith :: NativeRPC -> (Text -> Value -> IO Value) -> IO Text
sidechainIdentityWith native validator=do
  tip<-validator "GetChainTip" (object []) >>= fieldValue "blockHeaderInfo"
  hash<-fieldValue "blockHash" tip >>= fieldValue "hex"
  height<-fieldValue "height" tip :: IO Int64
  require (transactionId hash && height>=0) "sidechain_mainchain_unavailable"
  depth<-activeDepth native hash
  active<-native False "getblockhash" [toJSON height] >>= parseValue parseJSON
  require (depth>=1 && depth<=2 && active==hash) "sidechain_mainchain_behind"
  pure hash

-- The local sidechain must have a verified active ECX commitment for its own
-- fixed slot. A synced validator alone does not make an empty/wrong node ready.
sidechainHeadWith :: NativeRPC -> (Text -> Value -> IO Value) -> Call -> Asset -> IO (Text,Text)
sidechainHeadWith native validator call asset=do
  main<-sidechainIdentityWith native validator
  tip<-call "get_best_sidechain_block_hash" [] >>= parseValue parseJSON
  require (transactionId tip) "sidechain_not_synced"
  depth<-commitmentDepth native validator call asset tip
  require (depth>0) "sidechain_tip_not_active"
  again<-call "get_best_sidechain_block_hash" [] >>= parseValue parseJSON
  require (again==tip) "sidechain_tip_changed"
  pure(main,tip)

-- Ask for inclusions of the captured block, never a separately sampled live tip.
commitmentDepth :: NativeRPC -> (Text -> Value -> IO Value) -> Call -> Asset -> Text -> IO Int
commitmentDepth native validator call asset block=do
  commitments<-call "get_bmm_inclusions" [toJSON block] >>= parseValue parseJSON :: IO [Text]
  require (not(null commitments) && length commitments<=1000 && all transactionId commitments) "sidechain_commitment_missing"
  depths<-forM commitments $ \commitment->do
    depth<-activeDepth native commitment
    when (depth>0) $ checkCommitment validator asset block commitment
    pure depth
  pure(maximum (0:depths))

checkCommitment :: (Text -> Value -> IO Value) -> Asset -> Text -> Text -> IO ()
checkCommitment validator asset block commitment=do
  require (asset `elem` [Thunder,BitNames]) "invalid_sidechain"
  proof<-validator "GetBmmHStarCommitment" (object ["blockHash" .= object ["hex" .= commitment],
    "sidechainId" .= (if asset==Thunder then 9 else 2::Int),"maxAncestors" .= (0::Int)])
  actual<-fieldValue "commitment" proof >>= fieldValue "commitment" >>= fieldValue "hex"
  require (actual==block) "sidechain_slot_commitment_mismatch"

readOutputsWith :: Call -> Asset -> [Text] -> IO [SidechainOutput]
readOutputsWith call asset addresses=do
  require (asset `elem` [Thunder,BitNames] && length addresses<=256
    && all validAddress addresses && length(nub addresses)==length addresses) "invalid_sidechain_addresses"
  values<-call "get_utxos" [toJSON addresses] >>= parseValue parseJSON :: IO [Value]
  require (length values<=1000) "sidechain_output_page_too_large"
  outputs<-fmap catMaybes $ forM values $ \value->do
    point<-fieldValue "outpoint" value
    (kind,txid,index)<-case point of
      Object fields | [entry]<-KM.toList fields->case entry of
        ("Regular",body)->(,,) "Regular" <$> fieldValue "txid" body <*> fieldValue "vout" body
        ("Coinbase",body)->(,,) "Coinbase" <$> fieldValue (if asset==Thunder then "txid" else "merkle_root") body <*> fieldValue "vout" body
        ("Deposit",String text)->case T.splitOn ":" text of
          [tx,n] | Just index<-readMaybe(T.unpack n),T.pack(show (index::Int))==n->pure("Deposit",tx,index)
          _->reject "invalid_sidechain_outpoint"
        _->reject "invalid_sidechain_outpoint"
      _->reject "invalid_sidechain_outpoint"
    body<-fieldValue "output" value
    address<-fieldValue "address" body
    require (transactionId txid && index>=0 && toInteger index<=4294967295 && address `elem` addresses) "invalid_sidechain_output"
    content<-fieldValue "content" body
    case content of
      Object fields | [entry]<-KM.toList fields->case entry of
        (name,_) | K.toText name==(if asset==Thunder then "Value" else "BitcoinSats")->do
          quantity<-plainAmount asset body
          pure $ if units quantity==0 then Nothing else Just(SidechainOutput kind txid index address quantity)
        -- These are not spendable ECX collateral. Recognized foreign assets must
        -- not let an unsolicited NFT stop every customer's deposit scan.
        ("BitName",_) | asset==BitNames->pure Nothing
        ("BitNameReservation",_) | asset==BitNames->pure Nothing
        ("BitcoinWithdrawal",_) | asset==BitNames->pure Nothing
        ("Withdrawal",_) | asset==Thunder->pure Nothing
        _->reject "unsupported_sidechain_content"
      _->reject "invalid_sidechain_content"
  require (length(nub $ map (outputId asset) outputs)==length outputs) "duplicate_sidechain_output"
  pure outputs

plainAmount :: Asset -> Value -> IO Amount
plainAmount asset body=do
  content<-fieldValue "content" body
  quantity<-fieldValue (if asset==Thunder then "Value" else "BitcoinSats") content
  either reject pure (amount quantity)

-- Confirm the exact regular output and active inclusion, then require ECX
-- confirmations of a VERIFIED BMM commitment to that sidechain block. Do not
-- confuse BitNames' tip-height delta with ECX confirmations or accept stale forks.
verifyOutputWith :: NativeRPC -> (Text -> Value -> IO Value) -> Call -> Asset -> SidechainOutput -> IO (Text,Int)
verifyOutputWith native validator call asset expected=do
  _<-sidechainIdentityWith native validator
  require (asset `elem` [Thunder,BitNames] && outputKind expected=="Regular" && outputIndex expected>=0) "invalid_sidechain_source"
  let txid=outputTransaction expected
      inclusion=do
        value<-call "get_transaction" [toJSON txid]
        require (value/=Null) "sidechain_source_not_found"
        tx<-if asset==Thunder then fieldValue "tx" value else pure value
        outputs<-fieldValue "outputs" tx :: IO [Value]
        require (outputIndex expected<length outputs && length outputs<=1000) "sidechain_source_mismatch"
        let output=outputs!!outputIndex expected
        address<-fieldValue "address" output
        quantity<-plainAmount asset output
        require (address==outputAddress expected && quantity==outputAmount expected) "sidechain_source_mismatch"
        if asset==Thunder then fieldValue "block_hash" value else
          call "get_transaction_info" [toJSON txid] >>= fieldValue "txin" >>= fieldValue "block_hash"
  block<-inclusion
  require (transactionId block) "sidechain_source_unconfirmed"
  depth<-commitmentDepth native validator call asset block
  unspent<-readOutputsWith call asset [outputAddress expected]
  require (expected `elem` unspent) "sidechain_source_spent"
  again<-inclusion
  require (again==block) "sidechain_source_changed"
  pure(block,depth)

verifySourceWith :: NativeRPC -> (Text -> Value -> IO Value) -> Call -> W.PaymentSource -> IO W.Deposit
verifySourceWith native validator call binding=do
  let saved=W.sourceDeposit binding; asset=W.depositAsset saved
  policy<-either reject pure (sourcePolicy (W.sourcePolicy binding) asset)
  address<-either reject pure (decodeInstruction asset $ W.sourceInstruction binding)
  (tx,index)<-case T.splitOn ":" (W.depositId saved) of
    [prefix,tx,n] | prefix==T.toLower(T.pack $ show asset),transactionId tx,
      Just index<-readMaybe (T.unpack n),index>=0->pure(tx,index)
    _->reject "invalid_sidechain_deposit_id"
  require (sourceAsset(W.direction $ W.sourceRequest binding)==asset) "source_binding_mismatch"
  (anchor,depth)<-verifyOutputWith native validator call asset (SidechainOutput "Regular" tx index address $ W.depositAmount saved)
  pure saved {W.depositAnchor=anchor,W.depositConfirmations=depth,W.depositEligible=depth>=sidechainDepth policy}

activeDepth :: NativeRPC -> Text -> IO Int
activeDepth native hash=do
  header<-native False "getblockheader" [toJSON hash]
  actual<-fieldValue "hash" header
  depth<-fieldValue "confirmations" header :: IO Int
  height<-fieldValue "height" header :: IO Int64
  require (actual==hash && height>=0) "sidechain_commitment_mismatch"
  when (depth>0) $ do
    active<-native False "getblockhash" [toJSON height] >>= parseValue parseJSON
    require (active==hash) "sidechain_commitment_changed"
  pure(max 0 depth)

-- Called only by the signer evaluator for the ledger's sole unresolved claim.
-- All older allocated addresses remain in known, even for expired orders.
-- A lost reply can leave one recoverable address; ambiguity must stop allocation.
recoverAddressWith :: Call -> [Text] -> IO Text
recoverAddressWith call known=do
  require (length known<100000 && all validAddress known && length(nub known)==length known) "invalid_sidechain_allocation_history"
  let addresses=do
        values<-call "get_wallet_addresses" [] >>= parseValue parseJSON
        require (length values<=100001 && all validAddress values && length(nub values)==length values) "invalid_sidechain_wallet_addresses"
        pure values
  let recover previous=case known \\ previous of
        []->pure previous
        missing->do
          require (null $ previous \\ known) "sidechain_allocation_ambiguous"
          restored<-call "get_new_address" [] >>= parseValue parseJSON
          require (restored `elem` missing) "sidechain_wallet_history_mismatch"
          current<-addresses
          require (sort current==sort(restored:previous)) "sidechain_wallet_history_mismatch"
          recover current
  before<-addresses >>= recover
  address<-case before \\ known of
    []->call "get_new_address" [] >>= parseValue parseJSON
    [saved]->pure saved
    _->reject "sidechain_allocation_ambiguous"
  require (validAddress address && address `notElem` known) "invalid_sidechain_allocation"
  after<-addresses
  require (sort after==sort(address:known)) "sidechain_allocation_ambiguous"
  pure address
