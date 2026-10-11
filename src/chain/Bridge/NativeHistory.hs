{-# LANGUAGE ScopedTypeVariables #-}
-- Fixed read-only wallet history RPC. Capture and validate the entire response
-- before replay; no callback can observe a truncated or error response.
module Bridge.NativeHistory (readHistory,readTransaction) where

import Bridge.Error
import Bridge.File (hashHandle)
import Bridge.RPC (fieldValue,parseValue,retryRpcRead)
import Control.Concurrent (threadDelay)
import Control.Exception (bracket,catch,onException)
import Control.Monad (unless)
import Data.Aeson
import qualified Data.Aeson.KeyMap as KM
import Data.Aeson.Decoding (toEitherValue)
import Data.Aeson.Decoding.ByteString.Lazy (lbsToTokens)
import Data.Aeson.Decoding.Tokens
import qualified Data.ByteString as B
import qualified Data.ByteString.Char8 as BC
import qualified Data.ByteString.Lazy as L
import qualified Data.Set as S
import Data.Text (Text)
import qualified Data.Text as T
import GHC.IO.Handle (hDuplicate)
import Network.HTTP.Client
import Network.HTTP.Client.TLS (tlsManagerSettings)
import Network.HTTP.Types.Status (statusCode)
import System.Directory (getTemporaryDirectory,removeFile)
import System.IO
import Text.Read (readMaybe)

readHistory :: String -> (B.ByteString,B.ByteString) -> Text -> Int
  -> (Text -> Value -> IO ()) -> IO Text
readHistory url auth cursor depth consume =
  withCapture url auth "listsinceblock" [toJSON cursor,toJSON depth,Bool False,Bool True]
    (\h->replay h $ history (const $ pure ())) $ \capture anchor->do
      repeated<-replay capture (history $ consume anchor)
      require (repeated==anchor) "native_history_capture_changed"
      pure anchor

-- Incoming/source transactions only: authored payout validation still uses the
-- complete ordinary RPC. The capture hash also fences fields omitted here.
readTransaction :: String -> (B.ByteString,B.ByteString) -> Text -> IO Value
readTransaction url auth tx =
  withCapture url auth "gettransaction" [toJSON tx,Bool False,Bool True]
    (\h->replay h transaction) $ \capture result->do
      hSeek capture AbsoluteSeek 0
      fingerprint<-hashHandle capture
      case result of
        Object fields->pure $ Object (KM.insert "rpcCaptureHash" (String fingerprint) fields)
        _->reject "unexpected_rpc_schema"

replay :: Handle -> (L.ByteString -> IO a) -> IO a
replay capture parse = do
  hSeek capture AbsoluteSeek 0
  bracket (hDuplicate capture) hClose $ \h->L.hGetContents h >>= parse

withCapture :: String -> (B.ByteString,B.ByteString) -> Text -> [Value]
  -> (Handle -> IO a) -> (Handle -> a -> IO b) -> IO b
withCapture url (username,password) methodName params validate consume =
  -- The general manager buffers HTTPS responses for provider rate limits.
  -- This local-node-only session streams HTTP and HTTPS alike, without proxies.
  bracket (newManager $ managerSetProxy noProxy tlsManagerSettings
    {managerRetryableException=const False,managerConnCount=1
    ,managerResponseTimeout=responseTimeoutMicro 15000000}) closeManager $ \manager->do
    base<-parseRequest url
    let request=applyBasicAuth username password base
          {method="POST",redirectCount=0,checkResponse= \_ _->pure ()
          ,requestHeaders=[("Content-Type","application/json")]
          ,requestBody=RequestBodyLBS $ encode $ object
            ["jsonrpc" .= ("2.0"::Text),"id" .= (1::Int),"method" .= methodName,"params" .= params]}
    directory<-getTemporaryDirectory
    -- Unlink immediately: only this open descriptor owns the private capture,
    -- including on cancellation/process death. Replays never reopen a pathname.
    bracket (do
      (name,h)<-openBinaryTempFile directory "ecx-native-history"
      removeFile name `onException` hClose h
      pure h) hClose $ \capture->do
      let fetch=do
            hSeek capture AbsoluteSeek 0
            hSetFileSize capture 0
            withResponse request manager $ \response->do
              let code=statusCode(responseStatus response)
                  delay=fmap (maybe maxBound id . readMaybe . BC.unpack) $ lookup "Retry-After" (responseHeaders response)
              require (code/=403) "rpc_method_forbidden"
              if code==429 then pure (Left delay) else do
                let copy=do
                      chunk<-brRead(responseBody response)
                      unless (B.null chunk) (B.hPut capture chunk >> copy)
                copy
                hFlush capture
                (do anchor<-validate capture
                    require (code==200) "rpc_http_status"
                    pure (Right anchor)) `catch` (\(BridgeError reason)->
                  if reason=="rpc_error_429" then pure (Left delay) else reject reason)
      anchor<-retryRpcRead threadDelay methodName fetch
        `catch` (\(_::HttpException)->reject "rpc_transport_unknown_outcome")
      -- Never retry a consumer: it may already have inspected some entries.
      consume capture anchor

-- Token traversal retains one entry, not the aggregate history. Aeson owns JSON
-- syntax/UTF-8/number parsing. Duplicate envelope/history keys are ambiguous.
history :: (Value -> IO ()) -> L.ByteString -> IO Text
history emit input=case lbsToTokens input of
  TkRecordOpen fields->envelope S.empty Nothing Nothing fields
  _->reject "rpc_invalid_json"
 where
  scalar tokens=either (const $ reject "rpc_invalid_json") pure (toEitherValue tokens)
  fresh key seen=require (not $ S.member key seen) "rpc_duplicate_field"
  envelope seen result failure (TkPair key tokens)=do
    fresh key seen
    let next=envelope (S.insert key seen)
    case key of
      "result"->case tokens of
        TkRecordOpen fields->do (anchor,rest)<-record S.empty Nothing fields; next (Just anchor) failure rest
        _->do (value,rest)<-scalar tokens; require (value==Null) "unexpected_rpc_schema"; next Nothing failure rest
      "id"->do (value,rest)<-scalar tokens; require (value==Number 1) "rpc_id_mismatch"; next result failure rest
      "error"->do
        (value,rest)<-scalar tokens
        code<-if value==Null then pure Nothing else Just <$> (fieldValue "code" value :: IO Int)
        next result code rest
      "jsonrpc"->do (value,rest)<-scalar tokens; require (value==String "2.0") "unexpected_rpc_schema"; next result failure rest
      _->reject "unexpected_rpc_schema"
  envelope seen result failure (TkRecordEnd trailing)=do
    require (S.member "id" seen) "unexpected_rpc_schema"
    require (L.all (`elem` [9,10,13,32]) trailing) "rpc_invalid_json"
    maybe (pure ()) (\code->reject $ "rpc_error_"<>T.pack(show code)) failure
    maybe (reject "unexpected_rpc_schema") pure result
  envelope _ _ _ _=reject "rpc_invalid_json"
  record seen anchor (TkPair key tokens)=do
    fresh key seen
    let next=record (S.insert key seen)
    case key of
      "lastblock"->do
        (value,rest)<-scalar tokens
        block<-parseValue parseJSON value
        require (T.length block==64 && T.all (`elem` ("0123456789abcdef"::String)) block) "invalid_native_scan_cursor"
        next (Just block) rest
      "transactions"->entries tokens >>= next anchor
      "removed"->entries tokens >>= next anchor
      _->reject "unexpected_rpc_schema"
  record seen anchor (TkRecordEnd rest)=do
    require (seen==S.fromList ["lastblock","transactions","removed"]) "unexpected_rpc_schema"
    maybe (reject "unexpected_rpc_schema") (\block->pure(block,rest)) anchor
  record _ _ _=reject "rpc_invalid_json"
  entries (TkArrayOpen items)=loop items
  entries _=reject "unexpected_rpc_schema"
  loop (TkItem tokens)=do
    (value,rest)<-scalar tokens
    emit value
    loop rest
  loop (TkArrayEnd rest)=pure rest
  loop _=reject "rpc_invalid_json"

-- ECX ca64033c: stripped size * 4 <= 4,000,000; each output costs
-- at least 9 bytes. Wallet details can contain send AND receive per output.
-- These are consensus-derived ceilings, not a customer transaction-size policy.
data Projection = Scalar | Fields [(Key,Projection)] | Items Int Projection | Outputs | Conflicts

transaction :: L.ByteString -> IO Value
transaction input=case lbsToTokens input of
  TkRecordOpen fields->envelope S.empty Nothing Nothing fields
  _->reject "rpc_invalid_json"
 where
  layout=Fields
    [("txid",Scalar),("confirmations",Scalar),("blockhash",Scalar),("amount",Scalar),("fee",Scalar)
    ,("walletconflicts",Conflicts)
    ,("lastprocessedblock",Fields [("hash",Scalar),("height",Scalar)])
    ,("decoded",Fields [("txid",Scalar),("vout",Outputs)])
    ,("details",Items 222222 $ Fields [("category",Scalar),("address",Scalar),("vout",Scalar),("amount",Scalar)])]
  scalar tokens=either (const $ reject "rpc_invalid_json") pure (toEitherValue tokens)
  envelope seen result failure (TkPair key tokens)=do
    require (not $ S.member key seen) "rpc_duplicate_field"
    let next=envelope (S.insert key seen)
    case key of
      "result"->case tokens of
        TkLit LitNull rest->next Nothing failure rest
        _->do (value,rest)<-project layout tokens; next (Just value) failure rest
      "id"->do (value,rest)<-scalar tokens; require (value==Number 1) "rpc_id_mismatch"; next result failure rest
      "error"->do
        (value,rest)<-project (Fields [("code",Scalar)]) tokens
        code<-if value==Null then pure Nothing else Just <$> (fieldValue "code" value :: IO Int)
        next result code rest
      "jsonrpc"->do (value,rest)<-scalar tokens; require (value==String "2.0") "unexpected_rpc_schema"; next result failure rest
      _->reject "unexpected_rpc_schema"
  envelope seen result failure (TkRecordEnd trailing)=do
    require (S.member "id" seen) "unexpected_rpc_schema"
    require (L.all (`elem` [9,10,13,32]) trailing) "rpc_invalid_json"
    maybe (pure ()) (\code->reject $ "rpc_error_"<>T.pack(show code)) failure
    maybe (reject "unexpected_rpc_schema") pure result
  envelope _ _ _ _=reject "rpc_invalid_json"

project :: Projection -> Tokens k e -> IO (Value,k)
project _ (TkLit LitNull rest)=pure (Null,rest)
project Scalar tokens=case tokens of
  TkText _ _->scalar
  TkNumber _ _->scalar
  TkLit _ _->scalar
  _->reject "unexpected_rpc_schema"
 where scalar=either (const $ reject "rpc_invalid_json") pure (toEitherValue tokens)
project (Fields allowed) (TkRecordOpen fields)=record KM.empty fields
 where
  record saved (TkPair key tokens)=case lookup key allowed of
    Nothing->skip 0 tokens >>= record saved
    Just shape->do
      require (not $ KM.member key saved) "rpc_duplicate_field"
      (value,rest)<-project shape tokens
      record (KM.insert key value saved) rest
  record saved (TkRecordEnd rest)=pure (Object saved,rest)
  record _ _=reject "rpc_invalid_json"
project (Items bound shape) (TkArrayOpen items)=array bound shape False items
project Outputs (TkArrayOpen items)=array 111111
  (Fields [("n",Scalar),("value",Scalar),("scriptPubKey",Fields [("hex",Scalar),("address",Scalar)])]) True items
-- Conflict history is not consensus-bounded. Consumers need emptiness and
-- complete evidence binding, not an in-memory list of every historical spender.
-- rpcCaptureHash binds its exact bytes; this projected field is a count.
project Conflicts (TkArrayOpen items)=conflicts 0 items
 where
  conflicts count (TkItem (TkText tx rest))=do
    require (T.length tx==64 && T.all (`elem` ("0123456789abcdef"::String)) tx) "invalid_native_source_conflicts"
    let next=count+1 :: Integer
    next `seq` conflicts next rest
  conflicts count (TkArrayEnd rest)=pure (toJSON count,rest)
  conflicts _ _=reject "invalid_native_source_conflicts"
project _ _=reject "unexpected_rpc_schema"

array :: Int -> Projection -> Bool -> TkArray k e -> IO (Value,k)
array bound shape outputs=loop 0 0 []
 where
  loop count scriptBytes values (TkItem tokens)=do
    require (count<bound) "native_transaction_consensus_bound"
    (value,rest)<-project shape tokens
    size<-if outputs then do
      index<-fieldValue "n" value
      require (index==count) "native_output_index_invalid"
      script<-fieldValue "scriptPubKey" value >>= fieldValue "hex" :: IO Text
      let n=T.length script
      require (even n && T.all (`elem` ("0123456789abcdef"::String)) script
        && n<=2000000-scriptBytes) "native_transaction_consensus_bound"
      pure n
     else pure 0
    let total=scriptBytes+size
    total `seq` loop (count+1) total (value:values) rest
  loop _ _ values (TkArrayEnd rest)=pure (toJSON $ reverse values,rest)
  loop _ _ _ _=reject "rpc_invalid_json"

-- Traverse discarded subtrees without constructing aggregate Values. Aeson
-- still materializes individual strings; this is not a constant-memory scalar
-- decoder. Core's transaction hex is bounded; local wallet metadata is trusted.
skip :: Int -> Tokens k e -> IO k
skip depth tokens=do
  require (depth<128) "unexpected_rpc_schema"
  case tokens of
    TkLit _ rest->pure rest
    TkText _ rest->pure rest
    TkNumber _ rest->pure rest
    TkArrayOpen items->itemsLoop items
    TkRecordOpen fields->fieldsLoop fields
    TkErr _->reject "rpc_invalid_json"
 where
  itemsLoop (TkItem value)=skip (depth+1) value >>= itemsLoop
  itemsLoop (TkArrayEnd rest)=pure rest
  itemsLoop _=reject "rpc_invalid_json"
  fieldsLoop (TkPair _ value)=skip (depth+1) value >>= fieldsLoop
  fieldsLoop (TkRecordEnd rest)=pure rest
  fieldsLoop _=reject "rpc_invalid_json"
