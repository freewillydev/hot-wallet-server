{-# LANGUAGE DeriveGeneric #-}
-- Bounded status and saved-lineage evidence for associated-account setup.
module Bridge.AdminStatus
  ( Status(..),inspectStatus,classifyStatus,Recovery(..),newRecovery
  , validateRecovery,validateSuccessor,attemptPath,newRecoveryWith ) where
import Bridge.Error (require,reject)
import Bridge.RPC
import Bridge.Solana (SignatureInfo(..))
import Bridge.SolanaMessage (publicKey,signatureBytes)
import Control.Exception (bracket)
import Control.Monad (unless)
import Data.Aeson
import Data.Aeson.Types (parseEither,Parser)
import Data.Int (Int64)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Word (Word64)
import GHC.Generics (Generic)
import Network.HTTP.Client (parseRequest,secure,closeManager)
import System.FilePath (isAbsolute,normalise)

data Status = Pending | Finalized | Failed | Unseen | ExpiredUnseen deriving (Eq,Show)
instance ToJSON Status where toJSON=String . name
name :: Status -> Text
name Pending="pending"
name Finalized="finalized"
name Failed="failed"
name Unseen="unseen"
name ExpiredUnseen="expired-unseen"

-- Callers first verify the archived signatures and their closed operation intent.
inspectStatus :: Text -> String -> Text -> Text -> Text -> IO Status
inspectStatus genesis endpoint signature bytes blockhash=
  withSolanaRpc endpoint genesis ("administration_requires_https","wrong_administration_network") $ \call->do
    values<-call "getSignatureStatuses" [toJSON [signature],object ["searchTransactionHistory" .= True]] >>= fieldValue "value"
    status<-case values of [value]->pure value; _->reject "invalid_administration_status"
    transaction<-call "getTransaction" [toJSON signature,object ["encoding" .= ("base64"::Text),"commitment" .= ("finalized"::Text),"maxSupportedTransactionVersion" .= (0::Int)]]
    valid<-if status==Null && transaction==Null then
      call "isBlockhashValid" [toJSON blockhash,object ["commitment" .= ("finalized"::Text)]] >>= fieldValue "value"
      else pure True
    either (const $ reject "administration_status_mismatch") pure (classifyStatus bytes status transaction valid)

-- Absence can reflect pruned/unavailable history: ExpiredUnseen is not nonexecution proof.
classifyStatus :: Text -> Value -> Value -> Bool -> Either String Status
classifyStatus bytes status transaction valid
  | status==Null = if transaction/=Null then Left "inconsistent transaction history"
      else Right (if valid then Unseen else ExpiredUnseen)
  | otherwise = parseEither (withObject "signature status" $ \s->do
      commitment<-s .: "confirmationStatus" :: Parser Text
      failure<-s .: "err" :: Parser Value
      case commitment of
        "finalized"->withObject "finalized transaction" (\t->do
          encoded<-t .: "transaction"
          unless (encoded==[bytes,"base64"]) (fail "saved bytes mismatch")
          metadata<-t .: "meta"
          actual<-withObject "metadata" (.: "err") metadata
          unless (actual==failure) (fail "status disagreement")
          pure (if failure==Null then Finalized else Failed)) transaction
        "processed"->pending
        "confirmed"->pending
        _->fail "unknown commitment") status
 where
  pending=if transaction==Null then pure Pending else fail "history changed during read; inspect again"

-- The retained canonical pathname prevents making a second successor by copying
-- a parent elsewhere. Independent copies of keys/journals on another host still
-- require operator exclusion. These fields are not a cryptographic chain proof.
data Recovery = Recovery
  { recoveryGenesis :: Text, recoveryPayer :: Text, recoveryFeeLimit :: Word64
  , recoveryRoot :: FilePath, recoveryGeneration :: Int, recoveryParent :: Maybe Text
  , recoveryBlockhash :: Text, recoveryOrigin :: Text, recoveryOriginSlot :: Word64
  , recoverySlot :: Word64, recoveryLastHeight :: Word64, recoveryEvidence :: Maybe Value
  } deriving (Eq,Show,Generic)
instance ToJSON Recovery where toJSON=genericToJSON defaultOptions
instance FromJSON Recovery where
  parseJSON=genericParseJSON defaultOptions {rejectUnknownFields=True}

attemptPath :: Recovery -> FilePath
attemptPath r=recoveryRoot r<>concat (replicate (recoveryGeneration r) ".retry")

validateRecovery :: Text -> Text -> Word64 -> Text -> Recovery -> Either Text ()
validateRecovery genesis payer fee recent r=do
  _<-publicKey payer; _<-publicKey recent; _<-signatureBytes (recoveryOrigin r)
  unless (recoveryGenesis r==genesis && recoveryPayer r==payer && recoveryFeeLimit r==fee
    && fee>0 && recoveryBlockhash r==recent && isAbsolute (recoveryRoot r)
    && normalise (recoveryRoot r)==recoveryRoot r && recoveryGeneration r>=0 && recoveryGeneration r<8
    && recoveryOriginSlot r<=recoverySlot r && recoverySlot r<=fromIntegral(maxBound::Int64)
    && recoveryLastHeight r>0) (Left "invalid_administration_recovery_context")
  unless (case (recoveryGeneration r,recoveryParent r,recoveryEvidence r) of
    (0,Nothing,Nothing)->True
    (n,Just parent,Just (Object _))->n>0 && T.length parent==64 && T.all (`elem` ("0123456789abcdef"::String)) parent
    _->False) (Left "invalid_administration_recovery_lineage")

validateSuccessor :: Recovery -> Text -> Recovery -> Either Text ()
validateSuccessor old parent new=do
  validateRecovery (recoveryGenesis old) (recoveryPayer old) (recoveryFeeLimit old) (recoveryBlockhash old) old
  validateRecovery (recoveryGenesis old) (recoveryPayer old) (recoveryFeeLimit old) (recoveryBlockhash new) new
  unless (recoveryRoot new==recoveryRoot old && recoveryGeneration new==recoveryGeneration old+1
    && recoveryParent new==Just parent && recoveryBlockhash new/=recoveryBlockhash old
    && recoverySlot new>recoverySlot old) (Left "administration_successor_mismatch")

type Call = Text -> [Value] -> IO Value

-- These read-only adapter seams never accept signing, submission or key callbacks.
newRecovery :: Text -> String -> Text -> Word64 -> FilePath -> IO Recovery
newRecovery genesis endpoint payer fee root=do
  transport<-parseRequest endpoint
  require (secure transport) "administration_requires_https"
  bracket newRpcManager closeManager $ \manager->newRecoveryWith (rpc manager endpoint Nothing) genesis payer fee root

newRecoveryWith :: Call -> Text -> Text -> Word64 -> FilePath -> IO Recovery
newRecoveryWith call genesis payer fee root=do
  identity call genesis
  _<-either reject pure (publicKey payer)
  origins<-call "getSignaturesForAddress" [toJSON payer,object
    ["commitment" .= ("finalized"::Text),"limit" .= (1::Int)]] >>= parseValue parseJSON
  origin<-case origins of [value]->pure value; _->reject "administration_history_origin_required"
  latest<-call "getLatestBlockhash" [object ["commitment" .= ("finalized"::Text),"minContextSlot" .= historySlot origin]]
  context<-fieldValue "context" latest
  slot<-fieldValue "slot" context
  value<-fieldValue "value" latest
  recent<-fieldValue "blockhash" value
  height<-fieldValue "lastValidBlockHeight" value
  let r=Recovery genesis payer fee root 0 Nothing recent (historySignature origin)
          (fromIntegral $ historySlot origin) slot height Nothing
  either reject pure (validateRecovery genesis payer fee recent r)
  checkBlock call r
  pure r

identity :: Call -> Text -> IO ()
identity call expected=do
  actual<-call "getGenesisHash" [] >>= parseValue parseJSON
  require (actual==expected) "wrong_administration_network"

-- Anchor slot must precede any possible execution, not merely this invocation of
-- deterministic Ed25519 signing. Verify the actual block that created the hash;
-- transactions in that block predate availability of its resulting blockhash.
checkBlock :: Call -> Recovery -> IO ()
checkBlock call r=do
  block<-call "getBlock" [toJSON(recoverySlot r),object ["commitment" .= ("finalized"::Text)
    ,"transactionDetails" .= ("none"::Text),"rewards" .= False]]
  recent<-fieldValue "blockhash" block
  height<-fieldValue "blockHeight" block :: IO Word64
  require (recent==recoveryBlockhash r && height<recoveryLastHeight r
    && toInteger(recoveryLastHeight r)-toInteger height<=300) "administration_blockhash_origin_mismatch"
