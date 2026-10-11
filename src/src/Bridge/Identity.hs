-- Exact baseline capability hashing; raw tokens never become persisted IDs.
module Bridge.Identity (digest, capabilityHash, bearerHash,payInstruction,payReference,payURIFor,publicKey, NativeReceiptDigest, emptyNativeReceipts, addNativeReceipt, nativeReceiptCommitment) where
import Bridge.Domain (Amount,renderCoins)
import Crypto.Hash (Digest,SHA256,Context,hash,hashInit,hashUpdate,hashFinalize)
import qualified Bridge.Wire as W
import Bridge.Domain (Asset(Native))
import Data.Aeson (Value,encode,object,(.=))
import qualified Data.ByteString.Lazy as BL
import Text.Read (readMaybe)
import qualified Data.ByteArray.Encoding as BA
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Base16 as Hex
import qualified Data.ByteString.Base58 as B58
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE

digest :: ByteString -> Text
digest bytes=TE.decodeUtf8 (BA.convertToBase BA.Base16 (hash bytes :: Digest SHA256))
capabilityHash :: Text -> Either Text Text
capabilityHash token
  | T.length token==64 && T.all (`elem` ("0123456789abcdef"::String)) token =
      Right (digest $ TE.encodeUtf8 $ "ecx-capability-v1:"<>token)
  | otherwise=Left "invalid_capability"
bearerHash :: Text -> Either Text Text
bearerHash header=maybe (Left "authorization_required") capabilityHash (T.stripPrefix "Bearer " header)

-- Same order-derived Solana Pay reference as the original bridge.
payInstruction :: Text -> Either Text Text
payInstruction identifier=("solana-pay:"<>) <$> payReference identifier
payReference :: Text -> Either Text Text
payReference identifier = do
  if T.length identifier/=64 then Left "invalid_order_reference" else pure ()
  raw <- either (const $ Left "invalid_order_reference") Right (Hex.decode $ TE.encodeUtf8 identifier)
  if BS.length raw/=32 then Left "invalid_order_reference" else
    Right (TE.decodeUtf8 (B58.encodeBase58 B58.bitcoinAlphabet raw))

publicKey :: Text -> Either Text BS.ByteString
publicKey value
  | T.length value<32 || T.length value>44 = Left "invalid_public_key"
  | otherwise = case B58.decodeBase58 B58.bitcoinAlphabet (TE.encodeUtf8 value) of
      Just bytes | BS.length bytes==32 -> Right bytes
      _ -> Left "invalid_public_key"

-- Keys are validated base58, so only the fixed label needs URI escaping.
payURIFor :: Text -> Text -> Text -> Amount -> Either Text Text
payURIFor owner mint instruction quantity = do
  reference<-maybe (Left "invalid_pay_reference") Right (T.stripPrefix "solana-pay:" instruction)
  mapM_ publicKey [owner,mint,reference]
  pure ("solana:"<>owner<>"?amount="<>renderCoins quantity<>"&spl-token="<>mint<>"&reference="<>reference<>"&label=ECX%20Bridge")

-- Domain-separated receipt commitment, ordered by ID length then ID (canonical
-- decimal output indices within one transaction). Only immutable binding and
-- current eligibility participate; allocation/first-seen changes do not.
data NativeReceiptDigest = NativeReceiptDigest !Integer !Text !(Context SHA256)
emptyNativeReceipts :: NativeReceiptDigest
emptyNativeReceipts = NativeReceiptDigest 0 "" (hashUpdate hashInit ("ecx-native-receipts-v1\n" :: ByteString))
addNativeReceipt :: NativeReceiptDigest -> W.Deposit -> Either Text NativeReceiptDigest
addNativeReceipt (NativeReceiptDigest count previous context) receipt = do
  let identifier=W.depositId receipt
  case T.splitOn ":" identifier of
    ["native",tx,index] | T.length tx==64,T.all (`elem` ("0123456789abcdef"::String)) tx,
      Just n<-(readMaybe (T.unpack index)::Maybe Integer),n>=0,n<=4294967295,T.pack(show n)==index,
      W.depositAsset receipt==Native,(T.length identifier,identifier)>(T.length previous,previous)->pure ()
    _->Left "invalid_native_receipt_commitment"
  let bytes=BL.toStrict $ encode (identifier,W.depositAmount receipt,W.depositOrder receipt,W.depositEligible receipt)
  pure $ NativeReceiptDigest (count+1) identifier (hashUpdate (hashUpdate context bytes) ("\n" :: ByteString))
nativeReceiptCommitment :: NativeReceiptDigest -> Value
nativeReceiptCommitment (NativeReceiptDigest count _ context) = object
  ["version" .= (1::Int),"count" .= count,"sha256" .= TE.decodeUtf8 (BA.convertToBase BA.Base16 (hashFinalize context))]
