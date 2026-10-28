module Bridge.PaymentObservation
  ( PaymentObservation(..), nativeConfirmation, activeNativeBlock
  , observeSolanaPayment, solanaExpiryEvidence, ExpiryProgress(..), ExpiryHistory(..), expiryProgressValid ) where
import Bridge.Domain (Amount,amount)
import Bridge.Error
import Bridge.Identity (digest)
import Bridge.NativePayment
import Bridge.Solana (solanaGenesis,SignatureInfo(..))
import Bridge.SolanaMessage (signatureBytes)
import Control.Monad (forM,unless)
import qualified Data.Set as Set
import GHC.Generics (Generic)
import Bridge.SolanaHelper
import Bridge.SolanaPayment
import Bridge.Wire (PaymentCosts(..),Profile(..))
import Bridge.RPC (fieldValue,parseValue)
import Data.Aeson
import qualified Data.ByteString.Lazy as BL
import Data.Int (Int64)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE

data PaymentObservation = PaymentUnseen | PaymentWaiting
  | PaymentConfirmed PaymentCosts Text | PaymentFailed Amount Text deriving (Eq,Show)

-- The family reader verifies effects and active spenders before this depth proof.
nativeConfirmation :: NativeRPC -> NativeSigned -> Int -> Value -> IO PaymentObservation
nativeConfirmation call signed confirmations value
  | confirmations<planDepth(signedNativePlan signed)=pure PaymentWaiting
  | otherwise=do
      anchor<-fieldValue "blockhash" value
      height<-activeNativeBlock call anchor (planDepth $ signedNativePlan signed)
      zero<-either reject pure (amount 0)
      pure $ PaymentConfirmed (PaymentCosts (signedNativeFee signed) zero) $ encoded $ object
        ["txid" .= nativeTxid(signedNativeTransaction signed),"blockhash" .= anchor
        ,"height" .= height,"requiredDepth" .= planDepth(signedNativePlan signed)]

activeNativeBlock :: NativeRPC -> Text -> Int -> IO Int64
activeNativeBlock call anchor depth = do
  require (T.length anchor==64 && T.all (`elem` ("0123456789abcdef"::String)) anchor && depth>0) "invalid_native_settlement_anchor"
  header<-call False "getblockheader" [toJSON anchor]
  actual<-fieldValue "hash" header
  confirmations<-fieldValue "confirmations" header :: IO Int
  height<-fieldValue "height" header :: IO Int64
  canonical<-call False "getblockhash" [toJSON height] >>= parseValue parseJSON
  require (actual==anchor && canonical==anchor && height>=0 && confirmations>=depth) "native_settlement_not_canonical"
  pure height

observeSolanaPayment :: SolanaRPC -> SolanaPolicy -> SolanaSigned -> IO PaymentObservation
observeSolanaPayment call config signed = do
  signature<-maybe (reject "helper_signature_missing") pure (replySignature $ signedSolanaReply signed)
  proof<-call "getTransaction" [toJSON signature,object
    ["commitment" .= ("finalized"::Text),"encoding" .= ("json"::Text),"maxSupportedTransactionVersion" .= (0::Int)]]
  if proof/=Null then do
    outcome<-either reject pure (verifySolanaOutcome config signed proof)
    let evidence=encoded $ object ["signature" .= signature,"outcome" .= outcome,"transactionHash" .= digest(BL.toStrict $ encode proof)]
    pure $ if outcomeSucceeded outcome
      then PaymentConfirmed (PaymentCosts (outcomeFee outcome) (outcomeRent outcome)) evidence
      else PaymentFailed (outcomeFee outcome) evidence
  else do
    response<-call "getSignatureStatuses" [toJSON [signature],object ["searchTransactionHistory" .= True]]
    (_,value)<-contextValue (recentSlot $ solPlanRecent $ signedSolanaPlan signed) response
    statuses<-parseValue parseJSON value :: IO [Value]
    case statuses of
      [Null]->pure PaymentUnseen
      [status]->do
        finality<-fieldValue "confirmationStatus" status :: IO Text
        require (finality `elem` ["processed","confirmed"]) "finalized_solana_evidence_unavailable"
        pure PaymentWaiting
      _->reject "invalid_signature_status_response"

encoded :: ToJSON a => a -> Text
encoded=TE.decodeUtf8 . BL.toStrict . encode

-- Scratch history coverage for one exact attempt/provider configuration. It is
-- not an expiry authorization. Completion still requires fresh provider checks.
data ExpiryProgress = ExpiryProgress
  { expiryBinding :: !Text, expiryHistories :: ![ExpiryHistory] } deriving (Eq,Show,Generic)
data ExpiryHistory = ExpiryHistory
  { expiryStream :: !Text, expiryOrigin :: !Text, expiryHorizon :: !Int64
  , expiryWindow :: ![SignatureInfo], expiryCount :: !Integer
  , expiryDigest :: !Text, expiryComplete :: !Bool } deriving (Eq,Show,Generic)
instance ToJSON ExpiryHistory
instance FromJSON ExpiryHistory
instance ToJSON ExpiryProgress
instance FromJSON ExpiryProgress where
  parseJSON value=do
    progress<-genericParseJSON defaultOptions value
    unless (expiryProgressValid progress) (fail "invalid expiry progress")
    pure progress

expiryProgressValid :: ExpiryProgress -> Bool
expiryProgressValid p=hex (expiryBinding p) && not(null histories) && length histories<=4
  && length streams==Set.size(Set.fromList streams) && all valid histories
 where
  histories=expiryHistories p; streams=map expiryStream histories
  hex t=T.length t==64 && T.all (`elem` ("0123456789abcdef"::String)) t
  signature t=case signatureBytes t of Right _->True; Left _->False
  valid h=hex(expiryStream h) && signature(expiryOrigin h) && expiryHorizon h>=0
    && not(null rows) && length rows<=100 && expiryCount h>=toInteger(length rows)
    && expiryCount h<=toInteger(maxBound::Int64) && hex(expiryDigest h)
    && all (signature.historySignature) rows && all ((>=0).historySlot) rows
    && length ids==Set.size(Set.fromList ids) && and(zipWith (>=) slots (drop 1 slots))
    && (expiryComplete h == (last ids==expiryOrigin h))
   where rows=expiryWindow h; ids=map historySignature rows; slots=map historySlot rows

-- Finalized height alone is insufficient. Walk BOTH histories to their immutable
-- origins on EVERY provider. Save at most ten pages per stream per invocation;
-- continuing from a saved finalized cursor avoids restarting at a growing head.
-- After completion, absence still needs fresh height/hash/transaction/status checks.
solanaExpiryEvidence :: SolanaRPC -> Maybe SolanaRPC -> Profile -> SolanaPolicy
  -> (Text,Text) -> SolanaSigned -> Text -> Maybe ExpiryProgress
  -> IO (Maybe ExpiryProgress,Maybe Text)
solanaExpiryEvidence primary independent profile config (tokenOrigin,operatingOrigin) signed binding saved=do
  require (solPlanFingerprint(signedSolanaPlan signed)==fingerprint config && minimumSlot>=0 && recentLastValidHeight recent>0) "saved_solana_policy_mismatch"
  mapM_ (\p->require (expiryProgressValid p && expiryBinding p==binding) "solana_expiry_progress_changed") saved
  height<-primary "getBlockHeight" [options minimumSlot] >>= parseValue parseJSON :: IO Int64
  require (height>=0) "expiry_provider_behind"
  if height<=recentLastValidHeight recent then pure (saved,Nothing) else do
    mapM_ (either reject (const $ pure ()) . signatureBytes) [tokenOrigin,operatingOrigin]
    signature<-maybe (reject "helper_signature_missing") pure (replySignature $ signedSolanaReply signed)
    providers<-case independent of
      Nothing->require (profile/=CanonicalBeta) "independent_rpc_required" >> pure [("primary",primary)]
      Just call->pure [("primary",primary),("independent",call)]
    let streams=[stream label address origin | (label,_)<-providers,(address,origin)<-accounts]
    mapM_ (\p->require (map expiryStream (expiryHistories p)==streams) "solana_expiry_progress_changed") saved
    results<-mapM (\(label,call)->evidence label call signature) providers
    let progress=ExpiryProgress binding (concatMap fst results)
    require (expiryProgressValid progress) "invalid_solana_expiry_progress"
    pure (Just progress,if all expiryComplete (expiryHistories progress) then Just $ encoded $ object
      ["signature" .= signature,"blockhash" .= recentHash recent,"lastValidBlockHeight" .= recentLastValidHeight recent
      ,"binding" .= binding,"providers" .= map snd results] else Nothing)
 where
  recent=solPlanRecent $ signedSolanaPlan signed
  minimumSlot=recentSlot recent
  accounts=[(custodyAta config,tokenOrigin),(custodyOwner config,operatingOrigin)]
  options slot=object ["commitment" .= ("finalized"::Text),"minContextSlot" .= slot]
  stream label address origin=digest(BL.toStrict $ encode (label::Text,address,origin))
  evidence label call signature=do
    genesis<-call "getGenesisHash" [] >>= parseValue parseJSON
    require (genesis==solanaGenesis profile) "expiry_wrong_genesis"
    height<-call "getBlockHeight" [options minimumSlot] >>= parseValue parseJSON :: IO Int64
    require (height>recentLastValidHeight recent) "expiry_provider_behind"
    slot<-call "getSlot" [options minimumSlot] >>= parseValue parseJSON :: IO Int64
    require (slot>=minimumSlot) "expiry_provider_behind"
    (_,valid)<-call "isBlockhashValid" [toJSON $ recentHash recent,options slot] >>= contextValue slot
    require (valid==Bool False) "blockhash_still_valid"
    histories<-forM accounts $ \(address,origin)->do
      let key=stream label address origin
          previous=[h | p<-maybe [] pure saved,h<-expiryHistories p,expiryStream h==key]
          fetch before=call "getSignaturesForAddress"
            [toJSON address,object $ ["commitment" .= ("finalized"::Text),"minContextSlot" .= slot,"limit" .= (100::Int)]
              <> maybe [] (\sig->["before" .= sig]) before] >>= parseValue parseJSON
      case previous of
        []->walk signature fetch 0 (ExpiryHistory key origin slot [] 0 (digest "") False)
        [h]->do
          require (expiryOrigin h==origin && expiryHorizon h<=slot) "solana_expiry_progress_changed"
          walk signature fetch 0 h
        _->reject "solana_expiry_progress_changed"
    transaction<-call "getTransaction" [toJSON signature,object ["commitment" .= ("finalized"::Text),"encoding" .= ("json"::Text),"maxSupportedTransactionVersion" .= (0::Int)]]
    require (transaction==Null) "expired_transaction_observed"
    (_,statuses)<-call "getSignatureStatuses" [toJSON [signature],object ["searchTransactionHistory" .= True]] >>= contextValue slot
    require (statuses==toJSON [Null]) "expired_signature_observed"
    pure (histories,object ["provider" .= label,"genesis" .= genesis,"finalizedHeight" .= height
      ,"minimumFinalizedSlot" .= slot,"blockhashValid" .= False,"histories" .= histories
      ,"transaction" .= Null,"signatureStatuses" .= statuses])
  walk signature fetch pages h
    | expiryComplete h || pages==10 = pure h
    | otherwise=do
        let old=expiryWindow h
        page<-fetch (if null old then Nothing else Just $ historySignature $ last old)
        require (not(null page) && length page<=100) "solana_history_gap"
        let joined=old<>page; ids=map historySignature joined; slots=map historySlot joined
        require (length ids==Set.size(Set.fromList ids)) "solana_history_repeated_page"
        require (and(zipWith (>=) slots (drop 1 slots))) "solana_history_order_invalid"
        require (all ((/=signature).historySignature) page) "expired_signature_in_history"
        let (prefix,rest)=break ((==expiryOrigin h).historySignature) page
            covered=prefix<>take 1 rest
            next=h {expiryWindow=covered,expiryCount=expiryCount h+toInteger(length covered)
              ,expiryDigest=digest(TE.encodeUtf8(expiryDigest h)<>BL.toStrict(encode covered))
              ,expiryComplete=not(null rest)}
        require (expiryCount next<=toInteger(maxBound::Int64)) "solana_expiry_history_too_large"
        walk signature fetch (pages+1::Int) next
