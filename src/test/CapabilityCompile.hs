{-# LANGUAGE CPP, OverloadedStrings, DataKinds, TypeApplications, FlexibleContexts, TypeOperators, QualifiedDo #-}
-- Compile normally for the positive control; each BAD_* macro must fail.
module CapabilityCompile where
import Bridge.Operation.Internal
import Bridge.Critical ()
import Control.Operation
import Data.Coerce (coerce)
import Data.Proxy (Proxy(..))
import Control.Operation.Flow (Flow)
import qualified Control.Operation.Flow as F
import Data.Text (Text)
import Data.Int (Int64)
import Data.Typeable (Typeable)

validPayout :: (Typeable value, PayoutCapabilities value) => value -> Maybe (Flow (PayoutStep value) '[Text] '[] ())
validPayout = payoutFlow

#ifdef BAD_FLOW_ORDER
signWithoutPreparation :: (Typeable value, WorkerSigning value) => Flow (PayoutStep value) '[Text] '[SignedPayout] ()
signWithoutPreparation = F.step (PayoutStep SignPayout)
#endif
#ifdef BAD_FLOW_BRANCH
unbackedBranch :: (Typeable value, WorkerQueue value, WorkerBackup value) => Bool -> Flow (PayoutStep value) '[SignedPayout] '[QueuedPayout] ()
unbackedBranch queued = if queued then F.step (PayoutStep QueuePayout) else F.pure ()
#endif
#ifdef BAD_FLOW_SEND
sendWithoutIntent :: (Typeable value, WorkerBroadcast value) => Flow (PayoutStep value) '[SignedPayout] '[] ()
sendWithoutIntent = F.step (PayoutStep SendPayout)
#endif
#ifdef BAD_FLOW_CAPABILITY
hiddenPayout :: Stage '[CompileOperation 'Worker 'Critical ()]
hiddenPayout = Stage (\value -> payoutFlow value `seq` Right value)
#endif
#ifdef BAD_FLOW_IO
uncheckedPayout :: IO () -> Flow (PayoutStep value) '[] '[] ()
uncheckedPayout work = F.step work
#endif
#ifdef BAD_FLOW_COERCE
coercePreparation :: Flow (PayoutStep value) '[PreparedPayout] '[SignedPayout] ()
                  -> Flow (PayoutStep value) '[Text] '[SignedPayout] ()
coercePreparation = coerce
#endif

valid :: Stage '[CompileOperation 'Customer 'Safe ()]
valid = Stage (\value -> operationDSL value `seq` Right value)

workerStage :: Stage '[WorkerQueue]
workerStage = Stage (\value -> queuePayment value "transaction" `seq` Right value)
combinedWorkerStage :: Stage '[CompileOperation 'Worker 'Critical (), WorkerQueue]
combinedWorkerStage = Stage (\value -> operationDSL value `seq` queuePayment value "transaction" `seq` Right value)
operatorStage :: Stage '[OperatorService]
operatorStage = Stage (\value -> pauseService value "review" `seq` Right value)

#ifdef BAD_DOMAIN
operatorFromWorker :: Stage '[WorkerQueue]
operatorFromWorker = Stage (\value -> pauseService value "review" `seq` Right value)
#endif
#ifdef BAD_HIDDEN_WORKER
hiddenWorker :: Stage '[CompileOperation 'Worker 'Critical ()]
hiddenWorker = Stage (\value -> queuePayment value "transaction" `seq` Right value)
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
queueRequest :: SomeOperationAt Program 'Worker 'Critical Int64
queueRequest = workerRequest @'[WorkerQueue] (\cap -> queuePayment cap "transaction")
serviceRequest :: Plan 'Operator ()
serviceRequest = operator @'[OperatorService] (\cap -> pauseService cap "review")
recoveryRequest :: Bool -> SomeOperationAt Program 'Worker 'Critical ()
recoveryRequest observe = workerRequest @'[WorkerObservation, WorkerRecovery] $ \cap ->
  if observe then observeChains cap else recoverNativeLocks cap
prepareStep :: (Typeable value, WorkerPreparation value, WorkerBackup value)
            => Flow (PayoutStep value) '[Text] '[PreparedPayout] ()
prepareStep = F.step (PayoutStep PreparePayout)

#ifdef BAD_PREPARATION_SIGN
preparationCannotSign :: SomeOperationAt Program 'Worker 'Critical Text
preparationCannotSign = workerRequest @'[WorkerPreparation] (\cap -> signPreparedPayment cap "payment")
#endif
#ifdef BAD_QUEUE_SEND
queueCannotSend :: SomeOperationAt Program 'Worker 'Critical ()
queueCannotSend = workerRequest @'[WorkerQueue] (\cap -> broadcastPayment cap "transaction")
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
prepareWithoutBackup :: (Typeable value, WorkerPreparation value)
                     => Flow (PayoutStep value) '[Text] '[PreparedPayout] ()
prepareWithoutBackup = F.step (PayoutStep PreparePayout)
#endif
