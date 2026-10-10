{-# LANGUAGE GADTs, ForeignFunctionInterface #-}
-- Only associated-token-account setup; no mint, burn or arbitrary instructions.
module Token (Request(..),Safe(..),evalSafe,validate,Saved(..),validateSaved,validateSuccessorSaved) where
import Bridge.Error (require,reject)
import Bridge.Domain (parseNatural)
import Bridge.SolanaMessage (Transaction(..),publicKey,base58,decodeTransaction,validateAssociated)
import Bridge.AdminStatus (Recovery(..),validateRecovery,validateSuccessor)
import Crypto.Error (CryptoFailable(..))
import qualified Crypto.PubKey.Ed25519 as Ed
import qualified Data.ByteString.Base64 as B64
import qualified Data.Text.Encoding as TE
import Control.Exception (bracket)
import Control.Monad (unless)
import Data.Aeson
import qualified Data.ByteString as B
import qualified Data.ByteString.Lazy as L
import Data.Text (Text)
import qualified Data.Text as T
import Foreign
import Foreign.C.Types
import System.Posix.DynamicLinker

data Request = Associated
  { authority :: Text, mint :: Text, account :: Text, owner :: Text
  , rent :: Word64, blockhash :: Text } deriving (Eq,Show)

-- Keep the immutable ATA attempt format used by existing installations.
instance ToJSON Request where
  toJSON Associated{authority=payer,mint=key,account=address,owner=recipient,rent=lamports,blockhash=recent}=object
    ["protocol" .= (1::Int),"verb" .= ("associated"::Text),"authority" .= payer,"mint" .= key
    ,"account" .= address,"owner" .= recipient,"rent" .= T.pack(show lamports),"blockhash" .= recent]
instance FromJSON Request where
  parseJSON=withObject "associated account preparation" $ \o->do
    protocol<-o .: "protocol"
    verb<-o .: "verb"
    unless (protocol==(1::Int) && verb==("associated"::Text) && length o==8)
      (fail "invalid_associated_operation")
    raw<-o .: "rent"
    n<-case parseNatural (toInteger(maxBound::Word64)) raw of
      Just x | x>0 -> pure(fromInteger x)
      _->fail "invalid_account_rent"
    Associated <$> o .: "authority" <*> o .: "mint" <*> o .: "account" <*> o .: "owner" <*> pure n <*> o .: "blockhash"

data Safe a where
  Prepare :: FilePath -> Request -> Safe Text
  AssociatedAddress :: FilePath -> Text -> Text -> Safe Text

evalSafe :: Safe a -> IO a
evalSafe (AssociatedAddress library recipient key)=do
  mapM_ (either reject (const $ pure ()) . publicKey) [recipient,key]
  output<-invoke library (L.toStrict $ encode $ object ["protocol" .= (1::Int),"verb" .= ("associated_address"::Text),"mint" .= key,"owner" .= recipient])
  address<-either (const $ reject "invalid_associated_address_reply") pure (eitherDecodeStrict' output)
  either reject (const $ pure address) (publicKey address)
evalSafe (Prepare library request)=do
  require (rent request>0) "invalid_account_rent"
  mapM_ (either reject (const $ pure ()) . publicKey)
    [authority request,mint request,account request,owner request,blockhash request]
  output<-invoke library (L.toStrict $ encode request)
  transaction<-either (const $ reject "invalid_token_sdk_reply") pure (eitherDecodeStrict' output)
  either reject (const $ pure transaction) (validate request transaction)

-- Independently check the entire SDK message, including the zero signature,
-- exact instruction, key roles and blockhash, before it can be signed.
validate :: Request -> Text -> Either Text Transaction
validate Associated{authority=payer,mint=key,account=address,owner=recipient,rent=lamports,blockhash=recent} encoded=do
  unless (lamports>0) (Left "invalid_account_rent")
  validateAssociated False payer key address recipient recent encoded

data Saved = Saved
  { savedRequest :: Request, savedId :: Text, savedTransaction :: Text
  , savedRecovery :: Maybe Recovery } deriving (Eq,Show)
instance ToJSON Saved where
  toJSON saved=object $ ["request" .= savedRequest saved,"signature" .= savedId saved,"transaction" .= savedTransaction saved]
    <>["recovery" .= recovery | Just recovery<-[savedRecovery saved]]
instance FromJSON Saved where
  parseJSON=withObject "signed token operation" $ \o->do
    recovery<-o .:? "recovery"
    unless (length o==case recovery of Nothing->3; Just _->4) (fail "Unexpected saved-operation fields")
    Saved <$> o .: "request" <*> o .: "signature" <*> o .: "transaction" <*> pure recovery

-- Verify both the signature and its exact request before using an archived file.
validateSaved :: Saved -> Either Text Text
validateSaved (Saved request identifier encoded recovery)=do
  mapM_ (\context->validateRecovery (recoveryGenesis context) (authority request)
    (recoveryFeeLimit context) (blockhash request) context) recovery
  Transaction signatures _ message<-decodeTransaction encoded
  let unsigned=TE.decodeUtf8 $ B64.encode (B.singleton 1<>B.replicate 64 0<>message)
  _<-validate request unsigned
  owner<-publicKey (authority request)
  case (signatures,Ed.publicKey owner) of
    ([bytes],CryptoPassed key)->case Ed.signature bytes of
      CryptoPassed signature | base58 bytes==identifier && Ed.verify key message signature -> pure unsigned
      _->Left "invalid_token_signature"
    _->Left "invalid_token_signature"

-- A new blockhash is the only permitted change to the operation itself.
validateSuccessorSaved :: Saved -> Text -> Saved -> Either Text ()
validateSuccessorSaved parent parentHash child=do
  _<-validateSaved parent
  _<-validateSaved child
  before<-maybe (Left "token_recovery_context_required") Right (savedRecovery parent)
  after<-maybe (Left "token_recovery_context_required") Right (savedRecovery child)
  validateSuccessor before parentHash after
  unless ((savedRequest parent) {blockhash=blockhash(savedRequest child)}==savedRequest child)
    (Left "token_recovery_intent_mismatch")

-- Dedicated unsigned entry point; no caller-selected symbol or signing path.
type PrepareFn = Ptr Word8 -> CSize -> Ptr Word8 -> CSize -> Ptr Word8 -> CSize -> Ptr CSize -> IO CInt
foreign import ccall safe "dynamic" callPrepare :: FunPtr PrepareFn -> PrepareFn
invoke :: FilePath -> B.ByteString -> IO B.ByteString
invoke library request=do
  require (B.length request<=8192) "token_request_too_large"
  bracket (dlopen library [RTLD_NOW,RTLD_LOCAL]) dlclose $ \handle->do
    prepare<-callPrepare <$> dlsym handle "ecx_associated_prepare_v1"
    B.useAsCString "{}" $ \config->B.useAsCStringLen request $ \(input,size)->
      allocaBytes 8192 $ \output->alloca $ \lengthPtr->do
        poke lengthPtr 0
        status<-prepare (castPtr config) 2 (castPtr input) (fromIntegral size) output 8192 lengthPtr
        count<-peek lengthPtr
        require (status==0 && count>0 && count<=8192) "token_sdk_failed"
        B.packCStringLen (castPtr output,fromIntegral count)
