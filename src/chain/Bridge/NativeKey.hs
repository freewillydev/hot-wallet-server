{-# LANGUAGE ForeignFunctionInterface #-}
-- Offline key validation/derivation only; no signing, RPC or mutable global context.
module Bridge.NativeKey (deriveChild,validMainnetXpub,validNetworkXpub,validNativeAddress,validOwnerDestination) where
import Crypto.Hash (Digest,SHA256,hash)
import qualified Data.ByteArray as BA
import qualified Data.ByteString.Base58 as B58
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Crypto.Random (getRandomBytes)
import Control.Exception (finally)
import qualified Data.ByteString as B
import Foreign (Ptr,allocaBytes,castPtr,fillBytes)
import Foreign.C.Types (CInt(..))
import Data.Word (Word8)
import Data.Bits ((.&.),xor,shiftL,shiftR,testBit)
import Data.Char (ord)

-- Returns child scalar and compressed parent public key. A zero tweak validates
-- a master key without changing it. Invalid scalars/zero children fail closed.
deriveChild :: B.ByteString -> B.ByteString -> IO (Maybe (B.ByteString,B.ByteString))
deriveChild parent tweak
  | B.length parent/=32 || B.length tweak/=32 = pure Nothing
  | otherwise = do
      randomness<-getRandomBytes 32
      B.useAsCString parent $ \p -> B.useAsCString tweak $ \t ->
        B.useAsCString randomness $ \r -> allocaBytes 32 $ \child -> allocaBytes 33 $ \public -> do
          (do
            ok<-nativeChild (castPtr p) (castPtr t) (castPtr r) child public
            if ok/=1 then pure Nothing else do
              secret<-B.packCStringLen (castPtr child,32)
              pub<-B.packCStringLen (castPtr public,33)
              pure (Just (secret,pub))) `finally` fillBytes child 0 32

foreign import ccall unsafe "ecx_native_child"
  nativeChild :: Ptr Word8 -> Ptr Word8 -> Ptr Word8 -> Ptr Word8 -> Ptr Word8 -> IO CInt

-- BIP32 public serialization only: checksum, network version, root metadata,
-- and an actual compressed curve point. Never accept a private extended key.
validMainnetXpub :: T.Text -> IO Bool
validMainnetXpub = validNetworkXpub False

validNetworkXpub :: Bool -> T.Text -> IO Bool
validNetworkXpub signet encoded
  | T.length encoded /= 111 = pure False
  | otherwise = case B58.decodeBase58 B58.bitcoinAlphabet (TE.encodeUtf8 encoded) of
      Just bytes | B.length bytes == 82 -> do
        let payload = B.take 78 bytes
            sha value = BA.convert (hash value :: Digest SHA256) :: B.ByteString
            public = B.drop 45 payload
            valid = B.take 4 payload == B.pack (if signet then [0x04,0x35,0x87,0xcf] else [0x04,0x88,0xb2,0x1e])
              && B.drop 78 bytes == B.take 4 (sha $ sha payload)
              && (B.index payload 4 /= 0 || B.take 8 (B.drop 5 payload) == B.replicate 8 0)
              && B.head public `elem` [2,3]
        if not valid then pure False else
          B.useAsCString public $ \key -> (==1) <$> nativePublicValid (castPtr key)
      _ -> pure False

foreign import ccall unsafe "ecx_native_public_valid"
  nativePublicValid :: Ptr Word8 -> IO CInt

-- Owner fees accept a normal receiving address or the existing account xpub.
-- This is offline encoding/network validation; the node still checks the script
-- and rejects custody-owned/watch-only destinations before reserving a payout.
validOwnerDestination :: Bool -> T.Text -> IO Bool
validOwnerDestination signet destination
  | validNativeAddress signet destination = pure True
  | otherwise = validNetworkXpub signet destination

validNativeAddress :: Bool -> T.Text -> Bool
validNativeAddress signet address
  | T.length address<14 || T.length address>90 || not(T.all (\c->c>='!' && c<='~') address) = False
  | otherwise = legacy || witness
 where
  legacy=case B58.decodeBase58 B58.bitcoinAlphabet (TE.encodeUtf8 address) of
    Just bytes | B.length bytes==25 ->
      let payload=B.take 21 bytes
          sha value=BA.convert(hash value :: Digest SHA256) :: B.ByteString
      in B.head bytes `elem` (if signet then [111,196] else [0,5])
        && B.drop 21 bytes==B.take 4(sha $ sha payload)
    _->False
  -- BIP173/BIP350: support only the witness scripts the payout engine supports:
  -- v0 with 20/32 bytes, or v1 with 32 bytes. A 52-word program has four padding
  -- bits, which must be zero; a 32-word program has no padding.
  witness=case T.stripPrefix (hrp<>"1") (T.toLower address) >>= traverse word . T.unpack of
    Just values@(version:remaining) | length values>=7 ->
      let program=take (length values-7) remaining
          size=length program
          supported=(version==0 && size `elem` [32,52]) || (version==1 && size==52)
          caseOK=address==T.toLower address || address==T.toUpper address
          expanded=map ((`shiftR` 5).ord) (T.unpack hrp)<>[0]<>map ((.&.31).ord) (T.unpack hrp)
      in supported && caseOK && (size==32 || last program .&. 15==0)
        && foldl' polymod 1 (expanded<>values)==(if version==0 then 1 else 0x2bc830a3)
    _->False
  hrp=if signet then "tb" else "bc"
  word character=T.findIndex (==character) "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
  polymod check value=foldl' xor (((check .&. 0x1ffffff) `shiftL` 5) `xor` value)
    [generator | (bit,generator)<-zip [0..] [0x3b6a57b2,0x26508e6d,0x1ea119fa,0x3d4233dd,0x2a1462b3]
      ,testBit (check `shiftR` 25) bit]
