-- Captured finalized Devnet proofs and offline SDK/RPC contracts, never sends.
module SolanaPaymentCheck (checks) where
import Bridge.Domain (Amount, Asset(..), Direction(..), amount, units, earnedFees, payment)
import Bridge.Payment
import Bridge.Admission (checkSolanaQuoteWith,checkSolanaPayoutWith)
import Bridge.PaymentObservation
import Bridge.Store
import qualified Bridge.Wire as W
import qualified Data.ByteString.Lazy as BL
import Bridge.Error
import Bridge.RPC (fieldValue)
import Bridge.Solana (tokenProgram,solanaGenesis)
import Bridge.SolanaHelper
import Bridge.SolanaMessage
import Bridge.SolanaPayment
import Bridge.SDKBuild (sdkLibraryPath)
import Control.Exception (try)
import Crypto.Error (CryptoFailable(..))
import qualified Crypto.PubKey.Ed25519 as Ed
import Data.Aeson hiding (Result)
import Data.ByteArray (convert)
import qualified Data.Aeson.KeyMap as KM
import qualified Data.ByteString as BS
import qualified Data.ByteString.Base64 as B64
import Data.IORef
import Data.Bits (xor)
import Data.List (elemIndex)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Paths_ecx_bridge (getDataFileName)
import Test.QuickCheck

checks :: IO [Result]
checks=do
  fixture <- readFixture "signed-three-units.json"
  unsignedFixture <- readFixture "unsigned-three-units.json"
  unsignedReply <- fieldValue "reply" unsignedFixture
  reply <- fieldValue "reply" fixture
  owner <- fieldValue "owner" fixture
  recipient <- fieldValue "recipient" fixture
  token <- fieldValue "mint" fixture
  hash <- fieldValue "blockhash" fixture
  let config=SolanaPolicy "codec-fixture" "offline-policy" token owner (replySource reply) (amt 10000) (amt 2100000)
      plan=SolanaPlan (fingerprint config) recipient (amt 3) "order-1" (RecentBlockhash hash 1000 100) (maxSolFee config) (maxSolAccountRent config) Nothing
      request=solanaPayoutRequest config plan
      call destination method _=case method of
        "getBlockHeight"->pure (Number 900)
        "getFeeForMessage"->pure (context $ Number 5000)
        "getMultipleAccounts"->pure $ context $ toJSON [tokenAccount config owner,destination,systemAccount 10000000]
        "getMinimumBalanceForRentExemption"->pure (Number 1488440)
        "simulateTransaction"->pure $ context $ object ["err" .= Null]
        _->fail ("unexpected RPC: "<>T.unpack method)
      prepare p rpcCall=prepareSolanaSigned rpcCall (const $ pure reply) config p
  workflowFixture <- readFixture "signed-payment-workflow.json"
  workflowReply <- fieldValue "reply" workflowFixture
  identifier <- fieldValue "paymentId" workflowFixture
  funding <- either reject pure (earnedFees (T.drop 4 identifier) Wrapped $ amt 3)
  outgoing <- either reject pure (payment identifier funding recipient)
  let encoded value=TE.decodeUtf8 (BL.toStrict $ encode value)
      boundPlan=plan {solPlanReference=payoutReference (fingerprint config) identifier}
      boundRequest=solanaPayoutRequest config boundPlan
      terms=W.PaymentTerms (W.PolicySnapshot 1 "finalized" $ fingerprint config)
        (W.CostLimits (amt 1) (maxSolFee config) (maxSolAccountRent config))
      prepared=PreparedPayment (PaymentView outgoing terms PaymentPaying) 0 (encoded boundPlan)
        (Just $ encoded boundRequest) (amt 2110000)
      boundSigned=SolanaSigned boundPlan workflowReply (amt 5000) (amt 1488440)
      verify=verifySigningReply (\_ _ _->fail "Solana validation must not call native RPC") W.L2LSignetDevnet config
  proofResults <- mapM captured ["new","existing"]
  local <- sequence
    [ check "optional SOL gas preserves old encodings and binds one exact atomic transfer" $ once $ ioProperty $ do
        ordinary<-invokeUnsignedHelper sdkLibraryPath config request
        original<-either reject pure (validateHelperReply config request reply)
        let oldPlan=case toJSON plan of Object fields->not(KM.member "solPlanGasLamports" fields); _->False
            oldRequest=case toJSON request of Object fields->not(KM.member "gas_lamports" fields); _->False
            gasPlan=plan {solPlanGasLamports=Just $ amt 1000000}
            gasRequest=solanaPayoutRequest config gasPlan
        gasReply<-signedGasReply config gasRequest
        transaction<-either reject pure (validateHelperReply config gasRequest gasReply)
        rejectedDeposit<-rejectsAny $ invokeUnsignedHelper sdkLibraryPath config gasRequest {helperPayout=False}
        let altered=[gasRequest {requestGasLamports=Nothing},gasRequest {requestGasLamports=Just $ amt 999999}
              ,gasRequest {requestGasLamports=Just $ amt 0}]
            instructionCount=case transaction of Transaction _ (Message _ _ _ _ _ instructions) _->length instructions
        pure (oldPlan && oldRequest && eitherDecode(encode plan)==Right plan && eitherDecode(encode request)==Right request
          && replyTransaction ordinary==unsignedSimulation original && instructionCount==4 && rejectedDeposit
          && solanaOperatingLimit gasPlan==Right(amt 3110000)
          && all (isLeft . (\wanted->validateHelperReply config wanted gasReply)) altered)
    , check "SOL gas settlement requires exact recipient credit and accounts failed transactions as fee only" $ once $ ioProperty $ do
        let gasPlan=plan {solPlanGasLamports=Just $ amt 1000000}
            gasRequest=solanaPayoutRequest config gasPlan
        gasReply<-signedGasReply config gasRequest
        let signed=SolanaSigned gasPlan gasReply (amt 5000) (amt 1488440)
            inspect=verifySolanaOutcome config signed
        success<-gasProof config signed True 1488440 1000000
        existing<-gasProof config signed True 0 1000000
        failure<-gasProof config signed False 0 0
        missing<-gasProof config signed True 1488440 0
        excessive<-gasProof config signed True 1488440 1000001
        failedGift<-gasProof config signed False 0 1000000
        let gasRPC wallet balance method args=case method of
              "getMultipleAccounts"->pure $ context $ toJSON [tokenAccount config owner,Null,systemAccount balance,wallet]
              "getMinimumBalanceForRentExemption" | take 1 args==[Number 0]->pure (Number 890880)
              _->call Null method args
            prepareGas rpcCall=prepareSolanaSigned rpcCall (const $ pure gasReply) config gasPlan
        _<-prepareGas (gasRPC Null 10000000)
        _<-prepareGas (gasRPC (systemAccount 1) 10000000)
        badWallet<-rejects "unsupported_system_account" (prepareGas $ gasRPC (tokenAccount config recipient) 10000000)
        insufficient<-rejects "insufficient_operating_sol" (prepareGas $ gasRPC Null 1493440)
        belowRent<-rejects "gas_top_up_below_rent" (checkSolanaGasRecipient (gasRPC Null 10000000) (Just $ amt 1) Null)
        pure (fmap outcomeGasLamports(inspect success)==Right(amt 1000000)
          && fmap outcomeGasLamports(inspect existing)==Right(amt 1000000)
          && fmap outcomeGasLamports(inspect failure)==Right(amt 0)
          && all (isLeft.inspect) [missing,excessive,failedGift] && badWallet && insufficient && belowRent)
    , check "Solana expiry requires finalized absence on both anchored account histories and every provider" $ once $ ioProperty $ do
        let origin=T.replicate 64 "1"
            row sig failed=object ["signature" .= sig,"slot" .= (100::Int),"confirmationStatus" .= ("finalized"::Text),"err" .= (if failed then String "failed" else Null)]
            response value=object ["context" .= object ["slot" .= (200::Int)],"value" .= value]
            base profile method _=case method of
              "getGenesisHash"->pure $ toJSON (solanaGenesis profile)
              "getBlockHeight"->pure $ Number 1001
              "getSlot"->pure $ Number 200
              "isBlockhashValid"->pure $ response (Bool False)
              "getSignaturesForAddress"->pure $ toJSON [row origin False]
              "getTransaction"->pure Null
              "getSignatureStatuses"->pure $ response (toJSON [Null])
              _->fail "unexpected expiry RPC"
            primary=base W.L2LSignetDevnet
            prove a b profile=solanaExpiryEvidence a b profile config (origin,origin) boundSigned
            changed method value name args=if name==method then pure value else primary name args
        valid<-prove primary (Just primary) W.L2LSignetDevnet
        waiting<-prove (changed "getBlockHeight" (Number 1000)) Nothing W.L2LSignetDevnet
        absentVerifier<-rejects "independent_rpc_required" (prove (base W.CanonicalBeta) Nothing W.CanonicalBeta)
        signature<-maybe (fail "missing fixture signature") pure (replySignature $ signedSolanaReply boundSigned)
        failures<-mapM (\(method,value,code)->rejects code (prove primary (Just $ changed method value) W.L2LSignetDevnet))
          [("getGenesisHash",String "wrong","expiry_wrong_genesis"),
           ("getBlockHeight",Number 1000,"expiry_provider_behind"),
           ("getSlot",Number 99,"expiry_provider_behind"),
           ("isBlockhashValid",response $ Bool True,"blockhash_still_valid"),
           ("getSignaturesForAddress",toJSON ([]::[Value]),"solana_history_gap"),
           ("getSignaturesForAddress",toJSON [row signature True,row origin False],"expired_signature_in_history"),
           ("getTransaction",object [],"expired_transaction_observed"),
           ("getSignatureStatuses",response $ toJSON [object []],"expired_signature_observed")]
        pure (valid/=Nothing && waiting==Nothing && absentVerifier && and failures)
    , check "Solana uses confirmed blockhashes and retains the 40-block window through preparation" $ once $ ioProperty $ do
        let recentRPC height method args=case method of
              "getLatestBlockhash"->do
                require (args==[object ["commitment" .= ("confirmed"::Text)]]) "wrong_blockhash_commitment"
                pure $ context $ object ["blockhash" .= hash,"lastValidBlockHeight" .= (1000::Int)]
              "getBlockHeight"->do
                require (args==[object ["commitment" .= ("confirmed"::Text),"minContextSlot" .= (100::Int)]]) "wrong_blockhash_window_context"
                pure $ toJSON (height::Int)
              _->fail "unexpected blockhash RPC"
        recent<-getRecentBlockhash (recentRPC 960)
        tooShort<-rejects "solana_blockhash_window_too_short" (getRecentBlockhash $ recentRPC 961)
        height<-newIORef (960::Int)
        aged<-rejects "solana_blockhash_window_too_short" $ prepare plan $ \method args->
          if method=="getBlockHeight" then do
            current<-atomicModifyIORef' height (\n->(n+1,n))
            recentRPC current method args
          else call Null method args
        after<-readIORef height
        pure (recent==solPlanRecent plan && tooShort && aged && after==962)
    , check "sending keeps hard expiry and live hash validation after preparation headroom is spent" $ forAll (chooseInt (1,39)) $ \remaining->ioProperty $ do
        let sendRPC height valid slot method args=case method of
              "getBlockHeight"->pure $ toJSON (height::Int)
              "isBlockhashValid"->do
                require (args==[toJSON hash,object ["commitment" .= ("confirmed"::Text),"minContextSlot" .= (100::Int)]]) "wrong_send_hash_context"
                pure $ object ["context" .= object ["slot" .= (slot::Int)],"value" .= valid]
              _->fail "unexpected send validity RPC"
            recent=solPlanRecent plan
        checkBlockhashForSend (sendRPC (1000-remaining) True 100) recent
        expired<-rejects "solana_blockhash_expired" $ checkBlockhashForSend (sendRPC 1000 True 100) recent
        invalid<-rejects "solana_blockhash_expired" $ checkBlockhashForSend (sendRPC 999 False 100) recent
        stale<-rejects "solana_context_too_old" $ checkBlockhashForSend (sendRPC 999 True 99) recent
        pure (expired && invalid && stale)
    , check "unsigned Solana cancellation validates saved policy without RPC or a draft" $ once $ ioProperty $ do
        let noRPC _ _ _=fail "Solana cancellation reached native RPC"
        (points,cleanup)<-cancellationPlan noRPC W.L2LSignetDevnet config prepared
        (empty,undrafted)<-cancellationPlan noRPC W.L2LSignetDevnet config prepared {preparedDraft=Nothing}
        bad<-rejectsAny (cancellationPlan noRPC W.L2LSignetDevnet config prepared {preparedFee=amt 1})
        pure (null points && null empty && not(T.null cleanup) && cleanup/=undrafted && bad)
    , check "Solana admission simulates an unsigned payout and rejects signed previews" $ once $ ioProperty $ do
        let order=W.OrderRequest NativeToWrapped (amt 4) recipient "refund" Nothing "quote" Nothing
            quoteRequest=request {helperReference="quote-check"}
            memo=TE.encodeUtf8 $ helperMemo config quoteRequest
            original=either error id (B64.decode $ TE.encodeUtf8 $ replyMessage reply)
            body=BS.take (BS.length original-BS.length(TE.encodeUtf8 $ replyMemo reply)-1) original<>BS.singleton(fromIntegral $ BS.length memo)<>memo
            preview=reply {replyMemo=TE.decodeUtf8 memo,replyMessage=TE.decodeUtf8 $ B64.encode body,
              replyTransaction=TE.decodeUtf8 $ B64.encode $ BS.singleton 1<>BS.replicate 64 0<>body,replySignature=Nothing}
            helper wanted=require (wanted==quoteRequest) "unexpected_quote_request" >> pure preview
        calls<-newIORef ([]::[Text])
        let preflight method args=do
              modifyIORef' calls (<>[method])
              case method of
                "getLatestBlockhash"->pure $ context $ object ["blockhash" .= hash,"lastValidBlockHeight" .= (1000::Int)]
                "getMultipleAccounts"->pure $ context $ toJSON [systemAccount 1,Null,tokenAccount config owner,systemAccount 10000000]
                "simulateTransaction"->case args of
                  [String raw,_]->do
                    Transaction signatures _ _<-either reject pure (decodeTransaction raw)
                    require (signatures==[BS.replicate 64 0]) "signed_preview"
                    call Null method args
                  _->fail "unexpected simulation parameters"
                _->call Null method args
        checkSolanaQuoteWith preflight helper config order
        checkSolanaPayoutWith preflight helper config recipient (amt 3)
        signedPreview<-rejectsAny (checkSolanaQuoteWith preflight (const $ pure reply) config order)
        failedSimulation<-rejects "solana_simulation_failed" (checkSolanaQuoteWith
          (\method args->if method=="simulateTransaction" then pure $ context $ object ["err" .= String "failure"] else preflight method args) helper config order)
        methods<-readIORef calls
        pure (signedPreview && failedSimulation && "simulateTransaction" `elem` methods && "sendTransaction" `notElem` methods)
    , check "payment workflow verifies SDK bytes bound to earned funding and saved reference" $ once $ ioProperty $ do
        attempt<-verify prepared (SolanaReply boundSigned)
        verifySignedAttempt (\_ _ _->fail "unexpected RPC") W.L2LSignetDevnet config prepared attempt
        alteredEnvelope<-mapM (rejects "signer_attempt_mismatch" . verifySignedAttempt (\_ _ _->fail "unexpected RPC") W.L2LSignetDevnet config prepared)
          [attempt {signedId="other"},attempt {signedBytes="other"},attempt {commonInput=Just "other:0"}]
        wrongReference<-rejects "saved_solana_policy_mismatch" $ resolveSigningPlan W.L2LSignetDevnet config
          prepared {preparedPolicy=encoded boundPlan {solPlanReference="order-1"}}
        wrongFee<-rejects "invalid_saved_payment" $ verify prepared (SolanaReply boundSigned {signedSolanaFeeEstimate=amt 10001})
        wrongSignature<-rejectsAny $ verify prepared (SolanaReply boundSigned {signedSolanaReply=workflowReply {replyTransaction=replyTransaction reply}})
        pure (Just (signedId attempt)==replySignature workflowReply && signedBytes attempt==replyTransaction workflowReply
          && commonInput attempt==Nothing && and alteredEnvelope && wrongReference && wrongFee && wrongSignature)
    , check "Solana signed SDK vector binds identity message and signature" $ once $
        isRight (validateHelperReply config request reply) &&
        all (isLeft . validateHelperReply config request)
          [reply {replyProtocol=2},reply {replyMemo="wrong"},reply {replySignature=Nothing},
           reply {replySource=replyDestination reply},reply {replyMessage="AAAA"}] &&
        isLeft (validateUnsignedHelperReply config request reply)
    , check "Solana unsigned deposit vector remains signature-free" $ once $
        isRight (validateHelperReply config {custodyOwner=recipient,custodyAta=replyDestination unsignedReply}
          request {helperPayout=False} unsignedReply)
    , check "Solana signature corruption is rejected" $ forAll (chooseInt (1,64)) $ \index ->
        let bytes=either error id (B64.decode $ TE.encodeUtf8 $ replyTransaction reply)
            corrupted=BS.take index bytes<>BS.singleton (BS.index bytes index `xor` 1)<>BS.drop (index+1) bytes
        in isLeft (validateHelperReply config request reply {replyTransaction=TE.decodeUtf8 $ B64.encode corrupted})
    , check "Solana amount mutation cannot reuse signature" $ forAll (chooseInteger (4,1000000000)) $ \n ->
        isLeft (validateHelperReply config request {helperAmount=amt n} reply)
    , check "Solana packet and message bounds apply before base64 decoding" $ once $
        decodeTransaction (T.replicate 1645 "A")==Left "transaction_too_large" &&
        isLeft (validateHelperReply config request reply {replyMessage=T.replicate 1645 "A"})
    , check "Solana simulation preserves message but removes usable signature" $ once $ ioProperty $ do
        calls<-newIORef ([]::[Text])
        let rpcCall method args=do
              modifyIORef' calls (<>[method])
              case (method,args) of
                ("simulateTransaction",[String encoded,options])->do
                  Transaction signatures _ body<-either reject pure (decodeTransaction encoded)
                  sigVerify<-fieldValue "sigVerify" options
                  replaceHash<-fieldValue "replaceRecentBlockhash" options
                  require (signatures==[BS.replicate 64 0] && TE.decodeUtf8(B64.encode body)==replyMessage reply && not sigVerify && not replaceHash) "unsafe_simulation"
                _->pure ()
              call Null method args
        signed<-prepare plan rpcCall
        methods<-readIORef calls
        pure (signedSolanaFeeEstimate signed==amt 5000 && signedSolanaRentEstimate signed==amt 1488440 && "sendTransaction" `notElem` methods)
    , check "Solana rent counts only required top-up and never goes negative" $ forAll (chooseInteger (0,3000000)) $ \prefunded -> ioProperty $ do
        signed<-prepare plan (call $ systemAccount prefunded)
        pure (toInteger(units $ signedSolanaRentEstimate signed)==max 0 (1488440-prefunded))
    , check "existing recipient ATA needs no rent" $ once $ ioProperty $ do
        signed<-prepare plan (call $ tokenAccount config recipient)
        pure (signedSolanaRentEstimate signed==amt 0)
    , check "Solana preparation rejects stale context expired hash missing/excess fees and failed simulation" $ once $ ioProperty $ do
        let cases=[("getBlockHeight",Number 970,"solana_blockhash_window_too_short"),
              ("getFeeForMessage",context Null,"solana_fee_unavailable"),
              ("getFeeForMessage",context $ Number 10001,"solana_fee_above_limit"),
              ("getMultipleAccounts",object ["context" .= object ["slot" .= (99::Int)],"value" .= Null],"solana_context_too_old"),
              ("simulateTransaction",context $ object ["err" .= String "failure"],"solana_simulation_failed")]
        and <$> mapM (\(method,value,code)->rejects code $ prepare plan (\m args->if m==method then pure value else call Null m args)) cases
    , check "Solana operating rent and fee ceilings are mandatory" $ once $ ioProperty $ do
        fees<-rejects "solana_fee_above_limit" (prepare plan {solPlanFeeLimit=amt 1} $ call Null)
        rent<-rejects "solana_rent_above_limit" (prepare plan {solPlanRentLimit=amt 1} $ call Null)
        identity<-rejects "saved_solana_policy_mismatch" (prepare plan {solPlanFingerprint="wrong"} $ call Null)
        pure (fees && rent && identity)
    ]
  pure (proofResults<>local)
 where
  captured kind=do
    fixture<-readFixture ("solana-devnet-"<>kind<>"-payment.json")
    signed<-fieldValue "signed" fixture
    proof<-fieldValue "transaction" fixture
    outcome<-fieldValue "outcome" fixture
    let config=SolanaPolicy "l2l-devnet-local" "027929d80f528c8da4766560c2597c3971960bd47b4fc7c9f7648c0eba5996f8"
          "Hqb82J658UeWXCdr6DA6Au2ChMzrhxoSd3vdXk2hkNqM" "RWjpjjkpABkEGomLbZYyN53pA3FVdPXp9izJ25wErGX"
          "CKXz4AWgfRjw5YK17P64TgXuaci2QKAD7J1vZ9X2mNvT" (amt 10000) (amt 2100000)
        validate=verifySolanaOutcome config signed
        changed=[replace ["slot"] (Number 0) proof,replace ["meta","fee"] (Number 1) proof,
          replace ["transaction","signatures"] (toJSON ["wrong"::Text]) proof,
          replace ["meta","postTokenBalances"] (toJSON ([]::[Value])) proof,
          replace ["meta","err"] (String "failure") proof]
    meta<-fieldValue "meta" proof
    balances<-fieldValue "preBalances" meta :: IO [Integer]
    preTokens<-fieldValue "preTokenBalances" meta :: IO Value
    failedBalances<-case balances of first:rest->pure (first-toInteger(units $ outcomeFee outcome):rest); _->fail "empty fixture balances"
    let failure=replace ["meta","err"] (String "offline failure mutation")
          $ replace ["meta","postBalances"] (toJSON failedBalances)
          $ replace ["meta","postTokenBalances"] preTokens proof
        readOutcome evidence status method args=case (method,args) of
          ("getTransaction",[_,options])->do
            commitment<-fieldValue "commitment" options :: IO Text
            encoding<-fieldValue "encoding" options :: IO Text
            require (commitment=="finalized" && encoding=="json") "wrong_observation_commitment"
            pure evidence
          ("getSignatureStatuses",[_,options])->do
            history<-fieldValue "searchTransactionHistory" options
            require history "missing_historical_status_search"
            pure $ object ["context" .= object ["slot" .= recentSlot(solPlanRecent $ signedSolanaPlan signed)],"value" .= [status]]
          _->fail "unexpected observation RPC"
    check ("captured finalized Devnet "<>kind<>"-ATA payment and pending/failure observation contracts") $ once $ ioProperty $ do
      confirmed<-observeSolanaPayment (readOutcome proof Null) config signed
      unseen<-observeSolanaPayment (readOutcome Null Null) config signed
      waiting<-observeSolanaPayment (readOutcome Null $ object ["confirmationStatus" .= ("confirmed"::Text)]) config signed
      missing<-rejects "finalized_solana_evidence_unavailable" $ observeSolanaPayment
        (readOutcome Null $ object ["confirmationStatus" .= ("finalized"::Text)]) config signed
      failed<-observeSolanaPayment (readOutcome failure Null) config signed
      pure $ validate proof==Right outcome && all (isLeft . validate) changed
        && verifySolanaOutcome config {maxSolFee=amt 1,maxSolAccountRent=amt 0} signed proof==Right outcome
        && unseen==PaymentUnseen && waiting==PaymentWaiting && missing
        && (case confirmed of PaymentConfirmed costs evidence->costs==W.PaymentCosts (outcomeFee outcome) (outcomeRent outcome) && not(T.null evidence); _->False)
        && (case failed of PaymentFailed fee evidence->fee==outcomeFee outcome && not(T.null evidence); _->False)

readFixture :: FilePath -> IO Value
readFixture name=getDataFileName ("test/fixtures/"<>name) >>= BS.readFile >>= either fail pure . eitherDecodeStrict'
check :: Testable prop => String -> prop -> IO Result
check name p=putStrLn name >> quickCheckWithResult stdArgs {maxSuccess=100} p
amt :: Integer -> Amount
amt n=either (error . T.unpack) id (amount n)
isLeft :: Either a b -> Bool
isLeft (Left _)=True
isLeft _=False
isRight :: Either a b -> Bool
isRight=not . isLeft
rejects :: Text -> IO a -> IO Bool
rejects code action=do
  result<-try action
  pure $ case result of Left(BridgeError actual)->actual==code; Right _->False
context :: Value -> Value
context value=object ["context" .= object ["slot" .= (100::Int)],"value" .= value]
systemAccount :: Integer -> Value
systemAccount n=object ["owner" .= ("11111111111111111111111111111111"::Text),"executable" .= False,"data" .= ["","base64"::Text],"lamports" .= (n::Integer)]

-- Public deterministic fixture key, used only to sign SDK-created offline bytes.
signedGasReply :: SolanaPolicy -> HelperRequest -> IO HelperReply
signedGasReply config request = do
  reply<-invokeUnsignedHelper sdkLibraryPath config request
  Transaction _ _ message<-either reject pure (validateUnsignedHelperReply config request reply)
  secret<-case Ed.secretKey (BS.replicate 32 1) of CryptoPassed key->pure key; CryptoFailed _->fail "invalid fixture key"
  let public=Ed.toPublic secret
      signature=convert(Ed.sign secret public message) :: BS.ByteString
  require (base58(convert public)==helperOwner request) "fixture_owner_mismatch"
  pure reply {replySignature=Just $ base58 signature
    ,replyTransaction=TE.decodeUtf8 $ B64.encode $ BS.singleton 1<>signature<>message}

-- Synthetic metadata for an exact SDK message. Separate balance mutations test
-- the verifier; this is not a claim that the transaction reached a network.
gasProof :: SolanaPolicy -> SolanaSigned -> Bool -> Integer -> Integer -> IO Value
gasProof config signed success rent gas = do
  let plan=signedSolanaPlan signed; reply=signedSolanaReply signed
  Transaction _ (Message required signedReadonly readonly keys hash instructions) _<-
    either reject pure (validateHelperReply config (solanaPayoutRequest config plan) reply)
  let address=map base58 keys
      index key=maybe (fail "missing fixture account") pure (elemIndex key address)
  source<-index(replySource reply)
  destination<-index(replyDestination reply)
  recipient<-index(solPlanRecipient plan)
  let before=[if i==0 then 10000000 else if i==destination && rent==0 then 1488440 else 0 | i<-[0..length keys-1]]
      after=[n+(if i==0 then negate(5000+rent+gas) else if i==destination then rent else if i==recipient then gas else 0)
        | (i,n)<-zip [0..] before]
      tokens i owner n=object ["accountIndex" .= i,"mint" .= mint config,"owner" .= owner
        ,"uiTokenAmount" .= object ["decimals" .= (8::Int),"amount" .= T.pack(show (n::Integer))]]
      pre=[tokens source (custodyOwner config) 100]<>[tokens destination (solPlanRecipient plan) 100 | rent==0]
      post=if success then [tokens source (custodyOwner config) 97,tokens destination (solPlanRecipient plan) (if rent==0 then 103 else 3)] else pre
  pure $ object ["slot" .= recentSlot(solPlanRecent plan),"version" .= ("legacy"::Text)
    ,"transaction" .= object ["signatures" .= maybe [] pure (replySignature reply),"message" .= object
      ["accountKeys" .= address,"header" .= object ["numRequiredSignatures" .= required
        ,"numReadonlySignedAccounts" .= signedReadonly,"numReadonlyUnsignedAccounts" .= readonly]
      ,"recentBlockhash" .= base58 hash,"instructions" .= [object ["programIdIndex" .= program,"accounts" .= accounts,"data" .= base58 bytes]
        | Instruction program accounts bytes<-instructions]]]
    ,"meta" .= object ["err" .= (if success then Null else String "offline failure"),"fee" .= (5000::Integer)
      ,"preBalances" .= before,"postBalances" .= after,"preTokenBalances" .= pre,"postTokenBalances" .= post]]
tokenAccount :: SolanaPolicy -> Text -> Value
tokenAccount c owner=object ["owner" .= tokenProgram,"executable" .= False,"data" .= object
  ["space" .= (165::Int),"parsed" .= object ["type" .= ("account"::Text),"info" .= object
    ["mint" .= mint c,"owner" .= owner,"state" .= ("initialized"::Text),"isNative" .= False,
     "tokenAmount" .= object ["amount" .= ("100000000000"::Text),"decimals" .= (8::Int)]]]]]
replace :: [Key] -> Value -> Value -> Value
replace [] replacement _=replacement
replace (key:rest) replacement (Object fields)=Object $ KM.insert key (replace rest replacement $ maybe Null id $ KM.lookup key fields) fields
replace _ _ value=value

rejectsAny :: IO a -> IO Bool
rejectsAny action = do
  result <- try (action >> pure ())
  pure $ case result of Left (BridgeError _)->True; Right _->False
