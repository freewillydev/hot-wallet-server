{-# LANGUAGE DataKinds, GADTs, TypeOperators, TypeFamilies, TypeApplications #-}
{-# LANGUAGE ScopedTypeVariables #-}
module Main (main) where

import qualified RestoreGuideCheck
import qualified ConfigureCheck
import qualified Configure
import qualified SigningTransportCheck
import qualified ChainCheck
import qualified LifecycleCheck
import Bridge.Identity (bearerHash,capabilityHash,payInstruction,payURIFor)
import Bridge.API (customerServer)
import Bridge.Signer (signingServer)
import Bridge.Operation.Internal
import Bridge.Critical (operationPath,payoutOperation)
import qualified Bridge.Wire as W
import Servant.API ((:<|>)(..))
import Bridge.Domain
import Data.Aeson (eitherDecode,encode)
import Data.Int (Int64)
import qualified Data.ByteString.Lazy.Char8 as BL
import Data.List (nub)
import Data.Typeable (typeRep,eqT)
import Control.Operation
import Control.Operation.Flow (Values(..),runFlow)
import Control.Exception (SomeException,AsyncException(ThreadKilled),try,throwIO,fromException)
import Control.Monad (forM,when,unless)
import Data.IORef (newIORef,modifyIORef',readIORef)
import Data.Proxy (Proxy(..))
import Data.Type.Equality ((:~:)(Refl))
import qualified Data.Map.Strict as M
import qualified Data.Text as T
import System.Exit (exitFailure)
import System.Environment (getArgs)
import Test.QuickCheck hiding (total,Result)

main :: IO ()
main = getArgs >>= \args -> case args of
  ["--start-setup",directory]->Configure.startSetup directory
  ["--payout-safety-only"]->checked "Payout safety regressions passed" (all isSuccess <$> LifecycleCheck.payoutSafetyChecks)
  ["--configure-only"]->checked "Configure contract passed" ConfigureCheck.contract
  ["--funding-only"]->checked "Funding contract passed" SigningTransportCheck.fundingCheck
  ["--restore-root-only"]->checked "Privileged restore staging contract passed" RestoreGuideCheck.rootContract
  ["--restore-only"]->checked "Restore journal contract passed" RestoreGuideCheck.contract
  _->fullSuite
 where
  checked label action=action >>= \ok->if ok then putStrLn label else exitFailure

fullSuite :: IO ()
fullSuite = do
  results <- sequence
    [ check "Recovery step journals refuse uncertain replay" $ once $ ioProperty RestoreGuideCheck.contract
    , check "BIP39 generation and Solana wallet recovery" ConfigureCheck.walletProperty
    , check "configure saves private validated material and refuses overwrite/interruption" $ once $ ioProperty ConfigureCheck.contract
    , check "Solana Pay URI preserves exact units and rejects injectable keys" $ forAll amounts $ \n ->
        let key=T.replicate 32 "1"; quantity=good(amount n); instruction="solana-pay:"<>key
        in payURIFor key key instruction quantity==Right("solana:"<>key<>"?amount="<>renderCoins quantity<>"&spl-token="<>key<>"&reference="<>key<>"&label=ECX%20Bridge")
          && isLeft(payURIFor (key<>"?evil") key instruction quantity)
          && isLeft(payURIFor key key "invalid" quantity)
    , check "Solana Pay reference retains the baseline order binding" $ once $ property $
        and [payInstruction (T.replicate 64 "0")==Right ("solana-pay:"<>T.replicate 32 "1"),isLeft(payInstruction "bad")]
    , check "capabilities retain baseline hashing and reject malformed headers" $ once $ property $
        and [capabilityHash (T.replicate 64 "0")==Right "c7de6a9548a8cbddf66a91b07bedaa2949ebe64ce649be6d584f7ba7122b4c04"
            ,bearerHash ("Bearer "<>T.replicate 64 "0")==capabilityHash (T.replicate 64 "0")
            ,all (isLeft . bearerHash) ["", "bearer "<>T.replicate 64 "0", "Bearer "<>T.replicate 64 "A", "Bearer "<>T.replicate 64 "0"<>" "]]
    , check "customer handlers preserve request, result type and severity" $ once $ property handlerContract
    , check "payout flow preserves new/resumed/family paths and stops after failure or cancellation" $ once $ ioProperty payoutFlowContract
    , check "signer handler resolves an existential to a signer-only critical operation" $ once $ property $
        let prepared :<|> replacement :<|> draft :<|> checkpoint=signingServer ()
        in case (checkedOperation $ prepared ("deployment","payment",3),checkedOperation $ replacement ("deployment",7),checkedOperation $ draft ("deployment","parent",good $ amount 2),checkedOperation $ checkpoint ("deployment",9)) of
          (Right(SigningDSL (PreparedSigning (SignPrepared identity identifier generation))),Right(SigningDSL (ReplacementSigning (SignReplacement other decision))),Right(SigningDSL (DraftSigning (DraftReplacement third parent fee))),Right(SigningDSL (CheckpointSigning (CheckpointCustody fourth sequenceNo))))->
            identity=="deployment" && identifier=="payment" && generation==3 && other==identity && decision==7 && third==identity && parent=="parent" && units fee==2 && fourth==identity && sequenceNo==9
          _->False
    , check "signer trace labels match the formal path/result relation" $ once $ property $
        let prepared :<|> replacement :<|> draft :<|> checkpoint=signingServer ()
            label :: SomeOperationAt Program caller severity a -> Maybe (T.Text,T.Text,T.Text)
            label request=either (const Nothing) operationPath (checkedOperation request)
        in [label (prepared ("deployment","payment",3)),label (replacement ("deployment",7))
           ,label (draft ("deployment","parent",good $ amount 2)),label (checkpoint ("deployment",9))]
           ==map Just [("sign-preparation","SignPrepared","PreparedResult")
                      ,("sign-replacement","SignReplacement","ReplacementResult")
                      ,("draft-replacement","DraftReplacement","DraftResult")
                      ,("checkpoint-custody","CheckpointCustody","CheckpointResult")]
    , check "library context identity preserves caller and severity through existential preparation" $ once $ property $
        let identities=[typeRep(Proxy @(Context (CustomerCommand 'Safe ())))
              ,typeRep(Proxy @(Context (CustomerCommand 'Critical ())))
              ,typeRep(Proxy @(Context (OperatorCommand 'Safe ())))
              ,typeRep(Proxy @(Context (OperatorCommand 'Critical ())))
              ,typeRep(Proxy @(Context (WorkerCommand 'Critical ())))
              ,typeRep(Proxy @(Context (SignerCommand 'Critical ())))]
            select :: SomeOperationAt Program caller severity a -> T.Text
            select request=case checkedOperation request of
              Left _->"mismatch"
              Right operation->case operation of
                ReadCustomer{}->"customer-read"
                ReadOperator{}->"operator-read"
                WriteCustomer{}->"customer-write"
                OperatorDSL{}->"operator-write"
                WorkerDSL{}->"worker"
                SigningDSL{}->"signer"
        in length(nub identities)==6 && and
          [select(pending $ CustomerQuery PublicConfig)=="customer-read"
          ,select(pending $ OperatorQuery ServiceState)=="operator-read"
          ,select(pending $ CustomerChange $ CreateOrder "auth" $ W.OrderRequest NativeToWrapped (good $ amount 100) "dest" "refund" Nothing "key")=="customer-write"
          ,select(pending $ OperatorChange $ \cap -> pauseService cap "reason")=="operator-write"
          ,select(workerRequest runWorkerCycle)=="worker"
          ,select(pending $ SignerAction $ PreparedSigning $ SignPrepared "deployment" "payment" 3)=="signer"]
    , check "distinct dictionary constraints and signer outputs have no equality witness" $ once $ property $
        absent(eqT @(Context (CustomerCommand 'Safe ())) @(Context (CustomerCommand 'Critical ())))
        && absent(eqT @(Context (WorkerCommand 'Critical ())) @(Context (SignerCommand 'Critical ())))
        && absent(eqT @PreparedResult @ReplacementResult) && absent(eqT @PreparedResult @DraftResult)
        && absent(eqT @PreparedResult @CheckpointResult) && absent(eqT @ReplacementResult @DraftResult)
        && absent(eqT @ReplacementResult @CheckpointResult) && absent(eqT @DraftResult @CheckpointResult)
    , check "library existential dispatch preserves payload and rejects a different caller" $ once $ property $
        let selector = Compile :: DSL (CustomerCommand 'Safe W.PublicConfiguration)
            mismatch = interpret (SomeOperation (WorkerAction runWorkerCycle)) selector
        in case (checkedOperation (pending $ CustomerQuery PublicConfig), mismatch) of
          (Right (ReadCustomer PublicConfig), Nothing) -> True
          _ -> False
    , check "existential interpreter rejects changed severity and signer result" $ once $ property $
        let order=W.OrderRequest NativeToWrapped (good $ amount 100) "dest" "refund" Nothing "key"
            wrongSeverity=interpret (SomeOperation (CustomerChange $ CreateOrder "auth" order))
              (Compile :: DSL (CustomerCommand 'Safe W.OrderView))
            wrongResult=interpret (SomeOperation (SignerAction $ PreparedSigning $ SignPrepared "deployment" "payment" 3))
              (Compile :: DSL (SignerCommand 'Critical ReplacementResult))
        in case (wrongSeverity,wrongResult) of (Nothing,Nothing)->True; _->False
    , check "payload mismatch is rejected before inspecting command branches" $ once $ property $
        let mismatch=interpret (SomeOperation (error "mismatched command forced" :: WorkerCommand 'Critical ()))
              (Compile :: DSL (CustomerCommand 'Safe W.PublicConfiguration))
        in case mismatch of Nothing->True; Just _->False
    , check "result equality determines both severity and operation" $ once $ property $
        case resultIndices (Refl :: Result 'Critical SignPrepared :~: Result 'Critical SignPrepared) of
          (Refl,Refl)->True
    , check "typed signer result preserves all evidence through JSON" $ once $ property $
        let result=W.SignedAttempt "id" "bytes" "proof" (Just "outpoint")
        in eitherDecode (encode result)==Right result
    , check "serialized quotes cannot change saved accounting" $ forAll (chooseInteger (2,1000000000)) $ \n ->
        let q=good (quote $ good $ amount n)
        in conjoin [eitherDecode (encode q)===Right q,
          property (isLeft (eitherDecode "{\"gross\":\"100\",\"fee\":\"1\",\"net\":\"100\"}" :: Either String Quote))]
    , check "exact amount wire/decimal round trips" $ forAll amounts $ \n ->
        let a=good (amount n)
        in conjoin [parseUnits (T.pack $ show n)===Right a,parseCoins (renderCoins a)===Right a,
                    eitherDecode (encode a)===Right a]
    , check "wire amounts and integer policy reject hostile exponent notation promptly" $ within 1000000 $ once $ property $
        all (\raw ->
          let text=T.pack raw
              order input="{\"direction\":\"NativeToWrapped\",\"input\":"<>input<>
                ",\"recipient\":\"dest\",\"refund\":\"refund\",\"sourceOwner\":null,\"idempotencyKey\":\"key\"}"
              rejected bytes=isLeft (eitherDecode bytes :: Either String W.OrderRequest)
          in not(rejected $ order "\"100\"") && isLeft(parseUnits text) && isLeft(parseCoins text)
            && rejected(order $ BL.pack raw) && rejected(order $ encode text)
            && isLeft(eitherDecode ("{\"nativeDepth\":"<>BL.pack raw<>
              ",\"solanaCommitment\":\"finalized\",\"deploymentFingerprint\":\"id\"}") :: Either String W.PolicySnapshot))
          ["1e1000000000","1e-1000000000","1e9223372036854775807","1e-9223372036854775808"]
    , check "new fee rounds upward without overflow" $ forAll (chooseInteger (2,toInteger(maxBound::Int64))) $ \n ->
        let q=good (quote $ good $ amount n); f=toInteger (units $ fee q)
        in conjoin [f*100>=n,(f-1)*100<n,toInteger(units(net q))+f==n]
    , check "conversion/refund settlement balances each asset" $ forAll (chooseInteger (2,1000000000000)) $ \n ->
        forAll (elements [NativeToWrapped,WrappedToNative]) $ \direction ->
          let q=good (quote $ good $ amount n)
              c=good (conversion "order" "receipt" direction q)
              r=good (refund "order" "receipt" (sourceAsset direction) (gross q))
              make funding=good (payment "payment" funding "recipient")
              cp=make c; rp=make r
          in conjoin
            [balanced (settlement cp),balanced (settlement rp)
            ,paymentAmount cp==net q,paymentAmount rp==gross q
            ,paymentAsset cp==destinationAsset direction
            ,delta (sourceAsset direction) Principal (settlement cp)==negate n
            ,delta (sourceAsset direction) Earned (settlement rp)==0
            ,isLeft (reserveEarned c),isLeft (reserveEarned r)]
    , check "earned funds never consume customer principal or inventory" $ forAll (chooseInteger (1,1000000000000)) $ \n ->
        forAll (elements [Native,Wrapped]) $ \asset ->
          let f=good (earnedFees "withdrawal" asset (good $ amount n))
              reserve=good (reserveEarned f); release=good (releaseEarned f)
              paid=settlement (good $ payment "payment" f "recipient")
              total=reserve<>paid
          in conjoin
            [balanced reserve,balanced release,balanced paid
            ,all (==0) (M.elems $ totals $ reserve<>release)
            ,delta asset Earned total==negate n,delta asset External total==n
            ,delta asset FeePending total==0
            ,all (\p->postingAccount p `notElem` [Principal,Float,Backing,Liquidity]) total]
    , check "historical quotes retain their saved charge" $ forAll (chooseInteger (2,1000000000)) $ \n ->
        forAll (chooseInteger (0,n-1)) $ \saved ->
          let q=good (historicalQuote (good $ amount n) (good $ amount saved))
              p=good (conversion "order" "receipt" NativeToWrapped q >>= \f->payment "payment" f "recipient")
          in conjoin [toInteger(units(paymentAmount p))==n-saved,
                      delta Native Earned (settlement p)==saved]
    , check "invalid monetary forms and unsupported payouts are refused" $ once $ property $
        and [all (isLeft . parseUnits) ["", "01", "-1", "+1", "1e8", "1.0", "１２", "9223372036854775808"]
            ,isLeft (amount (-1)),isLeft (amount (toInteger(maxBound::Int64)+1))
            ,isLeft (quote $ good $ amount 0),isLeft (quote $ good $ amount 1)
            ,isLeft (historicalQuote (good $ amount 10) (good $ amount 11))
            ,isLeft (earnedFees "withdrawal" Sol (good $ amount 1))
            ,isLeft (refund "order" "receipt" Native (good $ amount 0))]
    ]
  chainResults <- ChainCheck.checks
  transportResults <- SigningTransportCheck.checks
  lifecycleResults <- LifecycleCheck.checks
  if all isSuccess (results<>chainResults<>transportResults<>lifecycleResults) then pure () else exitFailure
 where
  check description p=putStrLn description >> quickCheckWithResult stdArgs{maxSuccess=300} p
  amounts=chooseInteger (0,toInteger(maxBound::Int64))

good :: Show e => Either e a -> a
good = either (error . show) id
isLeft :: Either a b -> Bool
isLeft (Left _)=True
isLeft (Right _)=False
totals :: [Posting] -> M.Map (Asset,Account) Integer
totals = M.fromListWith (+) . map (\p->((postingAsset p,postingAccount p),postingDelta p))
delta :: Asset -> Account -> [Posting] -> Integer
delta asset account = M.findWithDefault 0 (asset,account) . totals
balanced :: [Posting] -> Bool
balanced = all (==0) . M.elems . M.fromListWith (+) . map (\p->(postingAsset p,postingDelta p))

-- Inspect the real Servant handlers; no mock chain or evaluator is involved.
handlerContract :: Bool
handlerContract =
  let config :<|> create :<|> status :<|> instructions = customerServer
      inputRequest = W.OrderRequest NativeToWrapped (good $ amount 100) "destination" "refund" Nothing "key"
      configOK = case config of
        SafePlan req -> case checkedOperation req of Right(ReadCustomer PublicConfig) -> True; _ -> False
        _ -> False
      createOK = case create "auth" inputRequest of
        CriticalPlan req -> case checkedOperation req of
          Right(WriteCustomer (CreateOrder auth saved)) -> auth=="auth" && saved==inputRequest
          _ -> False
        _ -> False
      statusOK = case status "order" "auth" of
        SafePlan req -> case checkedOperation req of
          Right(ReadCustomer (OrderStatus auth oid)) -> auth=="auth" && oid=="order"
          _ -> False
        _ -> False
      instructionsOK = case instructions "order" "auth" of
        SafePlan req -> case checkedOperation req of
          Right(ReadCustomer (PaymentInstructions auth oid)) -> auth=="auth" && oid=="order"
          _ -> False
        _ -> False
  in and [configOK,createOK,statusOK,instructionsOK]

-- GHC must derive both equalities from family-result equality, without casts.
resultIndices :: Result s op :~: Result t other -> (s :~: t, op :~: other)
resultIndices Refl = (Refl,Refl)

absent :: Maybe a -> Bool
absent Nothing=True
absent Just{}=False

-- Trace the actual closed Flow grammar, including actual identifier threading.
-- This is an unfunded control-flow oracle; PostgreSQL/HTTPS contracts separately
-- exercise existing durable operation and service boundaries.
payoutFlowContract :: IO Bool
payoutFlowContract = do
  let request = WorkerAction runWorkerCycle :: WorkerCommand 'Critical ()
  unless (case interpret (SomeOperation request) (CompilePayoutWorkflow :: DSL (PayoutWorkflow (WorkerCommand 'Critical ()))) of
    Nothing -> True; Just _ -> False) $ fail "payout workflow accepted a different payload"
  workflow <- maybe (fail "payout workflow did not compile") pure (payoutFlow request)
  and <$> forM [[],["saved"],["parent","replacement"]] (\attempts -> do
    let txid = case attempts of [] -> "new"; [saved] -> saved; _ -> "family-tip"
        prefix = ["inspect:payment"] <> case attempts of
          [] -> ["prepare:payment","backup:preparation","sign:payment"]
          [_] -> ["reuse:"<>txid]
          _ -> ["family:payment"]
        expected = prefix <> ["queue:"<>txid,"backup:intent","send:"<>txid]
    and <$> forM [(fault,asynchronous) | fault<-[0..length expected], asynchronous<-[False,True]] (\(fault,asynchronous) -> do
      trace <- newIORef []
      let record event = do
            modifyIORef' trace (<>[event])
            count <- length <$> readIORef trace
            when (fault==count) $ if asynchronous then throwIO ThreadKilled else throwIO (userError "outcome unknown")
          traceStep :: PayoutStep (WorkerCommand 'Critical ()) before after a -> Values before -> IO (a,Values after)
          traceStep wrapped@(PayoutStep step) values = do
            case checkedOperation (payoutOperation wrapped values) of
              Right WorkerDSL{} -> pure ()
              _ -> fail "payout did not compile to a deferred worker action"
            traceInstruction step values
          traceInstruction :: PayoutInstruction before after a -> Values before -> IO (a,Values after)
          traceInstruction step values = case (step,values) of
            (InspectPayout,identifier :& VNil) -> record ("inspect:"<>identifier) >> pure (attempts,values)
            (PreparePayout,identifier :& VNil) -> do
              record ("prepare:"<>identifier)
              record "backup:preparation"
              pure ((),PreparedPayout identifier :& VNil)
            (SignPayout,PreparedPayout identifier :& VNil) -> do
              record ("sign:"<>identifier)
              pure ((),SignedPayout "new" :& VNil)
            (ReusePayout saved,identifier :& VNil) -> do
              actual <- case saved of
                [one] -> record ("reuse:"<>one) >> pure one
                _ -> record ("family:"<>identifier) >> pure "family-tip"
              pure ((),SignedPayout actual :& VNil)
            (QueuePayout,SignedPayout signed :& VNil) -> do
              record ("queue:"<>signed)
              record "backup:intent"
              pure ((),QueuedPayout signed :& VNil)
            (SendPayout,QueuedPayout queued :& VNil) -> record ("send:"<>queued) >> pure ((),VNil)
      result <- try (runFlow traceStep workflow ("payment" :& VNil))
        :: IO (Either SomeException ((),Values '[]))
      actual <- readIORef trace
      pure $ actual==take (if fault==0 then length expected else fault) expected && case result of
        Right ((),VNil) -> fault==0
        Left failure -> fault/=0 && if asynchronous then fromException failure==Just ThreadKilled
          else (fromException failure :: Maybe AsyncException)==Nothing))
