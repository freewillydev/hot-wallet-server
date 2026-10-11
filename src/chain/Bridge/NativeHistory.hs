{-# LANGUAGE ScopedTypeVariables #-}
-- Fixed read-only wallet history RPC. Capture and validate the entire response
-- before replay; no callback can observe a truncated or error response.
module Bridge.NativeHistory (readHistory) where

import Bridge.Error
import Bridge.RPC (fieldValue,parseValue,retryRpcRead)
import Control.Concurrent (threadDelay)
import Control.Exception (bracket,catch,onException)
import Control.Monad (unless)
import Data.Aeson
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
readHistory url (username,password) cursor depth consume =
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
            ["jsonrpc" .= ("2.0"::Text),"id" .= (1::Int),"method" .= ("listsinceblock"::Text)
            ,"params" .= [toJSON cursor,toJSON depth,Bool False,Bool True]]}
    directory<-getTemporaryDirectory
    -- Unlink immediately: only this open descriptor owns the private capture,
    -- including on cancellation/process death. Replays never reopen a pathname.
    bracket (do
      (name,h)<-openBinaryTempFile directory "ecx-native-history"
      removeFile name `onException` hClose h
      pure h) hClose $ \capture->do
      let replay emit=do
            hSeek capture AbsoluteSeek 0
            bracket (hDuplicate capture) hClose $ \h->L.hGetContents h >>= history emit
          fetch=do
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
                (do anchor<-replay (const $ pure ())
                    require (code==200) "rpc_http_status"
                    pure (Right anchor)) `catch` (\(BridgeError reason)->
                  if reason=="rpc_error_429" then pure (Left delay) else reject reason)
      anchor<-retryRpcRead threadDelay "listsinceblock" fetch
        `catch` (\(_::HttpException)->reject "rpc_transport_unknown_outcome")
      -- Never retry a consumer: it may already have inspected some entries.
      repeated<-replay (consume anchor)
      require (repeated==anchor) "native_history_capture_changed"
      pure anchor

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
