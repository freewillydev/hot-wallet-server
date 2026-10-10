{-# LANGUAGE GADTs #-}
-- Read-only preflight; simulation always contains zero signatures.
module Token.Network (Network(..),Safe(..),Critical(..),evalSafe,evalCritical) where
import Bridge.AdminStatus (Status,inspectStatus,Recovery(..),newRecovery,validateRecovery,attemptPath)
import Bridge.AdminKey (readPrivate,readKey,savePrivate,newPrivatePath,withFamily)
import Bridge.Identity (digest)
import qualified Token
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as L
import qualified Data.ByteArray as BA
import qualified Crypto.PubKey.Ed25519 as Ed
import Token (Request(..),validate,Saved(..),validateSaved,validateSuccessorSaved)
import Bridge.Error (require,reject)
import Bridge.RPC
import Bridge.Solana (inspectMint,inspectClassicAccount)
import Bridge.SolanaMessage (Transaction(..),publicKey,base58)
import Control.Monad (unless,forM_)
import System.Posix.Files (fileExist)
import Data.Aeson
import qualified Data.ByteString.Base64 as B64
import Data.Text (Text)
import qualified Data.Text.Encoding as TE
import Data.Word (Word64)

data Network = Devnet | Mainnet deriving (Eq,Show)
data Safe a where
  RecentBlockhash :: Network -> String -> Safe Text
  InspectSaved :: Network -> String -> FilePath -> Safe Status
  Check :: Network -> String -> Word64 -> Request -> Text -> Safe Word64

evalSafe :: Safe a -> IO a
evalSafe (RecentBlockhash network endpoint)=
  withSolanaRpc endpoint (genesis network) ("invalid_token_rpc_policy","wrong_token_network") $ \call->do
    recent<-call "getLatestBlockhash" [object ["commitment" .= ("finalized"::Text)]]
      >>= fieldValue "value" >>= fieldValue "blockhash" >>= parseValue parseJSON
    either reject (const $ pure recent) (publicKey recent)
evalSafe (InspectSaved network endpoint path)=do
  (saved,_)<-loadFamily path
  forM_ (savedRecovery saved) $ \context->either reject pure $
    validateRecovery (genesis network) (authority $ savedRequest saved)
      (recoveryFeeLimit context) (blockhash $ savedRequest saved) context
  inspectStatus (genesis network) endpoint (savedId saved) (savedTransaction saved) (blockhash $ savedRequest saved)
evalSafe (Check network endpoint feeLimit request unsigned)=do
  require (feeLimit>0) "invalid_token_rpc_policy"
  Transaction _ _ message<-either reject pure (validate request unsigned)
  withSolanaRpc endpoint (genesis network) ("invalid_token_rpc_policy","wrong_token_network") $ \call->do
    let options=object ["encoding" .= ("jsonParsed"::Text),"commitment" .= ("finalized"::Text)]
        accountInfo address=call "getAccountInfo" [toJSON address,options] >>= fieldValue "value"
    _<-accountInfo (mint request) >>= parseValue (inspectMint Nothing)
    minimumRent<-call "getMinimumBalanceForRentExemption" [toJSON (165::Int),object ["commitment" .= ("finalized"::Text)]] >>= parseValue parseJSON :: IO Integer
    require (minimumRent>0 && minimumRent==toInteger(rent request)) "account_rent_mismatch"
    existing<-accountInfo (account request)
    rentCost<-if existing==Null then pure minimumRent else do
      (actualOwner,_,actualMint)<-parseValue inspectClassicAccount existing
      require (actualOwner==owner request && actualMint==mint request) "associated_account_identity_mismatch"
      pure 0
    -- The ATA and mint are checked above; reject a
    -- non-system fee payer, even if an RPC simulation would accept it.
    payer<-accountInfo (authority request)
    payerOwner<-fieldValue "owner" payer :: IO Text
    executable<-fieldValue "executable" payer
    lamports<-fieldValue "lamports" payer :: IO Integer
    require (payerOwner=="11111111111111111111111111111111" && not executable) "unsupported_token_fee_payer"
    feeValue<-call "getFeeForMessage" [toJSON $ TE.decodeUtf8 $ B64.encode message,object ["commitment" .= ("finalized"::Text)]]
    fee<-fieldValue "value" feeValue :: IO (Maybe Integer)
    n<-case fee of Just n | n>0 && n<=toInteger feeLimit && n+rentCost<=lamports->pure(fromInteger n); _->reject "token_fee_unavailable_or_excessive"
    simulation<-call "simulateTransaction" [toJSON unsigned,object
      ["encoding" .= ("base64"::Text),"commitment" .= ("finalized"::Text),"sigVerify" .= False,"replaceRecentBlockhash" .= False]]
    result<-fieldValue "value" simulation
    failure<-fieldValue "err" result :: IO Value
    require (failure==Null) "token_simulation_failed"
    pure n

-- Setup can sign once or submit saved bytes. Both operations serialize on the
-- durable family root; no replacement, minting or arbitrary signing operation.
data Critical a where
  Sign :: FilePath -> Network -> String -> Word64 -> Request -> Text -> FilePath -> FilePath -> Critical Text
  Submit :: Network -> String -> Word64 -> FilePath -> Critical Value

evalCritical :: Critical a -> IO a
evalCritical (Sign library network endpoint feeLimit request unsigned key output)=withFamily output $ do
  _<-either reject pure (validate request unsigned)
  newPrivatePath output
  _<-readKey (authority request) key
  recovery<-newRecovery (genesis network) endpoint (authority request) feeLimit output
  prepareAndSign library network endpoint key request recovery
evalCritical (Submit network endpoint feeLimit path)=withSavedFamily path $ \saved _->do
  forM_ (savedRecovery saved) $ \context->do
    either reject pure $ validateRecovery (genesis network) (authority $ savedRequest saved)
      feeLimit (blockhash $ savedRequest saved) context
    whenSuccessor context $ \child->do
      _<-loadFamily child
      reject "token_attempt_superseded"
  submitSaved network endpoint feeLimit saved

prepareAndSign :: FilePath -> Network -> String -> FilePath -> Request -> Recovery -> IO Text
prepareAndSign library network endpoint key original context=do
  let request=original {blockhash=recoveryBlockhash context}
  unsigned<-Token.evalSafe (Token.Prepare library request)
  _<-evalSafe (Check network endpoint (recoveryFeeLimit context) request unsigned)
  signPrepared key request unsigned context


-- Private to the critical network interpreter: callers cannot supply fabricated
-- recovery context to a separately exported signing function.
signPrepared :: FilePath -> Request -> Text -> Recovery -> IO Text
signPrepared keyfile request unsigned recovery=do
  either reject pure $ validateRecovery (recoveryGenesis recovery) (authority request)
    (recoveryFeeLimit recovery) (blockhash request) recovery
  Transaction _ _ message<-either reject pure (validate request unsigned)
  let output=attemptPath recovery
  newPrivatePath output
  secret<-readKey (authority request) keyfile
  let signature=Ed.sign secret (Ed.toPublic secret) message
      signatureBytes=BA.convert signature :: BS.ByteString
      identifier=base58 signatureBytes
      transaction=TE.decodeUtf8 $ B64.encode (BS.singleton 1<>signatureBytes<>message)
      record=L.toStrict $ encode $ Saved request identifier transaction (Just recovery)
  require (Ed.verify (Ed.toPublic secret) message signature) "token_signature_invalid"
  savePrivate output record
  pure identifier

readSaved :: FilePath -> IO (Saved,BS.ByteString)
readSaved path=do
  bytes<-readPrivate path
  saved<-either (const $ reject "invalid_token_attempt") pure (eitherDecodeStrict' bytes)
  _<-either reject pure (validateSaved saved)
  forM_ (savedRecovery saved) $ \context->require (path==attemptPath context) "token_attempt_path_mismatch"
  pure (saved,bytes)

-- Verify the direct parent before following it. The checked generation then
-- decreases on every read, bounding the complete family to eight archives.
loadFamily :: FilePath -> IO (Saved,BS.ByteString)
loadFamily path=do
  current<-readSaved path
  ancestors current
  pure current
 where
  ancestors (saved,_)=forM_ (savedRecovery saved) $ \context->
    unless (recoveryGeneration context==0) $ do
      parent@(before,bytes)<-readSaved (attemptPath (context {recoveryGeneration=recoveryGeneration context-1}))
      either reject pure (validateSuccessorSaved before (digest bytes) saved)
      ancestors parent

withSavedFamily :: FilePath -> (Saved -> BS.ByteString -> IO a) -> IO a
withSavedFamily path action=do
  (initial,_)<-readSaved path
  let root=maybe path recoveryRoot (savedRecovery initial)
  withFamily root $ do
    (saved,bytes)<-loadFamily path
    require (maybe path recoveryRoot (savedRecovery saved)==root) "token_attempt_family_changed"
    action saved bytes

whenSuccessor :: Recovery -> (FilePath -> IO ()) -> IO ()
whenSuccessor context action=unless (recoveryGeneration context>=7) $ do
  let child=attemptPath (context {recoveryGeneration=recoveryGeneration context+1})
  exists<-fileExist child
  if exists then action child else pure ()

submitSaved :: Network -> String -> Word64 -> Saved -> IO Value
submitSaved network endpoint feeLimit saved=do
  unsigned<-either reject pure (validateSaved saved)
  require (feeLimit>0) "invalid_token_rpc_policy"
  withSolanaRpc endpoint (genesis network) ("invalid_token_rpc_policy","wrong_token_network") $ \call->do
    let identifier=savedId saved
    statuses<-call "getSignatureStatuses" [toJSON [identifier],object ["searchTransactionHistory" .= True]] >>= fieldValue "value"
    status<-case statuses of [value]->pure value; _->reject "invalid_token_status"
    if status/=Null then do
      commitment<-fieldValue "confirmationStatus" status :: IO (Maybe Text)
      failure<-fieldValue "err" status :: IO Value
      if commitment/=Just "finalized" then pure $ object ["signature" .= identifier,"status" .= ("pending"::Text)] else do
        result<-call "getTransaction" [toJSON identifier,object ["encoding" .= ("base64"::Text),"commitment" .= ("finalized"::Text),"maxSupportedTransactionVersion" .= (0::Int)]]
        transaction<-fieldValue "transaction" result :: IO [Text]
        require (transaction==[savedTransaction saved,"base64"]) "token_finalized_bytes_mismatch"
        metadata<-fieldValue "meta" result
        errorValue<-fieldValue "err" metadata :: IO Value
        fee<-fieldValue "fee" metadata :: IO Integer
        require (errorValue==failure && fee>=0 && fee<=toInteger feeLimit) "token_finalized_metadata_mismatch"
        before<-fieldValue "preBalances" metadata :: IO [Integer]
        after<-fieldValue "postBalances" metadata :: IO [Integer]
        let maximumDebit=toInteger(rent $ savedRequest saved)+fee
        require (case (before,after) of
          (a:_,b:_)->a>=0 && b>=0 && a>=b && a-b>=fee && a-b<=maximumDebit
          _->False) "token_finalized_cost_exceeded"
        pure $ object ["signature" .= identifier,"status" .= (if failure==Null then "finalized" else "failed"::Text),"feeLamports" .= fee]
    else do
      _<-evalSafe (Check network endpoint feeLimit (savedRequest saved) unsigned)
      result<-call "sendTransaction" [toJSON (savedTransaction saved),object
        ["encoding" .= ("base64"::Text),"skipPreflight" .= False,"preflightCommitment" .= ("finalized"::Text),"maxRetries" .= (0::Int)]] >>= parseValue parseJSON
      require (result==identifier) "token_submission_identifier_mismatch"
      pure $ object ["signature" .= identifier,"status" .= ("submitted"::Text)]

genesis :: Network -> Text
genesis Devnet="EtWTRABZaYq6iMfeYKouRu166VU2xqa1wcaWoxPkrZBG"
genesis Mainnet="5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d"
