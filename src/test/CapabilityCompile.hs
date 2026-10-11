{-# LANGUAGE CPP, OverloadedStrings, DataKinds, TypeApplications, FlexibleContexts #-}
-- Compile normally for the positive control; each BAD_* macro must fail.
module CapabilityCompile where
import Bridge.Operation.Internal
import Control.Operation
import Data.Coerce (coerce)
import Data.Proxy (Proxy(..))

valid :: Stage '[CompileOperation 'Customer 'Safe ()]
valid = Stage (\value -> operationDSL value `seq` Right value)

workerStage :: Stage '[WorkerOperations]
workerStage = Stage (\value -> queuePayment value "transaction" `seq` Right value)
combinedWorkerStage :: Stage '[CompileOperation 'Worker 'Critical (), WorkerOperations]
combinedWorkerStage = Stage (\value -> operationDSL value `seq` queuePayment value "transaction" `seq` Right value)
operatorStage :: Stage '[OperatorWrite]
operatorStage = Stage (\value -> pauseService value "review" `seq` Right value)

#ifdef BAD_DOMAIN
operatorFromWorker :: Stage '[WorkerOperations]
operatorFromWorker = Stage (\value -> pauseService value "review" `seq` Right value)
#endif
#ifdef BAD_HIDDEN_WORKER
hiddenWorker :: Stage '[CompileOperation 'Worker 'Critical ()]
hiddenWorker = Stage (\value -> queuePayment value "transaction" `seq` Right value)
#endif
#ifdef BAD_IO
injectIO :: (Execution 'Worker 'Critical WorkerCommand, WorkerOperations (WorkerCommand 'Critical ()))
         => IO () -> SomeOperationAt Program 'Worker 'Critical ()
injectIO action = workerRequest (\_ -> action)
#endif

#ifdef BAD_COMPILE
hiddenCompile :: Stage '[WorkerOperations]
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
