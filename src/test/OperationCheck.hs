{-# LANGUAGE DataKinds, GADTs, TypeFamilies, FlexibleInstances, MultiParamTypeClasses #-}
{-# LANGUAGE ScopedTypeVariables, TypeApplications, TypeOperators, QualifiedDo #-}
{-# OPTIONS_GHC -Werror=incomplete-patterns -Werror=missing-methods #-}
module Main (main) where

import Bridge.Domain (amount,units)
import Bridge.Operation.Internal
import Control.Exception (SomeException,AsyncException(ThreadKilled),try,throwIO,fromException)
import Control.Monad (forM,unless,when)
import Control.Operation (Operation(..),SomeOperation(..))
import Control.Operation.Flow (Flow,Values(..),runFlow)
import qualified Control.Operation.Flow as F
import Data.IORef (newIORef,modifyIORef',readIORef)
import Data.Int (Int64)
import Data.Proxy (Proxy(..))
import Data.Text (Text)
import qualified Data.Text as T
import System.Exit (exitFailure)
import Test.QuickCheck hiding (Result)

-- This component links only the core grammar. Its effects are pure trace data;
-- neither a production evaluator nor keys, database or RPC are available.
data Settings = Settings
  { saved :: Bool, enabled :: Bool, candidates :: [Text], attempts :: [Text]
  , unseen :: Bool, feeCandidates :: [Text], feesEnabled :: Bool }
defaults :: Settings
defaults = Settings False True [] [] True [] True

data instance Effect 'Operator before after a = OperatorEvent
  (Settings -> Values before -> (Text,a,Values after))
data instance Effect 'Worker before after a = WorkerEvent
  (Settings -> Values before -> (Text,a,Values after))

class Trace caller where
  traceEffect :: Effect caller before after a -> Settings -> Values before -> (Text,a,Values after)
instance Trace 'Operator where traceEffect (OperatorEvent transition) = transition
instance Trace 'Worker where traceEffect (WorkerEvent transition) = transition

op :: Text -> (Settings -> a) -> Flow (RequestStep 'Operator) state state a
op label result = F.step $ Leaf $ OperatorEvent $ \settings values -> (label,result settings,values)
work :: Text -> (Settings -> a) -> Flow (RequestStep 'Worker) state state a
work label result = F.step $ Leaf $ WorkerEvent $ \settings values -> (label,result settings,values)
workerStep :: (Settings -> Values before -> (Text,a,Values after)) -> Flow (RequestStep 'Worker) before after a
workerStep = F.step . Leaf . WorkerEvent

instance Execution 'Operator 'Critical OperatorCommand where
  authorizeOperation _ _ = fail "trace compiler invoked authorization"
  evaluateOperation _ _ = fail "trace compiler invoked evaluation"
instance Execution 'Worker 'Critical WorkerCommand where
  authorizeOperation _ _ = fail "trace compiler invoked authorization"
  evaluateOperation _ _ = fail "trace compiler invoked evaluation"
instance Execution 'Worker 'Safe WorkerCommand where
  authorizeOperation _ _ = fail "trace compiler invoked authorization"
  evaluateOperation _ _ = fail "trace compiler invoked evaluation"

data instance ResumeWork (OperatorCommand 'Critical result) = ResumeWork
data instance ResumeDraft (OperatorCommand 'Critical result) = ResumeDraft
data instance RebroadcastWork (OperatorCommand 'Critical result) = RebroadcastWork Text
data instance ReplacementDraftWork (OperatorCommand 'Critical result) = ReplacementDraftWork Text
data instance ReplacementSigningWork (OperatorCommand 'Critical result) = ReplacementSigningWork Int64
data instance RetryWork (OperatorCommand 'Critical result) = RetryWork Text Text
data instance CancellationWork (OperatorCommand 'Critical result) = CancellationWork Text Int Text
data instance CancellationCommit (OperatorCommand 'Critical result) = CancellationCommit Text
data instance SigningWork (WorkerCommand 'Critical result) = SigningWork Text
data instance BroadcastWork (WorkerCommand 'Critical result) = BroadcastWork Text
data instance OwnerFeeWork (WorkerCommand 'Critical result) = OwnerFeeWork Text

instance OperatorService (OperatorCommand 'Critical result) where
  pauseService _ reason = op ("pause:"<>reason) (const ())
  resumeService = F.step . Expand . ResumeWorkflow
instance OperatorRepair (OperatorCommand 'Critical result) where
  repairCompletedOrder _ identifier = op ("repair:"<>identifier) (const ())
  retrySolanaPayment value txid reason = F.step $ Expand $ RetryWorkflow value txid reason
  cancelPreparation value identifier generation reason = F.step $ Expand $ CancellationWorkflow value identifier generation reason
  refundDeposit _ _ = error "unselected refund capability"
instance OperatorNative (OperatorCommand 'Critical result) where
  rebroadcastNative value txid anchor reason = F.step $ Expand $ RebroadcastWorkflow value txid anchor reason
  draftNativeReplacement value parent fee reason = F.step $ Expand $ ReplacementDraftWorkflow value parent fee reason
  signNativeReplacement value decision = F.step $ Expand $ ReplacementSigningWorkflow value decision
  cancelNativeReplacement _ _ _ = error "unselected native cancellation capability"
instance OperatorSource (OperatorCommand 'Critical result) where
  coverLostSource _ _ _ _ _ _ = error "unselected source capability"
  approveCovered _ _ _ _ = error "unselected source capability"
  restoreSource _ _ _ _ = error "unselected source capability"
instance OperatorTreasury (OperatorCommand 'Critical result) where
  classifySpend _ _ _ _ = error "unselected treasury capability"
  initializeOperating _ _ _ _ = error "unselected treasury capability"
  allocateReceipt _ _ _ _ = error "unselected treasury capability"
  withdrawFees _ _ _ _ _ _ = error "unselected treasury capability"
  cancelFeeWithdrawal _ _ _ = error "unselected treasury capability"

instance CustodySteps (OperatorCommand 'Critical result) where
  custodyScope _ = F.step . Scoped OperatorGuard
  checkpointCustody _ = op "backup" (const ())
  observeCustody _ = op "observe" (const ())
  reconcileCustodyStep _ = op "reconcile" (const ())
instance ResumeSteps (OperatorCommand 'Critical result) where
  checkResume _ = op "check" (const ())
  recoverResume _ = op "recover" (const ())
  inspectResume _ = op "inspect" (const ResumeWork)
  refreshResume _ ResumeWork = op "refresh" (const ())
  inspectResumeDraft _ = op "draft" (\s -> if saved s then Just ResumeDraft else Nothing)
  restoreResumeDraft _ ResumeDraft = op "restore" (const ())
  finishResume _ ResumeWork draft = op (case draft of Nothing -> "finish:no-draft"; Just ResumeDraft -> "finish:draft") (const ())
instance NativeSteps (OperatorCommand 'Critical result) where
  inspectRebroadcast _ txid anchor reason = op ("inspect:"<>txid<>":"<>T.pack(show anchor)<>":"<>reason) (const $ RebroadcastWork txid)
  sendRebroadcast _ (RebroadcastWork txid) = op "send-saved" (const txid)
  inspectReplacementDraft _ parent fee reason = op ("draft:"<>parent<>":"<>T.pack(show $ units fee)<>":"<>reason)
    (\s -> if saved s then Left 7 else Right $ ReplacementDraftWork parent)
  refreshReplacementDraft _ (ReplacementDraftWork parent) = op ("refresh:"<>parent) (const ())
  issueReplacementDraft _ (ReplacementDraftWork _) = op "draft-sign" (const 8)
  inspectReplacementSigning _ decision = op ("replacement:"<>T.pack(show decision))
    (\s -> if saved s then Left "saved" else Right $ ReplacementSigningWork decision)
  refreshReplacementSigning _ (ReplacementSigningWork decision) = op ("refresh:"<>T.pack(show decision)) (const ())
  issueReplacementSigning _ (ReplacementSigningWork _) = op "replacement-sign" (const "new")
instance RetrySteps (OperatorCommand 'Critical result) where
  inspectRetry _ txid reason = op ("retry:"<>txid<>":"<>reason)
    (\s -> if saved s then Nothing else Just $ RetryWork txid reason)
  refreshRetrySource _ (RetryWork txid _) = op ("refresh:"<>txid) (const ())
  proveRetryExpired _ (RetryWork txid _) = op "expiry" (const $ "proof:"<>txid)
  commitRetryApproval _ (RetryWork _ reason) proof = op ("approve:"<>reason<>":"<>proof) (const ())
instance CancellationSteps (OperatorCommand 'Critical result) where
  inspectCancellation _ identifier generation reason = op ("cancel:"<>identifier)
    (\s -> if saved s then Nothing else Just $ CancellationWork identifier generation reason)
  refreshCancellationSource _ (CancellationWork identifier _ _) = op ("refresh:"<>identifier) (const ())
  beginCancellation _ (CancellationWork identifier generation reason) = F.do
    op "reread-and-validate" (const ())
    op ("begin:"<>T.pack(show generation)<>":"<>reason) (const $ CancellationCommit identifier)
  releaseCancellation _ (CancellationCommit identifier) = op ("release:"<>identifier) (const ())
  finishCancellation _ (CancellationCommit identifier) = op ("finish:"<>identifier) (const ())

instance WorkerBackup (WorkerCommand 'Critical result) where
  checkpointBackup _ _ = work "explicit-backup" (const ())
  checkpointForUpgrade _ = error "unselected upgrade capability"
  checkpointPending _ = workerStep $ \_ (value :& VNil) -> ("backup",(),BackupCovered value :& VNil)
instance WorkerObservation (WorkerCommand 'Critical result) where
  observeChains _ = work "observe" (const ())
  reconcileCustody _ = work "reconcile" (const ())
  inspectPayout _ identifier = workerStep $ \s VNil -> ("inspect:"<>identifier,attempts s,identifier :& VNil)
instance WorkerRecovery (WorkerCommand 'Critical result) where
  recoverNativeSettlements _ = work "recover-settlements" (const ())
  recoverNativeSources _ = work "recover-sources" (const ())
  recoverNativeLocks _ = work "recover-locks" (const ())
  reconcilePayment _ identifier = work ("reconcile:"<>identifier) (const ())
  reusePayout _ previous = workerStep $ \_ (identifier :& VNil) -> case previous of
    [one] -> ("reuse:"<>one,(),SignedPayout one :& VNil)
    _ -> ("family:"<>identifier,(),SignedPayout "family-tip" :& VNil)
instance WorkerPreparation (WorkerCommand 'Critical result) where
  prepareOutgoing _ = workerStep $ \_ (identifier :& VNil) -> ("prepare:"<>identifier,(),PreparedPayout identifier :& VNil)
instance WorkerSigning (WorkerCommand 'Critical result) where
  signPreparedPayment = F.step . Expand . SigningWorkflow
instance WorkerQueue (WorkerCommand 'Critical result) where
  queuePayment _ = workerStep $ \_ (SignedPayout txid :& VNil) -> ("queue:"<>txid,1,QueuedPayout txid :& VNil)
instance WorkerBroadcast (WorkerCommand 'Critical result) where
  broadcastPayment = F.step . Expand . BroadcastWorkflow
instance WorkerCycle (WorkerCommand 'Critical result) where
  runWorkerCycle = F.step . Expand . CycleWorkflow
instance CycleSteps (WorkerCommand 'Critical result) where
  cycleScope _ = F.step . Scoped CycleGuard
  recoverCycle _ = work "recover" (const ())
  cycleCanPay _ = work "enabled" enabled
  cycleCandidates _ = work "candidates" candidates
  cyclePayout value identifier = F.step $ Expand $ PayoutWorkflow value identifier
  cycleOwnerFees = F.step . Expand . OwnerFeesWorkflow
instance SigningSteps (WorkerCommand 'Critical result) where
  signingScope _ = F.step . Scoped SigningGuard
  inspectSigning _ = workerStep $ \s (BackupCovered (PreparedPayout identifier) :& VNil) ->
    ("inspect-signing",if saved s then Just "saved" else Nothing,SigningWork identifier :& VNil)
  reuseSignature _ txid = workerStep $ \_ (SigningWork _ :& VNil) -> ("reuse:"<>txid,txid,SignedPayout txid :& VNil)
  issueSignature _ = workerStep $ \_ (SigningWork identifier :& VNil) -> ("issue:"<>identifier,"new",SignedPayout "new" :& VNil)
instance BroadcastSteps (WorkerCommand 'Critical result) where
  broadcastScope _ = F.step . Scoped BroadcastGuard
  inspectBroadcast _ = workerStep $ \s (BackupCovered (QueuedPayout txid) :& VNil) ->
    ("inspect-broadcast",unseen s,BroadcastWork txid :& VNil)
  sendUnseenPayment _ = workerStep $ \_ (BroadcastWork txid :& VNil) -> ("send:"<>txid,(),VNil)
  recordObservedPayment _ = workerStep $ \_ (BroadcastWork txid :& VNil) -> ("record:"<>txid,(),VNil)
instance OwnerFeeSteps (WorkerCommand 'Critical result) where
  ownerFeeCandidates _ = work "fee-candidates" (\s -> if feesEnabled s then map OwnerFeeWork (feeCandidates s) else [])
  reserveOwnerFee _ (OwnerFeeWork candidate) = work ("reserve:"<>candidate) (const $ candidate=="saved")

scope :: Text -> [Text] -> [Text]
scope label events = ["begin:"<>label]<>events<>["end:"<>label]

-- Every program comes through the real existential compiler; this suite supplies
-- only leaf effects and a trace evaluator, never a second workflow compiler.
operatorProgram :: Plan 'Operator a -> Flow (Action 'Operator) '[] '[] a
operatorProgram (CriticalPlan request) = case checkedOperation request of
  Right (OperatorDSL flow) -> flow
  _ -> error "operator compilation failed"
operatorProgram SafePlan{} = error "expected critical operator request"
workerProgram :: Flow (Action 'Worker) '[] '[] ()
workerProgram = case checkedOperation (workerRequest @'[WorkerCycle] runWorkerCycle) of
  Right (WorkerDSL flow) -> flow
  _ -> error "worker compilation failed"

-- Check every exception and asynchronous cancellation prefix against an
-- independent literal trace: no later effect or successful scope exit may occur.
verify :: forall caller a. (Eq a,Trace caller) => Settings -> Flow (Action caller) '[] '[] a -> [Text] -> a -> IO Bool
verify settings flow expected wanted = and <$> forM
  [(fault,asynchronous) | fault<-[0..length expected],asynchronous<-[False,True]] (\(fault,asynchronous) -> do
    events<-newIORef []
    let record label=do
          modifyIORef' events (<>[label])
          count<-length <$> readIORef events
          when (fault==count) $ if asynchronous then throwIO ThreadKilled else throwIO (userError "outcome unknown")
        execute :: Action caller before after result -> Values before -> IO (result,Values after)
        execute (Perform effect) values = do
          let (label,result,next)=traceEffect effect settings values
          record label
          pure (result,next)
        execute (Within guard nested) values = do
          let label = case guard of OperatorGuard -> "operator"; SigningGuard -> "signing"; BroadcastGuard -> "broadcast"; CycleGuard -> "cycle"
          record ("begin:"<>label)
          result<-runFlow execute nested values
          record ("end:"<>label)
          pure result
    result<-try @SomeException (runFlow execute flow VNil)
    actual<-readIORef events
    pure $ actual==take (if fault==0 then length expected else fault) expected && case result of
      Right (value,VNil) -> fault==0 && value==wanted
      Left failure -> fault/=0 && if asynchronous then fromException failure==Just ThreadKilled
        else (fromException failure :: Maybe AsyncException)==Nothing)

operatorChecks :: IO Bool
operatorChecks = do
  results<-forM [False,True] $ \flag -> do
    let settings=defaults {saved=flag}
        check :: Eq a => Plan 'Operator a -> [Text] -> a -> IO Bool
        check plan events result=verify settings (operatorProgram plan) (scope "operator" events) result
    sequence
      [ check (operator @'[OperatorService] resumeService)
          (["check","recover","inspect","refresh","backup","observe","reconcile","draft"]<>if flag then ["restore","finish:draft"] else ["finish:no-draft"]) ()
      , check (operator @'[OperatorNative] $ \cap -> draftNativeReplacement cap "parent" (either (error . show) id $ amount 2) "review")
          (["draft:parent:2:review"]<>if flag then [] else ["refresh:parent","reconcile","draft-sign"]) (if flag then 7 else 8)
      , check (operator @'[OperatorNative] $ \cap -> signNativeReplacement cap 7)
          (["replacement:7"]<>if flag then [] else ["refresh:7","backup","observe","reconcile","replacement-sign"]) (if flag then "saved" else "new")
      , check (operator @'[OperatorRepair] $ \cap -> retrySolanaPayment cap "transaction" "review")
          (["retry:transaction:review"]<>if flag then [] else ["refresh:transaction","expiry","reconcile","approve:review:proof:transaction"]) ()
      , check (operator @'[OperatorRepair] $ \cap -> cancelPreparation cap "payment" 3 "review")
          (["cancel:payment"]<>if flag then [] else ["refresh:payment","reconcile","reread-and-validate","begin:3:review","release:payment","finish:payment"]) ()
      ]
  rebroadcast<-verify defaults (operatorProgram $ operator @'[OperatorNative] $ \cap -> rebroadcastNative cap "transaction" 9 "review")
    (scope "operator" ["inspect:transaction:9:review","backup","send-saved"]) "transaction"
  composed<-verify defaults (operatorProgram $ operator @'[OperatorNative,OperatorService] $ \cap -> F.do
    txid<-signNativeReplacement cap 7
    pauseService cap (if txid=="new" then "new-result" else "saved-result")
    F.pure txid)
    (scope "operator" ["replacement:7","refresh:7","backup","observe","reconcile","replacement-sign"]<>["pause:new-result"]) "new"
  branches<-forM [False,True] $ \choice ->
    verify defaults (operatorProgram $ operator @'[OperatorService] $ \cap ->
      F.Branch (const choice)
        (if choice then pauseService cap "yes" else error "unselected branch forced")
        (if choice then error "unselected branch forced" else pauseService cap "no"))
      [if choice then "pause:yes" else "pause:no"] ()
  pure (and $ concat results<>[rebroadcast,composed]<>branches)

payoutEvents :: Settings -> Text -> [Text]
payoutEvents settings identifier =
  let txid=case attempts settings of [] -> if saved settings then "saved" else "new"; [one] -> one; _ -> "family-tip"
      prepare=case attempts settings of
        [] -> ["prepare:"<>identifier,"backup"]<>scope "signing" ["inspect-signing",if saved settings then "reuse:saved" else "issue:"<>identifier]
        [_] -> ["reuse:"<>txid]
        _ -> ["family:"<>identifier]
  in ["inspect:"<>identifier]<>prepare<>["queue:"<>txid,"backup"]
    <>scope "broadcast" ["inspect-broadcast",(if unseen settings then "send:" else "record:")<>txid]

workerChecks :: IO Bool
workerChecks = do
  payouts<-forM [(previous,signature,send) | previous<-[[],["saved"],["parent","replacement"]],signature<-[False,True],send<-[False,True]] $ \(previous,signature,send) -> do
    let settings=defaults {attempts=previous,saved=signature,unseen=send,candidates=["payment"]}
    verify settings workerProgram (scope "cycle" $ ["recover","enabled","candidates"]<>payoutEvents settings "payment"<>["fee-candidates"]) ()
  -- A selector may compose stages and use their result. Assert the signature's
  -- returned value as well as its state, which the cycle itself does not expose.
  signatures<-forM [False,True] $ \signature -> do
    let request=workerRequest @'[WorkerObservation,WorkerPreparation,WorkerBackup,WorkerSigning,WorkerQueue,WorkerBroadcast] $ \cap -> F.do
          inspectPayout cap "payment"
          prepareOutgoing cap
          checkpointPending cap
          txid<-signPreparedPayment cap
          queuePayment cap
          checkpointPending cap
          broadcastPayment cap
          F.pure txid
        flow=case checkedOperation request of Right (WorkerDSL compiled) -> compiled; _ -> error "signature composition failed"
        settings=defaults {saved=signature}
    verify settings flow (payoutEvents settings "payment") (if signature then "saved" else "new")
  cycles<-forM [(active,identifiers) | active<-[False,True],identifiers<-[[],["first","second"]]] $ \(active,identifiers) -> do
    let settings=defaults {enabled=active,candidates=identifiers}
    verify settings workerProgram (scope "cycle" $ ["recover","enabled"]<>if active then ["candidates"]<>concatMap (payoutEvents settings) identifiers<>["fee-candidates"] else []) ()
  fees<-forM [(configured,options,visited) | configured<-[False,True],(options,visited)<-
    [([],[]),(["empty"],["empty"]),(["saved","later"],["saved"])
    ,(["insufficient","saved","later"],["insufficient","saved"]),(["empty","declined"],["empty","declined"])]] $ \(configured,options,visited) ->
    verify (defaults {feesEnabled=configured,feeCandidates=options}) workerProgram
      (scope "cycle" $ ["recover","enabled","candidates","fee-candidates"]<>if configured then map ("reserve:"<>) visited else []) ()
  pure (and $ payouts<>signatures<>cycles<>fees)

main :: IO ()
main = do
  let payload=SomeOperation (WorkerAction (Proxy @'[WorkerCycle]) runWorkerCycle :: WorkerCommand 'Critical ())
      absent Nothing=True
      absent Just{}=False
  unless (absent $ interpret payload (Compile :: DSL (OperatorCommand 'Critical ()))) $ fail "wrong caller accepted"
  unless (absent $ interpret payload (Compile :: DSL (WorkerCommand 'Critical Text))) $ fail "wrong result accepted"
  unless (absent $ interpret payload (Compile :: DSL (WorkerCommand 'Safe ()))) $ fail "wrong severity accepted"
  case checkedOperation (workerRequest @'[WorkerObservation] @() $ \cap -> F.do
    observeChains cap
    error "compiler forced a value-dependent continuation") of
      Right WorkerDSL{} -> pure ()
      _ -> fail "deferred continuation did not compile"
  results<-mapM (\(label,action) -> putStrLn label >> quickCheckWithResult stdArgs {maxSuccess=1} (once $ ioProperty action))
    [("actual command interpretation: operator branches and composed continuation",operatorChecks)
    ,("actual command interpretation: nested payout/cycle/signing/broadcast/fees",workerChecks)]
  unless (all isSuccess results) exitFailure
