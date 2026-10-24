-- No IO, database, chain JSON or signing authority. Constructors carrying money
-- are private; adapters validate addresses and the store verifies funding proof.
{-# LANGUAGE DeriveAnyClass, DerivingStrategies, PatternSynonyms #-}
module Bridge.Domain
  ( Amount, units, amount, parseUnits, parseCoins, renderCoins, parseNatural
  , Asset(..), Direction(..), sourceAsset, destinationAsset
  , GasTopUp, mkGasTopUp, gasLamports, gasEcxFee
  , Quote, gross, fee, net, quote, historicalQuote, quoteWithGas, quoteGasTopUp
  , Funding(Conversion,Refund,EarnedFees), conversion, refund, earnedFees
  , Payment, payment, paymentId, paymentFunding, paymentRecipient, paymentAsset, paymentAmount, paymentGasLamports
  , Account(..), Posting(..), settlement, reserveEarned, releaseEarned
  ) where

import Data.Aeson (ToJSON(..),FromJSON(..),Value(String),withText,withObject,(.:),(.:?),(.=),object)
import Data.Int (Int64)
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)
import Text.Read (readMaybe)

-- Retained exact-amount parsing from baseline Bridge.Model. Intermediate
-- arithmetic uses Integer; only the checked constructor narrows to Int64.
newtype Amount = Amount Int64 deriving (Eq,Ord,Show)
units :: Amount -> Int64
units (Amount n) = n
instance ToJSON Amount where toJSON = String . T.pack . show . units
instance FromJSON Amount where parseJSON = withText "integer base-unit string" (either (fail . T.unpack) pure . parseUnits)
amount :: Integer -> Either Text Amount
amount n | n >= 0 && n <= toInteger (maxBound :: Int64) = Right (Amount (fromInteger n))
         | otherwise = Left "amount_out_of_range"
parseUnits :: Text -> Either Text Amount
parseUnits = maybe (Left "invalid_base_units") amount . parseNatural (10^(19::Int)-1)

-- Reject oversized/noncanonical text before allocating an Integer. The explicit
-- bound keeps SPL u64, liquidity u128 and signed ledger units distinct.
parseNatural :: Integer -> Text -> Maybe Integer
parseNatural bound t
  | bound<0 || T.null t || T.length t>length(show bound) || not(T.all asciiDigit t)
    || (T.length t>1 && T.head t=='0') = Nothing
  | otherwise = case readMaybe (T.unpack t) of
      Just n | n<=bound -> Just n
      _ -> Nothing
asciiDigit :: Char -> Bool
asciiDigit c = c >= '0' && c <= '9'
parseCoins :: Text -> Either Text Amount
parseCoins t = case T.splitOn "." t of
  [whole] -> go whole ""
  [whole, fractional] | not (T.null fractional) -> go whole fractional
  _ -> Left "invalid_decimal"
 where
  go w f
    | T.null w || T.length w > 11 || (T.length w > 1 && T.head w == '0') || T.length f > 8 || not (T.all asciiDigit (w<>f)) = Left "invalid_decimal"
    | otherwise = maybe (Left "invalid_decimal") amount (readMaybe (T.unpack (w <> T.justifyLeft 8 '0' f)))
renderCoins :: Amount -> Text
renderCoins a = let (w,f) = units a `divMod` 100000000 in T.pack (show w) <> "." <> T.justifyRight 8 '0' (T.pack (show f))

data Asset = Native | Wrapped | Sol deriving stock (Eq,Ord,Show,Generic) deriving anyclass (ToJSON,FromJSON)
data Direction = NativeToWrapped | WrappedToNative deriving stock (Eq,Show,Generic) deriving anyclass (ToJSON,FromJSON)
sourceAsset, destinationAsset :: Direction -> Asset
sourceAsset NativeToWrapped = Native
sourceAsset WrappedToNative = Wrapped
destinationAsset NativeToWrapped = Wrapped
destinationAsset WrappedToNative = Native

-- A small, explicitly purchased gas credit. Its fee is fixed at admission;
-- the signed payout carries exactly these lamports in the same transaction.
data GasTopUp = GasTopUp { gasLamports :: !Amount, gasEcxFee :: !Amount } deriving (Eq,Show)
mkGasTopUp :: Amount -> Amount -> Either Text GasTopUp
mkGasTopUp lamports charge
  | units lamports>0 && units lamports<=10000000 && units charge>0 = Right (GasTopUp lamports charge)
  | otherwise = Left "invalid_gas_top_up"
instance ToJSON GasTopUp where
  toJSON g=object ["gasLamports" .= gasLamports g,"gasEcxFee" .= gasEcxFee g]
instance FromJSON GasTopUp where
  parseJSON=withObject "gas top-up" $ \o->do
    lamports<-o .: "gasLamports"
    charge<-o .: "gasEcxFee"
    either (fail . T.unpack) pure (mkGasTopUp lamports charge)

data Quote = Quote !Amount !Amount !Amount !(Maybe GasTopUp) deriving (Eq,Show)
gross, fee, net :: Quote -> Amount
gross (Quote g _ _ _) = g
fee (Quote _ f _ _) = f
net (Quote _ _ n _) = n
quoteGasTopUp :: Quote -> Maybe GasTopUp
quoteGasTopUp (Quote _ _ _ gas) = gas
instance ToJSON Quote where
  toJSON q = object $ ["gross" .= gross q, "fee" .= fee q, "net" .= net q]
    <> maybe [] (\gas->["gasTopUp" .= gas]) (quoteGasTopUp q)
instance FromJSON Quote where
  parseJSON = withObject "quote" $ \o -> do
    g <- o .: "gross"
    f <- o .: "fee"
    n <- o .: "net"
    gas <- o .:? "gasTopUp"
    q <- either (fail . T.unpack) pure (savedQuote g f gas)
    if net q == n then pure q else fail "inconsistent_quote"
-- New terms are always 1%. Existing terms are loaded verbatim, never repriced.
quote :: Amount -> Either Text Quote
quote input = quoteWithGas input Nothing
quoteWithGas :: Amount -> Maybe GasTopUp -> Either Text Quote
quoteWithGas input gas = do
  charge<-amount $ (toInteger (units input)+99) `div` 100 + maybe 0 (toInteger . units . gasEcxFee) gas
  savedQuote input charge gas
historicalQuote :: Amount -> Amount -> Either Text Quote
historicalQuote input charge = savedQuote input charge Nothing
savedQuote :: Amount -> Amount -> Maybe GasTopUp -> Either Text Quote
savedQuote input charge gas = do
  if maybe False ((>charge) . gasEcxFee) gas then Left "inconsistent_gas_fee" else pure ()
  if charge>=input then Left "nonpositive_net" else pure ()
  remaining <- amount (toInteger (units input)-toInteger (units charge))
  if units remaining==0 then Left "nonpositive_net" else Right (Quote input charge remaining gas)

data Funding
  = ConversionFunding !Text !Text !Direction !Quote
  | RefundFunding !Text !Text !Asset !Amount
  | EarnedFunding !Text !Asset !Amount
  deriving (Eq,Show)

-- Unidirectional patterns permit exhaustive reading, never unchecked construction.
pattern Conversion :: Text -> Text -> Direction -> Quote -> Funding
pattern Conversion order receipt direction terms <- ConversionFunding order receipt direction terms
pattern Refund :: Text -> Text -> Asset -> Amount -> Funding
pattern Refund order receipt asset quantity <- RefundFunding order receipt asset quantity
pattern EarnedFees :: Text -> Asset -> Amount -> Funding
pattern EarnedFees withdrawal asset quantity <- EarnedFunding withdrawal asset quantity
{-# COMPLETE Conversion, Refund, EarnedFees #-}

conversion :: Text -> Text -> Direction -> Quote -> Either Text Funding
conversion order receipt direction terms = do
  identifier order
  identifier receipt
  if direction/=NativeToWrapped && quoteGasTopUp terms/=Nothing then Left "gas_top_up_wrap_only" else pure ()
  pure (ConversionFunding order receipt direction terms)
refund :: Text -> Text -> Asset -> Amount -> Either Text Funding
refund order receipt asset quantity = do
  identifier order
  identifier receipt
  payout asset quantity
  pure (RefundFunding order receipt asset quantity)
earnedFees :: Text -> Asset -> Amount -> Either Text Funding
earnedFees withdrawal asset quantity = do
  identifier withdrawal
  payout asset quantity
  pure (EarnedFunding withdrawal asset quantity)

identifier :: Text -> Either Text ()
identifier key
  | T.null key || T.length key>256 || T.any (<' ') key = Left "invalid_identifier"
  | otherwise = Right ()
payout :: Asset -> Amount -> Either Text ()
payout asset quantity
  | asset==Sol = Left "invalid_payout_asset"
  | units quantity==0 = Left "nonpositive_payout"
  | otherwise = Right ()

data Payment = Payment !Text !Funding !Text deriving (Eq,Show)
paymentId, paymentRecipient :: Payment -> Text
paymentId (Payment key _ _) = key
paymentRecipient (Payment _ _ recipient) = recipient
paymentFunding :: Payment -> Funding
paymentFunding (Payment _ funding _) = funding
payment :: Text -> Funding -> Text -> Either Text Payment
payment key funding recipient = do
  identifier key
  if T.null recipient || T.length recipient>128 || T.any (<= ' ') recipient
    then Left "invalid_recipient" else Right (Payment key funding recipient)
paymentAsset :: Payment -> Asset
paymentAsset p = case paymentFunding p of
  ConversionFunding _ _ direction _ -> destinationAsset direction
  RefundFunding _ _ asset _ -> asset
  EarnedFunding _ asset _ -> asset
paymentAmount :: Payment -> Amount
paymentAmount p = case paymentFunding p of
  ConversionFunding _ _ _ terms -> net terms
  RefundFunding _ _ _ quantity -> quantity
  EarnedFunding _ _ quantity -> quantity
paymentGasLamports :: Payment -> Maybe Amount
paymentGasLamports p = case paymentFunding p of
  ConversionFunding _ _ NativeToWrapped terms -> gasLamports <$> quoteGasTopUp terms
  _ -> Nothing

data Account = External | Principal | Unallocated | Float | Earned | FeePending | Operating | Backing | Liquidity | SourceDeficit
  deriving (Eq,Ord,Show)
data Posting = Posting { postingAsset :: !Asset, postingAccount :: !Account, postingDelta :: !Integer }
  deriving (Eq,Show)

-- These are economic effects, not authorization to post them. The store must
-- prove finality and atomically enforce one settled winner before recording them.
-- Network fees/rent are separate verified operating costs, never deducted here.
settlement :: Payment -> [Posting]
settlement p = case paymentFunding p of
  ConversionFunding _ _ direction terms ->
    let source=sourceAsset direction; destination=destinationAsset direction
    in [Posting source Principal (negate $ value $ gross terms), Posting source Float (value $ net terms),
        Posting source Earned (value $ fee terms), Posting destination Float (negate $ value $ net terms),
        Posting destination External (value $ net terms)]
  RefundFunding _ _ asset quantity -> transfer asset Principal External quantity
  EarnedFunding _ asset quantity -> transfer asset FeePending External quantity
reserveEarned, releaseEarned :: Funding -> Either Text [Posting]
reserveEarned (EarnedFunding _ asset quantity) = Right (transfer asset Earned FeePending quantity)
reserveEarned _ = Left "earned_funding_required"
releaseEarned (EarnedFunding _ asset quantity) = Right (transfer asset FeePending Earned quantity)
releaseEarned _ = Left "earned_funding_required"
transfer :: Asset -> Account -> Account -> Amount -> [Posting]
transfer asset from to quantity = [Posting asset from (negate $ value quantity),Posting asset to (value quantity)]
value :: Amount -> Integer
value = toInteger . units
