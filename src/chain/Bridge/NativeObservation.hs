-- Native wallet observation using the actual daemon RPC contract.
module Bridge.NativeObservation (scanNativeWith) where
import Bridge.Domain
import Bridge.Wire
import Bridge.Native
import Bridge.RPC
import Bridge.Error
import Bridge.Identity (digest,emptyNativeReceipts,addNativeReceipt,nativeReceiptCommitment)
import Control.Monad (forM,forM_,foldM,when)
import Data.Aeson
import qualified Data.ByteString.Lazy as LBS
import Data.Int (Int64)
import Data.IORef
import Data.List (sortOn)
import qualified Data.IntMap.Strict as IM
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import Text.Read (readMaybe)

optionalField :: FromJSON a => Key -> Value -> IO (Maybe a)
optionalField key = parseValue (withObject "RPC object" (.:? key))

isHash :: Text -> Bool
isHash value = T.length value==64 && T.all (`elem` ("0123456789abcdef"::String)) value

-- Complete capture is validated before any callback. Pages keep the original
-- checkpoint; only the returned empty completion batch may advance coverage.
scanNativeWith :: (Bool -> Text -> [Value] -> IO Value)
  -> (Text -> Int -> (Text -> Value -> IO ()) -> IO Text) -> (Text -> IO Value) -> NativeSettings
  -> Int -> Int -> Maybe Text -> Int64 -> (Maybe Text -> IO [Deposit])
  -> (Text -> IO (Maybe (Text,OrderRequest,PolicySnapshot)))
  -> (ScanBatch -> IO ()) -> IO ScanBatch
scanNativeWith call history transaction c defaultDepth depth previous now recoveryPage lookupInstruction emit = do
  require (defaultDepth>=1 && depth>=defaultDepth && now>=0) "invalid_native_scan_policy"
  require (maybe True isHash previous) "invalid_native_scan_cursor"
  info <- nativeIdentityWith call c
  wallet <- nativeWalletInfoWith call c
  tip <- fieldValue "blocks" info :: IO Int64
  processed <- fieldValue "lastprocessedblock" wallet
  height <- fieldValue "height" processed :: IO Int64
  walletHash <- fieldValue "hash" processed :: IO Text
  activeHash <- call False "getblockhash" [toJSON height] >>= parseValue parseJSON
  require (height>=tip && walletHash==activeHash) "native_wallet_behind_chain"
  when (previous==Nothing) $ do
    born <- fieldValue "birthtime" wallet :: IO Int64
    header <- call False "getblockheader" [toJSON (nativeCheckpointHash c)]
    checkpointTime <- fieldValue "time" header :: IO Int64
    require (born>=checkpointTime) "native_wallet_predates_scan_origin"
  lastTransaction<-newIORef Nothing
  let batch next deposits events=ScanBatch "Native" (nativeCheckpointHash c) previous next now deposits events
      observe next tx=do
        require (isHash tx) "invalid_native_transaction_id"
        lastSeen<-readIORef lastTransaction
        when (lastSeen/=Just tx) $ do
          (deposits,events)<-readTransaction tx
          let pages remaining=case splitAt 1000 remaining of
                (page,[])->emit (batch next page events)
                (page,rest)->emit (batch next page []) >> pages rest
          pages deposits
          writeIORef lastTransaction (Just tx)
      recover next after=do
        sources<-recoveryPage after
        forM_ sources $ \source->case T.splitOn ":" (depositId source) of
          ["native",tx,n] | depositAsset source==Native,isHash tx,
            Just index<-(readMaybe (T.unpack n)::Maybe Int),index>=0->observe next tx
          _->reject "invalid_native_deposit_id"
        case reverse sources of
          []->pure ()
          source:_->do
            let key=depositId source
            require (maybe True (<key) after) "invalid_native_recovery_cursor"
            recover next (Just key)
  next<-history (maybe (nativeCheckpointHash c) id previous) depth $ \anchor entry->do
    require (isHash anchor) "invalid_native_scan_cursor"
    fieldValue "txid" entry >>= observe anchor
  require (isHash next) "invalid_native_scan_cursor"
  recover next Nothing
  pure (batch next [] [])
 where
  readTransaction txid = do
    value <- transaction txid
    actual <- fieldValue "txid" value
    require (actual==txid) "native_transaction_identity_mismatch"
    confirmations <- fieldValue "confirmations" value :: IO Int
    anchor <- optionalField "blockhash" value
    require (confirmations<=0 || maybe False isHash anchor) "native_block_anchor_missing"
    decoded <- fieldValue "decoded" value
    decodedId <- fieldValue "txid" decoded
    require (decodedId==txid) "native_decoded_identity_mismatch"
    walletAmount <- fieldValue "amount" value
    magnitude <- either reject pure (nativeAmount $ abs walletAmount)
    feeValue <- optionalField "fee" value
    feeAmount <- mapM (either reject pure . nativeAmount . abs) feeValue
    let walletUnits=toInteger (units magnitude) * if walletAmount<0 then -1 else 1
    outputs <- fieldValue "vout" decoded :: IO [Value]
    details <- fieldValue "details" value :: IO [Value]
    require (length outputs<=111111 && length details<=222222) "native_transaction_consensus_bound"
    let indexed=IM.fromDistinctAscList (zip [0..] outputs)
    rows <- forM details $ \detail -> do
      category <- fieldValue "category" detail :: IO Text
      if category=="send" then pure ([],True) else do
        require (category `elem` ["receive","generate","immature","orphan"]) "native_category_unsupported"
        address <- fieldValue "address" detail
        outpoint <- fieldValue "vout" detail :: IO Int
        output<-maybe (reject "native_output_index_invalid") pure (IM.lookup outpoint indexed)
        outputIndex <- fieldValue "n" output :: IO Int
        detailAmount <- fieldValue "amount" detail >>= either reject pure . nativeAmount
        outputAmount <- fieldValue "value" output >>= either reject pure . nativeAmount
        require (outputIndex==outpoint && detailAmount==outputAmount && units outputAmount>0) "native_output_amount_mismatch"
        addressInfo <- call True "getaddressinfo" [toJSON (address::Text)]
        owned <- fieldValue "ismine" addressInfo :: IO Bool
        script <- fieldValue "scriptPubKey" addressInfo :: IO Text
        outputScript <- fieldValue "scriptPubKey" output >>= fieldValue "hex"
        require (owned && script==outputScript) "native_output_script_mismatch"
        binding <- if category=="receive" then lookupInstruction address else pure Nothing
        (order,required) <- case binding of
          Nothing -> pure (Nothing,if category=="receive" then defaultDepth else max 101 defaultDepth)
          Just (oid,request,policy) -> do
            require (direction request==NativeToWrapped) "native_instruction_direction_mismatch"
            require (nativeDepth policy>0 && nativeDepth policy<=depth) "invalid_saved_native_depth"
            pure (Just oid,nativeDepth policy)
        let receipt=Deposit ("native:"<>txid<>":"<>T.pack(show outpoint)) order Native outputAmount
              (maybe "unconfirmed" id anchor) (max 0 confirmations) (confirmations>=required && category/="orphan") now
        pure ([receipt],False)
    let deposits=concatMap fst rows
    require (Set.size (Set.fromList $ map depositId deposits)==length deposits) "duplicate_native_receipt"
    commitment<-foldM (\state receipt->either reject pure $ addNativeReceipt state receipt) emptyNativeReceipts (sortOn (\d->(T.length $ depositId d,depositId d)) deposits)
    captureHash<-optionalField "rpcCaptureHash" value :: IO (Maybe Text)
    let sending=or (map snd rows)
        evidence=object ["txid" .= txid,"confirmations" .= confirmations,"blockhash" .= anchor
          ,"walletNetUnits" .= T.pack(show walletUnits),"feeUnits" .= feeAmount
          ,"receiptCommitment" .= nativeReceiptCommitment commitment
          ,"rpcCaptureHash" .= maybe (digest $ LBS.toStrict $ encode value) id captureHash]
        kind | sending = "outgoing"
             | any ((/=Nothing) . depositOrder) deposits = "incoming"
             | not (null deposits) = "unmatched_incoming"
             | otherwise = "reference"
    pure (deposits,[ChainEvent txid kind (maybe "unconfirmed" id anchor) evidence])
