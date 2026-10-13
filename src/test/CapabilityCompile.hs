{-# LANGUAGE CPP, OverloadedStrings, DataKinds, TypeApplications, FlexibleContexts, TypeOperators, QualifiedDo #-}
-- Compile normally for the positive control; each BAD_* macro must fail.
module CapabilityCompile where
import Bridge.Operation.Internal
import Bridge.Critical ()
import Control.Operation
import Data.Coerce (coerce)
import Data.Proxy (Proxy(..))
import qualified Control.Operation.Flow as F
import Data.Text (Text)
import Data.Int (Int64)
import Data.Typeable (Typeable)

validPayout :: (Typeable value, PayoutCapabilities value) => value -> Text -> Maybe (Method value '[] '[] ())
validPayout = payoutFlow

#ifdef BAD_FLOW_ORDER
signWithoutPreparation :: WorkerSigning value => value -> Method value '[Text] '[SignedPayout] Text
signWithoutPreparation = signPreparedPayment
#endif
#ifdef BAD_FLOW_BRANCH
unbackedBranch :: WorkerQueue value => value -> Bool -> Method value '[SignedPayout] '[QueuedPayout] Int64
unbackedBranch value queued = if queued then queuePayment value else F.pure 0
#endif
#ifdef BAD_FLOW_SEND
sendWithoutIntent :: WorkerBroadcast value => value -> Method value '[SignedPayout] '[] ()
sendWithoutIntent = broadcastPayment
#endif
#ifdef BAD_FLOW_CAPABILITY
hiddenPayout :: Stage '[CompileOperation 'Worker 'Critical ()]
hiddenPayout = Stage (\value -> payoutFlow value "payment" `seq` Right value)
#endif
#ifdef BAD_FLOW_IO
uncheckedPayout :: IO () -> F.Flow (Action 'Worker) '[] '[] ()
uncheckedPayout work = F.step work
#endif
#ifdef BAD_FLOW_COERCE
coercePreparation :: F.Flow (Action 'Worker) '[BackupCovered PreparedPayout] '[SignedPayout] Text
                  -> F.Flow (Action 'Worker) '[Text] '[SignedPayout] Text
coercePreparation = coerce
#endif
#ifdef BAD_PREP_BACKUP
signWithoutBackup :: WorkerSigning value => value -> Method value '[PreparedPayout] '[SignedPayout] Text
signWithoutBackup = signPreparedPayment
#endif
#ifdef BAD_QUEUE_BACKUP
sendWithoutBackup :: WorkerBroadcast value => value -> Method value '[QueuedPayout] '[] ()
sendWithoutBackup = broadcastPayment
#endif

valid :: Stage '[CompileOperation 'Customer 'Safe ()]
valid = Stage (\value -> operationDSL value `seq` Right value)

workerStage :: Stage '[WorkerQueue]
workerStage = Stage (\value -> queuePayment value `seq` Right value)
combinedWorkerStage :: Stage '[CompileOperation 'Worker 'Critical (), WorkerQueue]
combinedWorkerStage = Stage (\value -> operationDSL value `seq` queuePayment value `seq` Right value)
operatorStage :: Stage '[OperatorService]
operatorStage = Stage (\value -> pauseService value "review" `seq` Right value)

#ifdef BAD_DOMAIN
operatorFromWorker :: Stage '[WorkerQueue]
operatorFromWorker = Stage (\value -> pauseService value "review" `seq` Right value)
#endif
#ifdef BAD_HIDDEN_WORKER
hiddenWorker :: Stage '[CompileOperation 'Worker 'Critical ()]
hiddenWorker = Stage (\value -> queuePayment value `seq` Right value)
#endif
#ifdef BAD_IO
injectIO :: IO () -> SomeOperationAt Program 'Worker 'Critical ()
injectIO action = workerRequest @'[WorkerQueue] (\_ -> action)
#endif

#ifdef BAD_COMPILE
hiddenCompile :: Stage '[WorkerQueue]
hiddenCompile = Stage (\value -> operationDSL value `seq` Right value)
#endif
#ifdef BAD_WIDEN
widen :: Pipeline (PreparationCaps 'Customer 'Safe ()) '[] (PreparationCaps 'Customer 'Safe ())
widen = Restrict (Proxy @(PreparationCaps 'Customer 'Safe ()))
#endif
#ifdef BAD_CALLER
wrongCaller :: SomeOperationAt Program 'Customer 'Critical a -> SomeOperationAt Program 'Signer 'Critical a
wrongCaller = id
#endif
#ifdef BAD_SEVERITY
wrongSeverity :: SomeOperationAt Program 'Customer 'Safe a -> SomeOperationAt Program 'Customer 'Critical a
wrongSeverity = id
#endif
#ifdef BAD_RESULT
wrongResult :: SomeOperationAt Program 'Signer 'Critical PreparedResult -> SomeOperationAt Program 'Signer 'Critical ReplacementResult
wrongResult = id
#endif

#ifdef BAD_COERCE
coerceCaller :: SomeOperationAt Program 'Customer 'Critical a -> SomeOperationAt Program 'Signer 'Critical a
coerceCaller = coerce
#endif

-- Positive controls for the actual narrowed request path, not just generic Stage.
observationRequest :: SomeOperationAt Program 'Worker 'Critical ()
observationRequest = workerRequest @'[WorkerObservation] observeChains
serviceRequest :: Plan 'Operator ()
serviceRequest = operator @'[OperatorService] (\cap -> pauseService cap "review")
recoveryRequest :: Bool -> SomeOperationAt Program 'Worker 'Critical ()
recoveryRequest observe = workerRequest @'[WorkerObservation, WorkerRecovery] $ \cap ->
  F.do
    if observe then observeChains cap else F.pure ()
    recoverNativeLocks cap
prepareStep :: (WorkerPreparation value, WorkerBackup value)
            => value -> Method value '[Text] '[BackupCovered PreparedPayout] ()
prepareStep value = F.do
  prepareOutgoing value
  checkpointPending value

#ifdef BAD_PREPARATION_SIGN
preparationCannotSign :: SomeOperationAt Program 'Worker 'Critical ()
preparationCannotSign = workerRequest @'[WorkerPreparation] (\cap -> signPreparedPayment cap `seq` F.pure ())
#endif
#ifdef BAD_QUEUE_SEND
queueCannotSend :: SomeOperationAt Program 'Worker 'Critical ()
queueCannotSend = workerRequest @'[WorkerQueue] (\cap -> broadcastPayment cap `seq` F.pure ())
#endif
#ifdef BAD_SERVICE_TREASURY
serviceCannotWithdraw :: Plan 'Operator Text
serviceCannotWithdraw = operator @'[OperatorService] (\cap -> cancelFeeWithdrawal cap "id" "reason")
#endif
#ifdef BAD_SOURCE_NATIVE
sourceCannotReplace :: Plan 'Operator Text
sourceCannotReplace = operator @'[OperatorSource] (\cap -> signNativeReplacement cap 1)
#endif
#ifdef BAD_REQUEST_DOMAIN
operatorCannotSelectWorker :: Plan 'Operator ()
operatorCannotSelectWorker = operator @'[WorkerBroadcast] (\_ -> error "unreachable selector")
#endif
#ifdef BAD_STEP_CAPABILITY
prepareWithoutBackup :: WorkerPreparation value
                     => value -> Method value '[Text] '[BackupCovered PreparedPayout] ()
prepareWithoutBackup value = F.do
  prepareOutgoing value
  checkpointPending value
#endif
