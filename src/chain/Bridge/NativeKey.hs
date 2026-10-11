{-# LANGUAGE ForeignFunctionInterface #-}
-- Offline key validation/derivation only; no signing, RPC or mutable global context.
module Bridge.NativeKey (deriveChild,validMainnetXpub) where
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

-- BIP32 public serialization only: checksum, mainnet version, root metadata,
-- and an actual compressed curve point. Never accept a private extended key.
validMainnetXpub :: T.Text -> IO Bool
validMainnetXpub encoded
  | T.length encoded /= 111 = pure False
  | otherwise = case B58.decodeBase58 B58.bitcoinAlphabet (TE.encodeUtf8 encoded) of
      Just bytes | B.length bytes == 82 -> do
        let payload = B.take 78 bytes
            sha value = BA.convert (hash value :: Digest SHA256) :: B.ByteString
            public = B.drop 45 payload
            valid = B.take 4 payload == B.pack [0x04,0x88,0xb2,0x1e]
              && B.drop 78 bytes == B.take 4 (sha $ sha payload)
              && (B.index payload 4 /= 0 || B.take 8 (B.drop 5 payload) == B.replicate 8 0)
              && B.head public `elem` [2,3]
        if not valid then pure False else
          B.useAsCString public $ \key -> (==1) <$> nativePublicValid (castPtr key)
      _ -> pure False

foreign import ccall unsafe "ecx_native_public_valid"
  nativePublicValid :: Ptr Word8 -> IO CInt
