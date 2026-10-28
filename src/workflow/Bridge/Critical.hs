{-# LANGUAGE AllowAmbiguousTypes, QualifiedDo #-}
{-# LANGUAGE DataKinds, GADTs, RankNTypes, ScopedTypeVariables, TypeFamilies, TypeApplications, ConstraintKinds, PatternSynonyms, ViewPatterns, FlexibleInstances, QuantifiedConstraints, FlexibleContexts, UndecidableInstances, MultiParamTypeClasses #-}
{-# OPTIONS_GHC -Werror=incomplete-patterns -Werror=missing-methods #-}
-- The signer ClientM is constructed only inside this critical evaluator.
module Bridge.Critical (operationPath,Process(..),WorkerLifetime(..),runProcess,CustomerSettings(..),SignerSettings(..),runWorkerLoop) where
import Bridge.Operation.Internal hiding (customer)
import qualified Bridge.Operation.Internal as Operation
import Control.Operation (Capabilities,UniqueCapabilities,Subset)
import Control.Operation.Flow (Flow,Values(..),runFlow)
import qualified Control.Operation.Flow as F
import Bridge.Domain (Asset(..),Amount,gross,paymentAsset,paymentId,units)
import Bridge.Identity (payURIFor,digest)
import Bridge.Admission (checkSolanaPayoutWith)
import Bridge.Order (createCustomerOrder)
import Bridge.Credentials (readNativeUnlock,withNativeUnlock)
import qualified Bridge.Config as C
import Bridge.Recovery
import Bridge.Control (runControl)
import Bridge.Web (publicApplication,runPublicServer)
import Data.Int (Int64)
import Data.Word (Word64)
import GHC.Clock (getMonotonicTimeNSec)
import qualified Database.PostgreSQL.Simple as PG
import qualified Data.Map.Strict as M
import qualified Data.Text as T
import Bridge.Error
import Bridge.Payment
import Bridge.Observer (ObserverSettings(..),observeOnce)
import Bridge.Reconciliation (inspectLossCustody)
import qualified Bridge.Reconciliation as Reconciliation
import Bridge.PaymentSource (verifyPaymentSource,inspectNativeSource)
import qualified Bridge.Wire as W
import Control.Monad (forM,forM_,when,forever)
import qualified Bridge.NativePayment as NP
import Bridge.NativePayment (NativeSigned,previewNativePayment,checkNativeAcceptance,releaseNativeInputLocks)
import Bridge.SolanaPayment (SolanaSigned,signedSolanaPlan,solPlanRecent,solPlanFeeLimit,solPlanRentLimit,checkBlockhashForSend,prepareSolanaSigned)
import Data.Text (Text)
import Bridge.PaymentObservation
import qualified Bridge.Solana as S
import qualified Bridge.SolanaDeposit as SD
import qualified Bridge.AdminStatus as Admin
import Data.Aeson (Value,eitherDecodeStrict',FromJSON,toJSON,object,(.=),parseJSON,encode)
import qualified Data.Text.Encoding as TE
import qualified Data.ByteString.Lazy as BL
import Data.Typeable (Typeable)
import Data.Proxy (Proxy(..))
import Bridge.Signer (signingAPI,SigningEndpoint(..),signerCredentials,signerCertificate,verifySigningKey,signingApplication,runSigningServer)
import Bridge.Store
import qualified Bridge.Native as N
import qualified Bridge.SolanaHelper as H
import Bridge.RPC (boundedBody,parseValue)
import qualified Bridge.RPC as RPC
import Control.Concurrent (threadDelay)
import Control.Concurrent.Async (concurrently_)
import System.IO (hPutStrLn,stderr)
import Control.Concurrent.MVar (MVar,newMVar,withMVar,modifyMVar)
import Control.Exception (bracket,onException,try,catch,throwIO,IOException)
import Data.IORef (newIORef,atomicModifyIORef')
import Data.Unique (newUnique,hashUnique)
import System.Posix.Process (getProcessID)
import qualified Data.ByteString as BS
import Data.Time.Clock.POSIX (getPOSIXTime)
import System.Directory (removeDirectoryRecursive)
import System.FilePath (takeDirectory)
import System.Timeout (timeout)
import Network.HTTP.Client hiding (Proxy)
import Network.HTTP.Client.TLS (mkManagerSettings)
import qualified Network.Connection as NC
import qualified Network.TLS as TLS
import Network.TLS.Extra.Cipher (ciphersuite_default)
import Data.X509.CertificateStore (makeCertificateStore)
import Servant.API ((:<|>)(..))
import qualified Servant.Client as SC

-- Evaluators recover their closed effect dictionary from the compiled grammar.
-- This view is private to evaluator dispatch; it is never returned by a handler.
data ExecutionProof caller severity a where
  ExecutionProof :: ExecutionContext caller severity a => ExecutionProof caller severity a

executionProof :: Program caller severity a -> ExecutionProof caller severity a
executionProof ReadOperator{} = ExecutionProof
executionProof OperatorDSL{} = ExecutionProof
executionProof WorkerDSL{} = ExecutionProof
executionProof ReadCustomer{} = ExecutionProof
executionProof WriteCustomer{} = ExecutionProof
executionProof SigningDSL{} = ExecutionProof

-- Recover the closed effect capability after restricted library preparation.
-- Recover the dictionary from the closed DSL, never an unchecked request.
pattern Executable :: () => ExecutionContext caller severity a => Program caller severity a
pattern Executable <- (executionProof -> ExecutionProof)
{-# COMPLETE Executable #-}

-- Safe interpretation has no writer, signer transport, keys or RPC manager.
data instance Evaluation 'Safe = SafeEnvironment Reader (Maybe W.PublicConfiguration)
  (MVar (Maybe (Word64,Maybe W.PublicReport)))

-- Coalesce public refreshes, including failures. This cache carries no authority;
-- intake checks stay live and the report retains its actual observation times.
cachedPublicReport :: Reader -> MVar (Maybe (Word64,Maybe W.PublicReport)) -> Int64 -> IO (Maybe W.PublicReport)
cachedPublicReport reader cache now=modifyMVar cache $ \saved->do
  tick<-getMonotonicTimeNSec
  (stamp,report)<-case saved of
    Just entry@(stamp,_) | tick-stamp<30000000000->pure entry
    _->do
      result<-(timeout 5000000 (Just <$> evalRead reader (ReadPublicReport now)))
        `catch` (\(_::BridgeError)->pure Nothing)
        `catch` (\(_::PG.SqlError)->pure Nothing)
        `catch` (\(_::IOException)->pure Nothing)
      pure(tick,maybe Nothing id result)
  let aged value=value {W.reportCustodyFresh=W.reportCustodyFresh value
        && maybe False (\at->at<=now && now-at<=60) (W.reportCustodyAt value)}
  pure(Just(stamp,report),aged <$> report)

evalSafe :: Evaluation 'Safe -> SomeOperationAt Program caller 'Safe a -> IO a
evalSafe environment request=do
  program<-either reject pure (checkedOperation request)
  traceEvaluation program $ case program of
    Executable->authorizeOperation environment program >> evaluateOperation environment program

-- Fixed labels only: never inspect/show request arguments, credentials or results.
-- Signer labels are the Handler/Result relation in test/formal/SignerPaths.tla.
operationPath :: Program caller severity a -> Maybe (Text,Text,Text)
operationPath (SigningDSL signing)=Just $ case signing of
  PreparedSigning{} -> ("sign-preparation","SignPrepared","PreparedResult")
  ReplacementSigning{} -> ("sign-replacement","SignReplacement","ReplacementResult")
  DraftSigning{} -> ("draft-replacement","DraftReplacement","DraftResult")
  CheckpointSigning{} -> ("checkpoint-custody","CheckpointCustody","CheckpointResult")
operationPath (ReadCustomer op)=Just $ case op of
  PublicConfig -> ("GET /api/v1/config","PublicConfig","PublicConfiguration")
  OrderStatus{} -> ("GET /api/v1/orders/:id","OrderStatus","OrderView")
  PaymentInstructions{} -> ("POST /api/v1/orders/:id/transaction","PaymentInstructions","PaymentInstruction")
operationPath (WriteCustomer Operation.CreateOrder{})=Just ("POST /api/v1/orders","CreateOrder","OrderView")
operationPath _=Nothing

-- Correlation is process-local, not a payment identifier or authorization token.
-- 'done' records a returned value, not delivery, broadcast or settlement.
traceEvaluation :: Program caller severity a -> IO a -> IO a
traceEvaluation program work=case operationPath program of
  Nothing->work
  Just (path,operation,constructor)->do
    correlation<-hashUnique <$> newUnique
    process<-getProcessID
    let emit stage=(hPutStrLn stderr $ T.unpack $ TE.decodeUtf8 $ BL.toStrict $ encode $ object
          ["event" .= ("operation_path"::Text),"trace" .= correlation,"process" .= show process,"path" .= path
          ,"operation" .= operation,"expectedResult" .= constructor,"stage" .= (stage::Text)])
          `catch` (\(_::IOException)->pure ())
    emit "resolved"
    emit "dsl"
    emit "evaluating"
    result<-work `onException` emit "rejected"
    emit "done"
    pure result

-- Ground instances own the closed effect grammar and concrete IO. Payload-type
-- equality is checked by the library interpreter before these methods run.
instance Execution 'Customer 'Safe CustomerCommand where
  authorizeOperation _ _=pure ()
  evaluateOperation (SafeEnvironment reader public cache) (ReadCustomer operation)=run operation
   where
    run :: CustomerRead a -> IO a
    run PublicConfig=do
      configuration<-configured
      now<-floor <$> getPOSIXTime
      report<-cachedPublicReport reader cache now
      let reported=configuration {W.pubReport=report}
      if not(W.pubIntakeEnabled configuration) then pure reported {W.pubAvailability=W.Availability False "observation_only"} else do
        result<-try (evalRead reader $ CheckIntake now) :: IO (Either BridgeError ())
        let state=case result of Right ()->W.Availability True ""; Left (BridgeError code)->W.Availability False code
        pure reported {W.pubAvailability=state}
    run (OrderStatus header identifier)=evalRead reader (ReadOrder header identifier)
    run (PaymentInstructions header identifier)=do
      configuration<-configured
      require (W.pubIntakeEnabled configuration) "deposit_window_closed"
      now<-floor <$> getPOSIXTime
      view<-evalRead reader (ReadPayableOrder now header identifier)
      instruction<-maybe (reject "instruction_not_recorded") pure (W.depositInstruction view)
      let mint=W.pubMint configuration
      uri<-either reject pure (payURIFor (W.pubCustodyOwner configuration) mint instruction (gross $ W.quote view))
      pure $ W.PaymentInstruction uri (T.drop 11 instruction) mint (gross $ W.quote view) "verified_source_owner"
    configured=maybe (reject "customer_configuration_unavailable") pure public

instance Execution 'Operator 'Safe OperatorCommand where
  authorizeOperation _ _=pure ()
  evaluateOperation (SafeEnvironment reader _ _) (ReadOperator operation)=run operation
   where
    run :: OperatorRead a -> IO a
    run NativeReviews=evalRead reader ReadNativeReviews
    run TreasuryReceipts=evalRead reader ReadTreasuryReceipts
    run ServiceState=evalRead reader ReadServiceStatus

data CustomerSettings = CustomerSettings
  { publicConfiguration :: W.PublicConfiguration, customerPolicy :: StorePolicy
  , unsignedSdk :: FilePath, ownerFeeRecipients :: Maybe C.OwnerFeeRecipients }

data SignerSettings = SignerSettings
  { signingNative :: N.NativeSettings, signingSolana :: S.SolanaSettings
  , signingPolicy :: H.SolanaPolicy, signingLibrary :: FilePath, signingKey :: FilePath
  , signingNativeUnlock :: Maybe FilePath
  , signingBackup :: Maybe (C.Config,FilePath,FilePath) }

-- Concrete service lifetimes, never caller-supplied evaluator continuations.
-- Checkpointing holds the same writer/fence without starting any background work.
-- Signer startup cannot receive a writer or customer configuration.
data WorkerLifetime = Serving Int FilePath FilePath | Checkpointing
data Process
  = WorkerProcess ObserverSettings H.SolanaPolicy (Maybe CustomerSettings) SigningEndpoint Writer WorkerLifetime
  | SignerProcess SignerSettings SigningEndpoint

runProcess :: Manager -> Reader -> Process -> IO ()
runProcess rpc reader process=do
  environment<-case process of
    SignerProcess settings _->do
      let native=signingNative settings; solana=signingSolana settings; config=signingPolicy settings
      require (S.solanaProfile solana==N.profile native
        && S.mint solana==H.mint config && S.custodyOwner solana==H.custodyOwner config
        && S.custodyAta solana==H.custodyAta config) "signer_profile_mismatch"
      N.validateNativeSettings native
      S.validateSolanaSettings solana
      verifySigningKey (S.custodyOwner solana) (signingKey settings)
      forM_ (signingNativeUnlock settings) $ \path->readNativeUnlock path >> pure ()
      pure $ SignerEvaluation rpc reader settings
    WorkerProcess settings config customerSettings endpoint writer _->do
      let native=nativeSettings settings; solana=solanaSettings settings
      require (N.profile native==S.solanaProfile solana && S.mint solana==H.mint config
        && S.custodyOwner solana==H.custodyOwner config && S.custodyAta solana==H.custodyAta config) "payment_profile_mismatch"
      N.validateNativeSettings native
      S.validateSolanaSettings solana
      forM_ customerSettings $ \configured->do
        let public=publicConfiguration configured; store=customerPolicy configured
            policy=W.paymentPolicy(executionTerms store); costs=W.paymentLimits(executionTerms store)
        require (W.pubProfile public==N.profile native && W.pubMint public==H.mint config
          && W.pubCustodyOwner public==H.custodyOwner config && W.pubDeployment public==H.deploymentId config
          && W.pubDecimals public==8
          && W.pubPayoutPolicy public==payoutPolicy store
          && W.pubFeesBps public==M.fromList [("NativeToWrapped",100),("WrappedToNative",100)]
          && W.pubSolanaCluster public==(if N.profile native==W.CanonicalBeta then "mainnet-beta" else "devnet")
          && W.deploymentFingerprint policy==H.fingerprint config && W.nativeDepth policy==defaultNativeDepth settings
          && W.savedSolanaFee costs==H.maxSolFee config && W.savedSolanaRent costs==H.maxSolAccountRent config) "customer_configuration_mismatch"
      pure $ WorkerEvaluation (CriticalEnvironment rpc settings config customerSettings endpoint reader writer)
  -- The only critical dispatch call site. It cannot escape this service lifetime.
  -- Each OS process owns its own gate; the two processes share no mutable state.
  gate<-newMVar ()
  let dispatch :: forall caller a. SomeOperationAt Program caller 'Critical a -> IO a
      dispatch request=do
        program<-either reject pure (checkedOperation request)
        evalCritical gate environment program
  case process of
    SignerProcess _ endpoint->do
      credentials<-signerCredentials endpoint
      signingApplication credentials dispatch >>= runSigningServer endpoint
    WorkerProcess _ _ _ _ _ Checkpointing->
      dispatch (workerRequest @'[WorkerBackup] checkpointForUpgrade) >>= BL.putStr . (<> "\n") . encode
    WorkerProcess _ _ customerSettings _ _ (Serving port assets directory)->do
      reportCache<-newMVar Nothing
      let safeEnvironment=SafeEnvironment reader (publicConfiguration <$> customerSettings) reportCache
          evaluate :: forall caller a. Plan caller a -> IO a
          evaluate (SafePlan request)=evalSafe safeEnvironment request
          evaluate (CriticalPlan request)=dispatch request
      app<-publicApplication assets evaluate
      concurrently_
        (runPublicServer port app)
        (concurrently_ (runWorkerLoop dispatch) (runControl directory evaluate))

evalCritical :: MVar () -> Evaluation 'Critical -> Program caller 'Critical a -> IO a
evalCritical gate environment operation@Executable =
  withMVar gate $ \_ -> traceEvaluation operation $ do
    authorizeOperation environment operation
    case (environment, operation) of
      -- Only the signer process holds keys. Keep all local key work inside
      -- this evaluator, under the gate and after caller authorization.
      (SignerEvaluation manager reader settings, SigningDSL signing) -> do
        let native = signingNative settings
            solana = signingSolana settings
            config = signingPolicy settings
            nativeRpc = N.nativeCall manager native
            solanaRpc = S.solanaCall manager solana
            expectedIdentity = H.fingerprint config

            -- Re-read the durable decision after the work. Changed authority
            -- discards the result; each read uses a fresh timestamp.
            withStableDecision
              :: Eq decision
              => (Int64 -> StoreRead decision)
              -> (decision -> IO result)
              -> IO result
            withStableDecision query work = do
              let readDecision = do
                    now <- floor <$> getPOSIXTime
                    evalRead reader (query now)
              before <- readDecision
              result <- work before
              after <- readDecision
              require (before == after) "signing_decision_changed"
              pure result

        case signing of
          CheckpointSigning (CheckpointCustody identity minimumSequence) -> do
            require (identity == expectedIdentity && minimumSequence >= 0)
              "invalid_custody_checkpoint"
            (deployment, backup, parent) <-
              maybe (reject "custody_checkpoint_not_configured") pure
                (signingBackup settings)
            require
              ( C.fingerprint deployment == identity
                && C.nativeSettings deployment == native
                && C.solanaSettings deployment == solana
                && C.nativeUnlockFile deployment == signingNativeUnlock settings
              ) "signer_profile_mismatch"

            -- Keep acquisition, upload/recheck and cleanup in one bracket.
            let exportCheckpoint = evalCustodyRecovery manager deployment $
                  ExportCheckpoint reader (signingKey settings) parent minimumSequence
                removeExport (manifest, _) =
                  removeDirectoryRecursive (takeDirectory manifest)
                uploadAndVerify (manifest, sequenceNo) = do
                  receipt <- evalCustodyRecovery manager deployment
                    (UploadCustody backup manifest sequenceNo)
                  after <- evalRead reader ReadState
                  require (ledgerSequence after == sequenceNo) "custody_backup_changed"
                  pure receipt
                fiveMinutes = 300000000 -- microseconds

            result <- timeout fiveMinutes $
              bracket exportCheckpoint removeExport uploadAndVerify
            receipt <- maybe (reject "custody_checkpoint_timeout") pure result
            pure (CheckpointResult receipt)

          DraftSigning (DraftReplacement identity parent fee) -> do
            require (identity == expectedIdentity) "signer_profile_mismatch"
            draft <- withStableDecision
              (\now -> ReadReplacementDraftContext now parent fee)
              (\family -> NP.draftNativeReplacement nativeRpc native (map snd family) fee)
            pure (DraftResult draft)

          ReplacementSigning (SignReplacement identity decision) -> do
            require (identity == expectedIdentity) "signer_profile_mismatch"
            (family, signed) <- withStableDecision
              (\now -> ReadReplacementSigning now decision) $ \(family, draft) -> do
                signed <- withNativeUnlock nativeRpc native (signingNativeUnlock settings) $
                  NP.signNativeReplacement nativeRpc native (map snd family) draft
                pure (family, signed)
            parent <- case reverse family of
              (saved, _) : _ -> pure saved
              [] -> reject "native_replacement_family_bounds"
            pure $ ReplacementResult $ SignedAttempt
              { signedId = NP.nativeTxid (NP.signedNativeTransaction signed)
              , signedBytes = NP.signedNativeBytes signed
              , signedPolicy = TE.decodeUtf8 (BL.toStrict $ encode signed)
              , commonInput = commonInput (recordedSigned parent)
              }

          PreparedSigning (SignPrepared identity identifier generation) -> do
            require (identity == expectedIdentity) "signer_profile_mismatch"
            signed <- withStableDecision
              (\now -> ReadSigningDecision now identifier generation) $ \prepared -> do
                plan <- resolveSigningPlan (N.profile native) config prepared
                reply <- case plan of
                  NativeAuthorization saved draft -> do
                    _ <- N.nativeIdentity manager native
                    withNativeUnlock nativeRpc native (signingNativeUnlock settings) $
                      NativeReply <$> NP.signNativeDraft nativeRpc saved draft

                  SolanaAuthorization saved expected -> do
                    _ <- S.solanaIdentity manager solana
                    let limits = config
                          { H.maxSolFee = solPlanFeeLimit saved
                          , H.maxSolAccountRent = solPlanRentLimit saved
                          }
                        sign actual = do
                          require (actual == expected) "saved_solana_request_mismatch"
                          H.signSolanaSdk (signingLibrary settings) limits
                            (signingKey settings) actual
                    SolanaReply <$> prepareSolanaSigned solanaRpc sign limits saved

                verifySigningReply nativeRpc (N.profile native) config prepared reply
            pure (PreparedResult signed)

      -- Worker/customer/operator effects use the same authorized Program.
      _ -> evaluateOperation environment operation

-- Private resources, never callbacks or operations supplied by a caller.
data CriticalEnvironment = CriticalEnvironment
  Manager ObserverSettings H.SolanaPolicy (Maybe CustomerSettings) SigningEndpoint Reader Writer

data instance Evaluation 'Critical
  = WorkerEvaluation CriticalEnvironment
  | SignerEvaluation Manager Reader SignerSettings

paying :: CriticalEnvironment -> Bool
paying (CriticalEnvironment _ _ _ configured _ _ _)=maybe True (W.pubIntakeEnabled . publicConfiguration) configured

customer :: CriticalEnvironment -> IO CustomerSettings
customer (CriticalEnvironment _ _ _ configured _ _ _)=maybe (reject "customer_configuration_unavailable") pure configured

-- Internal instructions are already authorized under the caller's held gate.
-- They pass through the checked grammar without reacquiring that gate.
evalWorker :: forall selected a.
              (Typeable a, Capabilities selected (WorkerCommand 'Critical a),
               UniqueCapabilities selected, Subset selected (DomainCaps 'Worker 'Critical),
               Subset selected (PreparationCaps 'Worker 'Critical a))
           => CriticalEnvironment
           -> (forall value. Capabilities selected value => value -> Method value '[] '[] a) -> IO a
evalWorker environment operation=evalWorkerRequest environment (workerRequest @selected operation)

evalWorkerRequest :: CriticalEnvironment -> SomeOperationAt Program 'Worker 'Critical a -> IO a
evalWorkerRequest environment request=do
  program<-either reject pure (checkedOperation request)
  case program of Executable->evaluateOperation (WorkerEvaluation environment) program

evaluateSigning :: Typeable a => CriticalEnvironment -> SigningOperation a -> IO a
evaluateSigning environment operation=do
  program<-either reject pure (checkedOperation $ pending $ SignerAction operation)
  case program of Executable->evaluateOperation (WorkerEvaluation environment) program

instance Execution 'Signer 'Critical SignerCommand where
  authorizeOperation WorkerEvaluation{} _=reject "signer_operation_forbidden"
  authorizeOperation SignerEvaluation{} _=pure ()
  evaluateOperation (WorkerEvaluation environment@(CriticalEnvironment _ _ _ _ endpoint _ _)) (SigningDSL operation)=do
    require (paying environment) "observation_only"
    credentials<-signerCredentials endpoint
    certificate<-signerCertificate endpoint
    let base=TLS.defaultParamsClient "127.0.0.1" BS.empty
        tls=base {TLS.clientShared=(TLS.clientShared base) {TLS.sharedCAStore=makeCertificateStore [certificate]}
          ,TLS.clientSupported=(TLS.clientSupported base) {TLS.supportedCiphers=ciphersuite_default}}
        settings=managerSetProxy noProxy (mkManagerSettings (NC.TLSSettings tls) Nothing)
          {managerRetryableException=const False,managerIdleConnectionCount=0
          ,managerResponseTimeout=responseTimeoutMicro (case operation of CheckpointSigning{}->315000000; _->60000000)
          ,managerModifyRequest= \request->pure request {redirectCount=0}
          ,managerModifyResponse= \response->do
            bytes<-boundedBody 524288 (responseBody response)
            body<-newIORef bytes
            pure response {responseBody=atomicModifyIORef' body $ \chunk->(BS.empty,chunk)}}
    bracket (newManager settings) closeManager $ \local->do
      let prepared :<|> replacement :<|> draft :<|> checkpoint=SC.client signingAPI credentials
          clientEnvironment=SC.mkClientEnv local (SC.BaseUrl SC.Https "127.0.0.1" (signerPort endpoint) "")
          call=case operation of
            CheckpointSigning (CheckpointCustody identity minimumSequence)->checkpoint (identity,minimumSequence)
            PreparedSigning (SignPrepared identity identifier generation)->prepared (identity,identifier,generation)
            ReplacementSigning (SignReplacement identity decision)->replacement (identity,decision)
            DraftSigning (DraftReplacement identity parent fee)->draft (identity,parent,fee)
      result<-SC.runClientM call clientEnvironment
      -- Even an HTTP failure may follow signing. Retain the preparation;
      -- never automatically retry or pretend the outcome is known.
      either (const $ reject "signer_outcome_unknown") pure result
  evaluateOperation SignerEvaluation{} _=reject "signer_evaluator_required"

instance Execution 'Customer 'Critical CustomerCommand where
  authorizeOperation (WorkerEvaluation environment) _=require (paying environment) "observation_only"
  authorizeOperation SignerEvaluation{} _=reject "signer_context_forbidden"
  evaluateOperation SignerEvaluation{} _=reject "signer_context_forbidden"
  evaluateOperation (WorkerEvaluation environment@(CriticalEnvironment rpc settings config _ _ reader writer))
      (WriteCustomer (Bridge.Operation.Internal.CreateOrder header request))=do
    c<-customer environment
    createCustomerOrder rpc settings config (customerPolicy c) (unsignedSdk c) (\n->evalWorker @'[WorkerBackup] environment (\cap -> checkpointBackup cap n) >> freshIntake environment) reader writer header request

-- Private instruction constructors own IO; capability methods only build Flow.
-- A composed Flow checks each leaf's original observation permission before IO,
-- including leaves chosen by a value-dependent continuation, under the held gate.
data instance Effect 'Operator before after a where
  OperatorEffect :: Bool -> (CriticalEnvironment -> Values before -> IO (a,Values after)) -> Effect 'Operator before after a
data instance Effect 'Worker before after a where
  WorkerEffect :: Bool -> (CriticalEnvironment -> Values before -> IO (a,Values after)) -> Effect 'Worker before after a

operatorEffect :: Bool -> (CriticalEnvironment -> IO a) -> Flow (RequestStep 'Operator) state state a
operatorEffect allowed action = F.step $ Leaf $ OperatorEffect allowed $ \environment values -> do
  result <- action environment
  pure (result,values)
workerEffect :: Bool -> (CriticalEnvironment -> IO a) -> Flow (RequestStep 'Worker) state state a
workerEffect allowed action = workerStep allowed $ \environment values -> do
  result <- action environment
  pure (result,values)
workerStep :: Bool -> (CriticalEnvironment -> Values before -> IO (a,Values after)) -> Flow (RequestStep 'Worker) before after a
workerStep allowed = F.step . Leaf . WorkerEffect allowed

-- A scope encloses the entire continuation, including cancellation between leaves.
-- It uses the already-held critical gate, never a second evaluator entry point.
runOperatorFlow :: CriticalEnvironment -> Flow (Action 'Operator) before after a -> Values before -> IO (a,Values after)
runOperatorFlow environment = runFlow $ \instruction values -> case instruction of
  Perform (OperatorEffect allowed action) -> do
    require (allowed || paying environment) "observation_only"
    action environment values
  Within OperatorGuard flow -> do
    require (paying environment) "observation_only"
    guarded environment (runOperatorFlow environment flow values)
runWorkerFlow :: CriticalEnvironment -> Flow (Action 'Worker) before after a -> Values before -> IO (a,Values after)
runWorkerFlow environment@(CriticalEnvironment _ _ _ _ _ reader writer) = runFlow $ \instruction values -> case instruction of
  Perform (WorkerEffect allowed action) -> do
    require (allowed || paying environment) "observation_only"
    action environment values
  Within SigningGuard flow -> do
    require (paying environment) "observation_only"
    runWorkerFlow environment flow values `onException` evalWrite writer (Pause "signing_requires_review")
  Within BroadcastGuard flow -> do
    require (paying environment) "observation_only"
    guarded environment (runWorkerFlow environment flow values)
  Within CycleGuard flow -> runWorkerFlow environment flow values `catch` (\(BridgeError code) ->
    if code=="custody_not_reconciled" then do
      paused<-ledgerPaused <$> evalRead reader ReadState
      when paused (reject code)
      pure ((),values)
    else evalWrite writer (Pause code) >> reject code)

-- Only the concrete interpreter constructs runtime evidence; interpretation owns
-- its ordering and branches, while these values retain exact saved decisions.
data instance ResumeWork (OperatorCommand 'Critical result) = ResumeWork [RecordedAttempt]
data instance ResumeDraft (OperatorCommand 'Critical result) = ResumeDraft NativeLockWork
data instance SigningWork (WorkerCommand 'Critical result) = SigningWork Text PreparedPayment
data instance BroadcastWork (WorkerCommand 'Critical result) = BroadcastWork RecordedAttempt SigningReply RecordedAttempt PaymentObservation
data instance RebroadcastWork (OperatorCommand 'Critical result) = RebroadcastWork RecordedAttempt [(RecordedAttempt,NativeSigned)] Int64
data instance ReplacementDraftWork (OperatorCommand 'Critical result) = ReplacementDraftWork RecordedAttempt Amount Text
data instance ReplacementSigningWork (OperatorCommand 'Critical result) = ReplacementSigningWork Int64 Text
data instance RetryWork (OperatorCommand 'Critical result) = RetryWork RecordedAttempt SolanaSigned Text
data instance CancellationWork (OperatorCommand 'Critical result) = CancellationWork Text Int Text (Maybe (Text,Text,Bool))
data instance CancellationCommit (OperatorCommand 'Critical result) = CancellationCommit PreparedPayment Text Text [NP.Outpoint]
data instance OwnerFeeWork (WorkerCommand 'Critical result) = OwnerFeeWork CustomerSettings C.OwnerFeeRecipients Asset

instance OperatorOperations

instance Execution 'Operator 'Critical OperatorCommand where
  authorizeOperation SignerEvaluation{} _=reject "signer_context_forbidden"
  authorizeOperation WorkerEvaluation{} _=pure ()
  evaluateOperation SignerEvaluation{} _=reject "signer_context_forbidden"
  evaluateOperation (WorkerEvaluation environment) (OperatorDSL workflow)=fst <$> runOperatorFlow environment workflow VNil

instance Typeable result => OperatorService (OperatorCommand 'Critical result) where
  pauseService _ reason = operatorEffect True $ \(CriticalEnvironment _ _ _ _ _ _ writer) -> evalWrite writer (Pause reason)
  resumeService = F.step . Expand . ResumeWorkflow

instance CustodySteps (OperatorCommand 'Critical result) where
  custodyScope _ = F.step . Scoped OperatorGuard
  checkpointCustody _ = operatorEffect False backupDecisions
  observeCustody _ = operatorEffect False $ \environment -> evalWorker @'[WorkerObservation] environment observeChains
  reconcileCustodyStep _ = operatorEffect False $ \environment -> evalWorker @'[WorkerObservation] environment reconcileCustody

instance Typeable result => ResumeSteps (OperatorCommand 'Critical result) where
  checkResume _ = operatorEffect False $ \(CriticalEnvironment rpc settings _ _ _ reader _) -> do
    state<-evalRead reader ReadState
    require (ledgerPaused state) "pause_before_operator_action"
    N.verifyNativeBoundaryWith (N.nativeCall rpc $ nativeSettings settings)
  recoverResume _ = operatorEffect False recoverPending
  inspectResume _ = operatorEffect False $ \(CriticalEnvironment _ _ _ _ _ reader _) -> do
    ids<-evalRead reader PendingAttempts
    ResumeWork <$> mapM (evalRead reader . ReadAttempt) ids
  refreshResume _ (ResumeWork reviewed) = operatorEffect False $ \environment ->
    forM_ reviewed (refreshSource environment . recordedPayment)
  inspectResumeDraft _ = operatorEffect False $ \(CriticalEnvironment _ _ _ _ _ reader _) -> do
    nativeWork<-evalRead reader ReadNativeLockWork
    pure $ case nativeWork of
      Just work | null(lockAttempts work) && not(lockCancelling work)
        && preparedDraft(lockPreparation work)/=Nothing -> Just (ResumeDraft work)
      _ -> Nothing
  restoreResumeDraft _ (ResumeDraft work) = operatorEffect False $ \(CriticalEnvironment rpc settings config _ _ _ _) -> do
    let native=nativeSettings settings
    _<-restoreNativeWork (N.nativeCall rpc native) native config (Just work)
    pure ()
  finishResume _ (ResumeWork reviewed) unsigned = operatorEffect False $ \(CriticalEnvironment _ settings _ _ _ _ writer) -> do
    now<-floor <$> getPOSIXTime
    let native=nativeSettings settings
    evalWrite writer (ResumeLedger now [("Native",N.nativeCheckpointHash native),("Solana",tokenOrigin settings),("SolanaOperating",operatingOrigin settings)]
      reviewed ((\(ResumeDraft work)->work) <$> unsigned))

instance Typeable result => OperatorRepair (OperatorCommand 'Critical result) where
  repairCompletedOrder _ order = operatorEffect False $ \(CriticalEnvironment _ _ _ _ _ _ writer) -> do
    now<-floor <$> getPOSIXTime
    evalWrite writer (RepairCompletedOrderView now order)
  retrySolanaPayment value txid reason = F.step $ Expand (RetryWorkflow value txid reason)
  cancelPreparation value identifier generation reason = F.step $ Expand (CancellationWorkflow value identifier generation reason)
  refundDeposit _ receipt = operatorEffect False $ \(CriticalEnvironment _ _ _ _ _ _ writer) -> do
    now<-floor <$> getPOSIXTime
    evalWrite writer (AuthorizeRefund now receipt)

instance RetrySteps (OperatorCommand 'Critical result) where
  inspectRetry _ txid reason = operatorEffect False $ \(CriticalEnvironment rpc settings config _ _ reader _) -> do
    let native=nativeSettings settings
    require (not(T.null $ T.strip reason) && T.length reason<=512) "invalid_retry_approval"
    previous<-evalRead reader (ReadRetryApproval txid)
    case previous of
      Just old->require (old==reason) "retry_approval_conflict" >> pure Nothing
      Nothing->do
        state<-evalRead reader ReadState
        require (ledgerPaused state) "pause_before_operator_action"
        saved<-evalRead reader (ReadAttempt txid)
        expired<-evalRead reader (ReadSolanaExpiry txid)
        require (recordedChain saved=="Solana" && recordedState saved=="review" && expired/=Nothing) "solana_retry_not_expected"
        prepared<-evalRead reader (ReadRecordedPreparation txid)
        verifySignedAttempt (N.nativeCall rpc native) (N.profile native) config prepared (recordedSigned saved)
        signed<-decode (signedPolicy $ recordedSigned saved)
        pure (Just $ RetryWork saved signed reason)
  refreshRetrySource _ (RetryWork saved _ _) = operatorEffect False $ \environment -> refreshSource environment (recordedPayment saved)
  proveRetryExpired _ (RetryWork _ signed _) = operatorEffect False $ \environment ->
    expiry environment signed >>= maybe (reject "solana_expiry_not_proven") pure
  commitRetryApproval _ (RetryWork saved _ reason) proof = operatorEffect False $ \(CriticalEnvironment _ _ _ _ _ _ writer) -> do
    now<-floor <$> getPOSIXTime
    evalWrite writer (ApproveSolanaRetry now saved reason proof)

instance CancellationSteps (OperatorCommand 'Critical result) where
  inspectCancellation _ identifier generation reason = operatorEffect False $ \(CriticalEnvironment _ _ _ _ _ reader _) -> do
    require (generation>=0 && generation<8 && not(T.null $ T.strip reason) && T.length reason<=512) "invalid_preparation_cancellation"
    state<-evalRead reader ReadState
    require (ledgerPaused state) "pause_before_operator_action"
    previous<-evalRead reader (ReadCancellation identifier generation)
    forM_ previous $ \(old,_,_)->require (old==reason) "preparation_cancellation_conflict"
    case previous of
      Just (_,_,True)->pure Nothing
      _->pure (Just $ CancellationWork identifier generation reason previous)
  refreshCancellationSource _ (CancellationWork identifier generation _ _) = operatorEffect False $ \environment@(CriticalEnvironment rpc settings _ _ _ reader _) -> do
    unsigned<-evalRead reader (ReadUnsignedPreparation identifier)
    require (preparedGeneration unsigned==generation) "preparation_generation_changed"
    case paymentAsset(savedPayment $ preparedView unsigned) of
      Native->N.nativeIdentity rpc (nativeSettings settings) >> pure ()
      Wrapped->S.solanaIdentity rpc (solanaSettings settings) >> pure ()
      Sol->reject "invalid_payout_asset"
    refreshSource environment identifier
  beginCancellation _ (CancellationWork identifier generation reason previous) = operatorEffect False $ \(CriticalEnvironment rpc settings config _ _ reader writer) -> do
    let native=nativeSettings settings
    prepared<-evalRead reader (ReadUnsignedPreparation identifier)
    require (preparedGeneration prepared==generation) "preparation_generation_changed"
    (points,cleanup)<-cancellationPlan (N.nativeCall rpc native) (N.profile native) config prepared
    forM_ previous $ \(_,plan,_)->require (plan==cleanup) "preparation_cancellation_conflict"
    now<-floor <$> getPOSIXTime
    evalWrite writer (BeginCancellation prepared now reason cleanup)
    pure (CancellationCommit prepared reason cleanup points)
  releaseCancellation _ (CancellationCommit prepared _ _ points) = operatorEffect False $ \(CriticalEnvironment rpc settings _ _ _ _ _) ->
    when (paymentAsset(savedPayment $ preparedView prepared)==Native) $
      releaseNativeInputLocks (N.nativeCall rpc $ nativeSettings settings) points
  finishCancellation _ (CancellationCommit prepared reason cleanup _) = operatorEffect False $ \(CriticalEnvironment _ _ _ _ _ _ writer) ->
    evalWrite writer (FinishCancellation prepared reason cleanup)

instance Typeable result => OperatorNative (OperatorCommand 'Critical result) where
  rebroadcastNative value txid anchor reason = F.step $ Expand (RebroadcastWorkflow value txid anchor reason)
  draftNativeReplacement value parent fee reason = F.step $ Expand (ReplacementDraftWorkflow value parent fee reason)
  signNativeReplacement value decision = F.step $ Expand (ReplacementSigningWorkflow value decision)
  cancelNativeReplacement _ decision reason = operatorEffect False $ \(CriticalEnvironment _ _ _ _ _ _ writer) ->
    evalWrite writer (CancelReplacementDraft decision reason)

instance Typeable result => NativeSteps (OperatorCommand 'Critical result) where
  inspectRebroadcast _ txid anchor reason = operatorEffect False $ \environment@(CriticalEnvironment rpc settings config _ _ reader writer) -> do
    let native=nativeSettings settings
    require (NP.transactionId txid && anchor>0 && not(T.null $ T.strip reason) && T.length reason<=512) "invalid_native_rebroadcast_approval"
    (saved,family,current)<-evalRead reader (ReadNativeRebroadcastContext txid)
    previous<-evalRead reader (ReadNativeRebroadcastDecision txid anchor reason)
    require (current==maybe anchor id previous) "native_rebroadcast_review_changed"
    before<-missingNativeFamily rpc native config reader saved family
    refreshSource environment (recordedPayment saved)
    block<-RPC.fieldValue "hash" (NP.familyPosition before) :: IO Text
    let proof=object ["transaction" .= txid,"bytesHash" .= digest(TE.encodeUtf8 $ signedBytes $ recordedSigned saved)
          ,"nodeBlock" .= block,"family" .= map (signedId.recordedSigned.fst) family,"noActiveFamilyPayment" .= True]
    approved<-maybe (evalWrite writer $ RecordNativeRebroadcast saved (map fst family) anchor reason proof) pure previous
    pure (RebroadcastWork saved family approved)
  sendRebroadcast _ (RebroadcastWork saved family approved) = operatorEffect False $ \environment@(CriticalEnvironment rpc settings config _ _ reader writer) -> do
    let native=nativeSettings settings; txid=signedId $ recordedSigned saved
    -- Backup may be slow: source and family must be rechecked before authorization.
    refreshSource environment (recordedPayment saved)
    _<-missingNativeFamily rpc native config reader saved family
    authorized<-evalWrite writer (AuthorizeNativeRebroadcast saved (map fst family) approved)
    actual<-N.nativeCall rpc native True "sendrawtransaction" [toJSON $ signedBytes $ recordedSigned authorized] >>= parseValue parseJSON
    require (actual==txid) "native_broadcast_identity_mismatch"
    pure txid
  inspectReplacementDraft _ parent fee reason = operatorEffect False $ \(CriticalEnvironment _ _ _ _ _ reader _) -> do
    require (NP.transactionId parent && units fee>0 && not(T.null $ T.strip reason) && T.length reason<=512) "invalid_native_replacement_decision"
    state<-evalRead reader ReadState
    require (ledgerPaused state) "pause_before_operator_action"
    previous<-evalRead reader (ReadReplacementDecision parent fee reason)
    case previous of
      Just (decision,cancelled)->require (not cancelled) "native_replacement_cancelled" >> pure (Left decision)
      Nothing->do
        saved<-evalRead reader (ReadAttempt parent)
        require (recordedChain saved=="Native") "native_replacement_not_expected"
        pure (Right $ ReplacementDraftWork saved fee reason)
  refreshReplacementDraft _ (ReplacementDraftWork saved _ _) = operatorEffect False $ \environment -> refreshSource environment (recordedPayment saved)
  issueReplacementDraft _ (ReplacementDraftWork saved fee reason) = operatorEffect False $ \environment@(CriticalEnvironment _ _ config _ _ reader writer) -> do
    let parent=signedId $ recordedSigned saved
    now<-floor <$> getPOSIXTime
    family<-evalRead reader (ReadReplacementDraftContext now parent fee)
    draft<-draftOutput <$> evaluateSigning environment (DraftSigning $ DraftReplacement (H.fingerprint config) parent fee)
    either reject pure (NP.validateNativeReplacementDraft (map snd family) fee draft)
    later<-floor <$> getPOSIXTime
    evalWrite writer (SaveReplacementDraft later saved draft reason)
  inspectReplacementSigning _ decision = operatorEffect False $ \(CriticalEnvironment _ _ _ _ _ reader _) -> do
    require (decision>0) "invalid_native_replacement_decision"
    state<-evalRead reader ReadState
    require (ledgerPaused state) "pause_before_operator_action"
    previous<-evalRead reader (ReadReplacementMember decision)
    case previous of
      Just saved->pure (Left $ signedId $ recordedSigned saved)
      Nothing->Right . ReplacementSigningWork decision <$> evalRead reader (ReadReplacementPayment decision)
  refreshReplacementSigning _ (ReplacementSigningWork _ identifier) = operatorEffect False $ \environment -> refreshSource environment identifier
  issueReplacementSigning _ (ReplacementSigningWork decision _) = operatorEffect False $ \environment@(CriticalEnvironment rpc settings config _ _ reader writer) -> do
    let native=nativeSettings settings
    now<-floor <$> getPOSIXTime
    (family,draft)<-evalRead reader (ReadReplacementSigning now decision)
    wire<-replacementOutput <$> evaluateSigning environment (ReplacementSigning $ SignReplacement (H.fingerprint config) decision)
    signed<-decode (signedPolicy wire)
    require (signedId wire==NP.nativeTxid(NP.signedNativeTransaction signed)
      && signedBytes wire==NP.signedNativeBytes signed
      && commonInput wire==commonInput(recordedSigned $ fst $ last family)) "native_replacement_signature_conflict"
    either reject pure (NP.validateNativeFamily $ map snd family<>[signed])
    require (NP.sameNativeTemplate (NP.draftTransaction draft) (NP.signedNativeTransaction signed)
      && NP.draftFee draft==NP.signedNativeFee signed
      && NP.sameNativePrevouts (NP.draftPrevouts draft) (NP.signedNativePrevouts signed)) "native_replacement_signed_template_changed"
    actual<-N.nativeCall rpc native False "decoderawtransaction" [toJSON $ signedBytes wire] >>= either reject pure . NP.decodeNativeTx
    require (actual==NP.signedNativeTransaction signed) "native_signed_bytes_mismatch"
    later<-floor <$> getPOSIXTime
    saved<-evalWrite writer (RecordReplacement later decision family signed)
    pure (signedId $ recordedSigned saved)

missingNativeFamily :: Manager -> N.NativeSettings -> H.SolanaPolicy -> Reader -> RecordedAttempt -> [(RecordedAttempt,NativeSigned)] -> IO NP.NativeFamilyView
missingNativeFamily rpc native config reader saved family = do
  (actual,view)<-readSavedNativeFamily (N.nativeCall rpc native) native config reader (recordedPayment saved)
  require (actual==family) "native_replacement_family_changed"
  require (NP.familyActive view==Nothing) "native_rebroadcast_payment_not_missing"
  pure view

instance OperatorSource (OperatorCommand 'Critical result) where
  coverLostSource _ receipt recovery capital earned reason = operatorEffect False $ \environment@(CriticalEnvironment rpc settings config _ _ reader writer) -> guarded environment $ do
    require (recovery>0 && not(T.null $ T.strip reason) && T.length reason<=512) "invalid_source_loss_cover"
    state<-evalRead reader ReadState
    require (ledgerPaused state) "pause_before_operator_action"
    previous<-evalRead reader (ReadLossCover receipt recovery)
    case previous of
      Just old->require (old==(capital,earned,reason)) "source_loss_cover_conflict"
      Nothing->do
        source<-evalRead reader (ReadSource receipt)
        proof<-proveMissing environment source
        custody<-inspectLossCustody rpc settings config reader
        now<-floor <$> getPOSIXTime
        evalWrite writer (CoverSourceLoss source recovery now capital earned reason proof custody)
  approveCovered _ key recovery reason = operatorEffect False $ \environment@(CriticalEnvironment _ _ _ _ _ reader writer) -> guarded environment $ do
    require (recovery>0 && not(T.null $ T.strip reason) && T.length reason<=512) "invalid_source_approval"
    state<-evalRead reader ReadState
    require (ledgerPaused state) "pause_before_operator_action"
    previous<-evalRead reader (ReadCoveredApproval key recovery)
    case previous of
      Just old->require (old==reason) "source_approval_conflict"
      Nothing->do
        evalRead reader (CheckCoveredSource key recovery)
        binding<-evalRead reader (ReadPaymentSource key) >>= maybe (reject "source_approval_not_expected") pure
        proof<-proveMissing environment (W.sourceDeposit binding)
        reconcilePending environment >>= mapM_ (either throwIO pure)
        evalWorker @'[WorkerObservation] environment reconcileCustody
        now<-floor <$> getPOSIXTime
        evalWrite writer (ApproveCoveredSource now key recovery reason proof)
  restoreSource _ key restoration reason = operatorEffect False $ \environment@(CriticalEnvironment _ _ _ _ _ reader writer) -> guarded environment $ do
    require (restoration>0 && not(T.null $ T.strip reason) && T.length reason<=512) "invalid_source_approval"
    state<-evalRead reader ReadState
    require (ledgerPaused state) "pause_before_operator_action"
    previous<-evalRead reader (ReadSourceApproval key restoration)
    case previous of
      Just old->require (old==reason) "source_approval_conflict"
      Nothing->do
        evalRead reader (CheckSourceRestoration key restoration)
        refreshSource environment key
        reconcilePending environment >>= mapM_ (either throwIO pure)
        evalWorker @'[WorkerObservation] environment reconcileCustody
        now<-floor <$> getPOSIXTime
        evalWrite writer (ApproveSourceRestoration now key restoration reason)

instance OperatorTreasury (OperatorCommand 'Critical result) where
  classifySpend _ chain key reason = operatorEffect False $ \(CriticalEnvironment _ _ _ _ _ _ writer) -> evalWrite writer (ClassifyTreasurySpend chain key reason)
  initializeOperating _ receipt signature reason = operatorEffect False $ \environment@(CriticalEnvironment rpc settings config _ _ reader writer) -> do
    let native=nativeSettings settings
        solana=solanaSettings settings
    require (not(T.null $ T.strip reason) && T.length reason<=512) "invalid_initial_funding_reason"
    replay<-evalRead reader (ReadInitialFundingReplay receipt signature reason)
    case replay of
      Just sequenceNo->pure sequenceNo
      Nothing->do
        state<-evalRead reader ReadState
        require (ledgerPaused state) "initial_funding_requires_pause"
        now<-floor <$> getPOSIXTime
        expected<-evalRead reader (ReadInitialFundingContext now)
        independent<-maybe (reject "independent_rpc_required") pure (S.solanaVerifierRpc solana)
        let primary=S.solanaCall rpc solana
            verify=RPC.rpc rpc independent Nothing
            origins=[("Native",N.nativeCheckpointHash native),("Solana",tokenOrigin settings),("SolanaOperating",operatingOrigin settings)]
        S.solanaGenesisWith primary (Just verify) solana
        proofs<-forM [primary,verify] $ \call->do
          statuses<-call "getSignatureStatuses" [toJSON [signature],object ["searchTransactionHistory" .= True]] >>= RPC.fieldValue "value"
          status<-case statuses of [value]->pure value; _->reject "invalid_initial_funding_status"
          raw<-call "getTransaction" [toJSON signature,object ["encoding" .= ("base64"::Text),"commitment" .= ("finalized"::Text),"maxSupportedTransactionVersion" .= (0::Int)]]
          encoded<-RPC.fieldValue "transaction" raw
          bytes<-case encoded of [value,"base64"]->pure value; _->reject "invalid_initial_funding_transaction"
          outcome<-either (const $ reject "initial_funding_not_finalized") pure (Admin.classifyStatus bytes status raw True)
          require (outcome==Admin.Finalized) "initial_funding_not_finalized"
          transaction<-S.finalizedTransactionWith call signature
          proof<-either reject pure (SD.verifyInitialAta signature (H.custodyOwner config) (H.mint config) (H.custodyAta config)
            (H.maxSolFee config) (H.maxSolAccountRent config) bytes transaction)
          rawSlot<-RPC.fieldValue "slot" raw
          statusSlot<-RPC.fieldValue "slot" status
          require (rawSlot==SD.initialSlot proof && statusSlot==rawSlot) "initial_funding_slot_mismatch"
          pure proof
        proof<-case proofs of [first,second] | first==second->pure first; _->reject "initial_funding_provider_disagreement"
        checkedAt<-floor <$> getPOSIXTime
        evalWrite writer (InitializeSolanaOperating checkedAt expected origins receipt proof reason)
  allocateReceipt _ receipt split reason = operatorEffect False $ \(CriticalEnvironment _ _ _ _ _ _ writer) -> do
    now<-floor <$> getPOSIXTime
    evalWrite writer (AllocateTreasury now receipt split reason)
  withdrawFees _ key asset quantity recipient reason = operatorEffect False $ \environment@(CriticalEnvironment rpc settings config _ _ reader writer) -> guarded environment $ do
    let native=nativeSettings settings; solana=solanaSettings settings
    c<-customer environment
    require (T.length key==64 && T.all (`elem` ("0123456789abcdef"::String)) key
      && not(T.null $ T.strip reason) && T.length reason<=512
      && units quantity>0 && quantity<=maximumWithdrawal(admissionLimits $ customerPolicy c)
      && asset `elem` [Native,Wrapped]) "invalid_fee_withdrawal"
    previous<-evalRead reader (ReadWithdrawal key)
    case previous of
      Just _->pure () -- Store checks exact immutable replay before returning it.
      Nothing->do
        state<-evalRead reader ReadState
        require (ledgerPaused state) "pause_before_operator_action"
        case asset of
          Native->do
            _<-N.nativeIdentity rpc native
            previewNativePayment (N.nativeCall rpc native) (N.profile native) (defaultNativeDepth settings)
              (W.savedNativeFee $ W.paymentLimits $ executionTerms $ customerPolicy c) recipient quantity
          Wrapped->do
            _<-S.solanaIdentity rpc solana
            checkSolanaPayoutWith (S.solanaCall rpc solana) (H.invokeUnsignedHelper (unsignedSdk c) config) config recipient quantity
          Sol->reject "invalid_payout_asset"
        evalWorker @'[WorkerObservation] environment reconcileCustody
    now<-floor <$> getPOSIXTime
    paymentId . withdrawalPayment <$> evalWrite writer (ReserveFees now key asset quantity recipient reason)
  cancelFeeWithdrawal _ key reason = operatorEffect False $ \(CriticalEnvironment _ _ _ _ _ reader writer) -> do
    state<-evalRead reader ReadState
    require (ledgerPaused state) "pause_before_operator_action"
    paymentId . withdrawalPayment <$> evalWrite writer (CancelFees key reason)

instance Execution 'Worker 'Critical WorkerCommand where
  authorizeOperation SignerEvaluation{} _=reject "signer_context_forbidden"
  authorizeOperation WorkerEvaluation{} _=pure ()
  evaluateOperation SignerEvaluation{} _=reject "signer_context_forbidden"
  evaluateOperation (WorkerEvaluation environment) (WorkerDSL workflow)=fst <$> runWorkerFlow environment workflow VNil

instance WorkerBackup (WorkerCommand 'Critical result) where
  checkpointBackup _ minimumSequence = workerEffect False $ \environment@(CriticalEnvironment _ _ _ _ _ reader _) -> guarded environment $ do
    before<-evalRead reader ReadState
    require (minimumSequence>=0 && minimumSequence<=ledgerSequence before) "invalid_custody_checkpoint"
    when (ledgerBackup before<minimumSequence) $ checkpoint environment minimumSequence before >> pure ()
  checkpointForUpgrade _ = workerEffect False $ \environment@(CriticalEnvironment _ _ _ _ _ reader _) -> guarded environment $ do
    before<-evalRead reader ReadState
    require (ledgerPaused before) "pause_before_upgrade_checkpoint"
    checkpoint environment (ledgerSequence before) before

  checkpointPending _ = workerStep False $ \environment (value :& VNil) -> do
    backupDecisions environment
    pure ((),BackupCovered value :& VNil)

instance WorkerObservation (WorkerCommand 'Critical result) where
  observeChains _ = workerEffect True $ \(CriticalEnvironment rpc settings _ _ _ reader writer) -> observeOnce rpc settings reader writer
  reconcileCustody _ = workerEffect True $ \(CriticalEnvironment rpc settings config _ _ reader writer) -> Reconciliation.reconcileCustody rpc settings config reader writer

  inspectPayout _ identifier = workerStep False $ \environment@(CriticalEnvironment _ _ _ _ _ reader _) VNil -> do
    freshIntake environment
    (_,_,attempts) <- evalRead reader (ReadPaymentWork identifier)
    pure (attempts,identifier :& VNil)

instance WorkerRecovery (WorkerCommand 'Critical result) where
  recoverNativeSettlements _ = workerEffect True $ \environment@(CriticalEnvironment rpc settings config _ _ reader writer) -> guarded environment $ do
    let native=nativeSettings settings
    candidates<-evalRead reader NativeSettlementCandidates
    outcomes<-forM candidates $ \saved->tryBridge $ do
      inspected<-tryBridge $ do
        (family,view)<-readSavedNativeFamily (N.nativeCall rpc native) native config reader (recordedPayment saved)
        require (saved `elem` map fst family) "native_settlement_changed"
        active<-activeNativeMember family view
        case active of
          Nothing->pure $ NativeUnavailable "native_settled_payment_unseen"
          Just (winner,signed,depth,proof)->do
            outcome<-nativeConfirmation (N.nativeCall rpc native) signed depth proof
            case outcome of
              PaymentWaiting->pure NativeConfirming
              PaymentConfirmed costs evidence->pure $
                if winner==saved then NativeReconfirmed costs evidence
                else NativeWinnerChanged (map fst family) (signedId $ recordedSigned winner) costs evidence
              _->reject "unexpected_native_payment_failure"
      let result=either (\(BridgeError code)->NativeUnavailable code) id inspected
      committed<-tryBridge (evalWrite writer $ RecordNativeSettlement saved result)
      case committed of
        Right ()->pure ()
        Left (BridgeError code)->evalWrite writer (RecordNativeSettlement saved $ NativeUnavailable code)
    mapM_ (either throwIO pure) outcomes
  recoverNativeSources _ = workerEffect True $ \(CriticalEnvironment rpc settings config _ _ reader writer) -> do
    let native=nativeSettings settings
    let recover after failure=do
          sources<-evalRead reader (NativeSourcePage after)
          outcomes<-forM sources $ \source->tryBridge $ do
            result<-tryBridge $ do
              _<-N.nativeIdentity rpc native
              (binding,evidence)<-evalRead reader (ReadNativeSourceInspection $ W.depositId source)
              inspectNativeSource (N.nativeCall rpc native) (N.readNativeTransaction native) native (defaultNativeDepth settings) (H.fingerprint config) source binding evidence
            let unavailable code=W.SourceUnavailable $ object ["reason" .= code]
                checked=either (\(BridgeError code)->unavailable code) id result
            recorded<-tryBridge (evalWrite writer $ RecordSourceCheck source checked)
            case recorded of
              Right ()->pure ()
              Left (BridgeError code)->evalWrite writer (RecordSourceCheck source $ unavailable code)
          let failed=case failure of
                Just err->Just err
                Nothing->case [err | Left err<-outcomes] of err:_->Just err; []->Nothing
          -- Do not retain a lazy chain of successful pages until sweep EOF.
          failed `seq` case reverse sources of
            []->maybe (pure ()) throwIO failed
            source:_->recover (Just $ W.depositId source) failed
    recover Nothing Nothing
  recoverNativeLocks _ = workerEffect True $ \environment@(CriticalEnvironment rpc settings config _ _ reader writer) -> guarded environment $ do
    let native=nativeSettings settings
    _<-N.nativeIdentity rpc native
    _<-N.nativeWalletInfoWith (N.nativeCall rpc native) native
    saved<-evalRead reader ReadNativeLockWork
    restored<-restoreNativeWork (N.nativeCall rpc native) native config saved
    when (restored>0) $ forM_ saved $ \work->evalWrite writer (RecordNativeLockRestore work restored)
  reconcilePayment _ txid = workerEffect True $ \environment@(CriticalEnvironment _ _ _ _ _ reader _) -> guarded environment $ do
    recorded<-evalRead reader (ReadAttempt txid)
    retired<-evalRead reader (ReadSolanaExpiry txid)
    payment<-evalRead reader (ReadPayment $ recordedPayment recorded)
    if savedStatus payment==PaymentPaid || recordedState recorded `elem` ["settled","failed"] || retired/=Nothing then pure () else do
      (current,reply)<-loadActive environment txid
      (winner,outcome)<-observeAttempt environment current reply
      recordOutcome environment winner outcome

  reusePayout _ attempts = workerStep False $ \(CriticalEnvironment _ _ _ _ _ reader _) (identifier :& VNil) -> do
    txid <- case attempts of
      [saved] -> pure saved
      _ -> do
        family <- evalRead reader (ReadNativeFamily identifier)
        pure (signedId $ recordedSigned $ fst $ last family)
    pure ((),SignedPayout txid :& VNil)

instance WorkerPreparation (WorkerCommand 'Critical result) where
  prepareOutgoing _ = workerStep False $ \environment@(CriticalEnvironment rpc settings config _ _ reader writer) (identifier :& VNil) -> do
    now<-floor <$> getPOSIXTime
    evalWrite writer (AdmitPayoutRounds now)
    -- Waiting for a round is normal, before RPC and before exception-driven pause.
    evalRead reader (CheckPayoutAdmission identifier)
    guarded environment $ do
      let native=nativeSettings settings; solana=solanaSettings settings
      evalRead reader (CheckIntake now)
      _<-N.nativeIdentity rpc native
      _<-S.solanaIdentity rpc solana
      refreshSource environment identifier
      freshIntake environment
      -- Plan RPC and source updates may age or invalidate custody before commit.
      _<-prepareUnsigned (freshIntake environment >> floor <$> getPOSIXTime) (N.nativeCall rpc native) (S.solanaCall rpc solana)
        (N.profile native) config reader writer identifier
      pure ((),PreparedPayout identifier :& VNil)

instance Typeable result => WorkerSigning (WorkerCommand 'Critical result) where
  signPreparedPayment = F.step . Expand . SigningWorkflow

instance Typeable result => SigningSteps (WorkerCommand 'Critical result) where
  signingScope _ = F.step . Scoped SigningGuard
  inspectSigning _ = workerStep False $ \(CriticalEnvironment _ _ _ _ _ reader _) (BackupCovered (PreparedPayout identifier) :& VNil) -> do
    (_,saved,attempts)<-evalRead reader (ReadPaymentWork identifier)
    prepared<-maybe (reject "payment_not_prepared") pure saved
    previous<-case attempts of
      []->pure Nothing
      [txid]->pure (Just txid)
      _->reject "payment_requires_recovery"
    pure (previous,SigningWork identifier prepared :& VNil)
  reuseSignature _ txid = workerStep False $ \(CriticalEnvironment rpc settings config _ _ reader _) (SigningWork identifier prepared :& VNil) -> do
    let native=nativeSettings settings
    recorded<-evalRead reader (ReadAttempt txid)
    require (recordedPayment recorded==identifier && recordedGeneration recorded==preparedGeneration prepared) "payment_requires_recovery"
    verifySignedAttempt (N.nativeCall rpc native) (N.profile native) config prepared (recordedSigned recorded)
    pure (txid,SignedPayout txid :& VNil)
  issueSignature _ = workerStep False $ \environment@(CriticalEnvironment rpc settings config _ _ reader writer) (SigningWork identifier prepared :& VNil) -> do
    let native=nativeSettings settings
    _<-resolveSigningPlan (N.profile native) config prepared
    refreshSource environment identifier
    freshIntake environment
    now<-floor <$> getPOSIXTime
    decision<-evalRead reader (ReadSigningDecision now identifier $ preparedGeneration prepared)
    require (decision==prepared) "preparation_changed"
    signed<-preparedOutput <$> evaluateSigning environment (PreparedSigning $ SignPrepared (H.fingerprint config) identifier $ preparedGeneration prepared)
    verifySignedAttempt (N.nativeCall rpc native) (N.profile native) config prepared signed
    recorded<-evalWrite writer (RecordAttempt prepared signed)
    let txid=signedId $ recordedSigned recorded
    pure (txid,SignedPayout txid :& VNil)

instance WorkerQueue (WorkerCommand 'Critical result) where
  queuePayment _ = workerStep False $ \environment@(CriticalEnvironment _ _ _ _ _ _ writer) (SignedPayout txid :& VNil) -> guarded environment $ do
    (recorded,_)<-loadActive environment txid
    refreshSource environment (recordedPayment recorded)
    freshIntake environment
    now<-floor <$> getPOSIXTime
    sequenceNo <- evalWrite writer (MarkBroadcast now txid)
    pure (sequenceNo,QueuedPayout txid :& VNil)

instance Typeable result => WorkerBroadcast (WorkerCommand 'Critical result) where
  broadcastPayment = F.step . Expand . BroadcastWorkflow

instance Typeable result => BroadcastSteps (WorkerCommand 'Critical result) where
  broadcastScope _ = F.step . Scoped BroadcastGuard
  inspectBroadcast _ = workerStep False $ \environment (BackupCovered (QueuedPayout txid) :& VNil) -> do
    (recorded,reply)<-loadActive environment txid
    require (recordedState recorded=="broadcast_intent") "broadcast_intent_required"
    (observedAttempt,observed)<-observeAttempt environment recorded reply
    pure (case observed of PaymentUnseen->True; _->False,BroadcastWork recorded reply observedAttempt observed :& VNil)
  sendUnseenPayment _ = workerStep False $ \environment@(CriticalEnvironment rpc settings _ _ _ _ writer) (BroadcastWork recorded reply _ observed :& VNil) -> do
    require (case observed of PaymentUnseen->True; _->False) "payment_already_observed"
    let native=nativeSettings settings; solana=solanaSettings settings; txid=signedId $ recordedSigned recorded
    refreshSource environment (recordedPayment recorded)
    freshIntake environment
    case reply of
      NativeReply signed->checkNativeAcceptance (N.nativeCall rpc native) signed
      SolanaReply signed->checkBlockhashForSend (S.solanaCall rpc solana) (solPlanRecent $ signedSolanaPlan signed)
    now<-floor <$> getPOSIXTime
    authorized<-evalWrite writer (AuthorizeSend now txid)
    require (authorized==recorded) "saved_payment_changed"
    actual<-case reply of
      NativeReply _->N.nativeCall rpc native True "sendrawtransaction" [toJSON $ signedBytes $ recordedSigned authorized] >>= parseValue parseJSON
      SolanaReply _->S.solanaCall rpc solana "sendTransaction" [toJSON $ signedBytes $ recordedSigned authorized,object
        ["encoding" .= ("base64"::Text),"skipPreflight" .= False,"preflightCommitment" .= ("confirmed"::Text),"maxRetries" .= (0::Int)]] >>= parseValue parseJSON
    require (actual==txid) "broadcast_identifier_mismatch"
    pure ((),VNil)
  recordObservedPayment _ = workerStep False $ \environment (BroadcastWork _ _ winner observed :& VNil) -> do
    recordOutcome environment winner observed
    pure ((),VNil)

instance Typeable result => WorkerCycle (WorkerCommand 'Critical result) where
  runWorkerCycle = F.step . Expand . CycleWorkflow

instance Typeable result => CycleSteps (WorkerCommand 'Critical result) where
  cycleScope _ = F.step . Scoped CycleGuard
  recoverCycle _ = workerEffect True recoverPending
  cycleCanPay _ = workerEffect True $ \environment@(CriticalEnvironment _ _ _ _ _ reader _) -> do
    state<-evalRead reader ReadState
    pure (paying environment && not(ledgerPaused state))
  cycleCandidates _ = workerEffect False $ \(CriticalEnvironment _ _ _ _ _ reader writer) -> do
    now<-floor <$> getPOSIXTime
    evalWrite writer (AdmitPayoutRounds now)
    evalRead reader PaymentCandidates
  cyclePayout value identifier = F.step $ Expand (PayoutWorkflow value identifier)
  cycleOwnerFees = F.step . Expand . OwnerFeesWorkflow

-- This optional reservation never signs. All resulting work uses the ordinary
-- payout pipeline, and a commit ends this cycle so custody can be reconciled.
instance OwnerFeeSteps (WorkerCommand 'Critical result) where
  ownerFeeCandidates _ = workerEffect False $ \(CriticalEnvironment _ _ config configured _ reader _) ->
    case configured of
      Just c | Just recipients<-ownerFeeRecipients c->do
        priority<-evalRead reader ReadAutomaticFeePriority
        nativeWork<-evalRead reader ReadNativeLockWork
        -- Never contest active native inputs. Saved history determines priority.
        -- A self destination retains earned fees; it is not a withdrawal.
        pure [OwnerFeeWork c recipients asset | asset<-priority,asset/=Native || nativeWork==Nothing
          ,asset/=Wrapped || C.solanaOwner recipients/=H.custodyOwner config]
      _->pure []
  reserveOwnerFee _ (OwnerFeeWork c recipients asset) = workerEffect False $ \environment@(CriticalEnvironment rpc settings config _ _ reader writer) -> do
    let policy=customerPolicy c
        threshold=if asset==Native then W.nativePayoutThreshold (payoutPolicy policy)
          else W.wrappedPayoutThreshold (payoutPolicy policy)
    candidate<-evalRead reader (ReadAutomaticFeeAmount asset threshold $ maximumWithdrawal $ admissionLimits policy)
    case candidate of
      Nothing->pure False
      Just quantity->do
        freshIntake environment
        outcome<-tryBridge $ do
          recipient<-case asset of
            Native->do
              let native=nativeSettings settings; call=N.nativeCall rpc native
              _<-N.nativeIdentity rpc native
              address<-N.ownerAddressWith call (N.profile native) (C.nativeOwnerXpub recipients)
              previewNativePayment call (N.profile native) (defaultNativeDepth settings)
                (W.savedNativeFee $ W.paymentLimits $ executionTerms policy) address quantity
              pure address
            Wrapped->do
              _<-S.solanaIdentity rpc (solanaSettings settings)
              let address=C.solanaOwner recipients
              checkSolanaPayoutWith (S.solanaCall rpc $ solanaSettings settings)
                (H.invokeUnsignedHelper (unsignedSdk c) config) config address quantity
              pure address
            Sol->reject "invalid_payout_asset"
          checkedAt<-floor <$> getPOSIXTime
          saved<-evalWrite writer (ReserveAutomaticFees checkedAt asset recipient)
          pure saved
        case outcome of
          Right (Just _)->pure True
          Right Nothing->pure False
          -- Native ownership is resolved by the node. Keep these fees earned,
          -- with no reservation or transfer, when its destination is custody.
          Left (BridgeError "bridge_owned_destination") | asset==Native->pure False
          Left (BridgeError code) | code `elem` ["native_admission_funds_unavailable","native_fee_budget_exceeded",
            "insufficient_operating_sol","insufficient_custody_tokens"]->pure False
          Left failure->throwIO failure

checkpoint :: CriticalEnvironment -> Int64 -> LedgerState -> IO W.BackupReceipt
checkpoint environment@(CriticalEnvironment _ _ config _ _ reader writer) minimumSequence before=do
  receipt<-checkpointOutput <$> evaluateSigning environment
    (CheckpointSigning $ CheckpointCustody (H.fingerprint config) minimumSequence)
  let hash value=T.length value==64 && T.all (`elem` ("0123456789abcdef"::String)) value
  require (W.receiptIdentity receipt==H.fingerprint config && W.receiptSequence receipt==ledgerSequence before
    && hash (W.receiptSnapshot receipt) && hash (W.receiptArchiveHash receipt)) "invalid_custody_checkpoint_receipt"
  after<-evalRead reader ReadState
  require (ledgerSequence after==ledgerSequence before) "custody_backup_changed"
  evalWrite writer (AcknowledgeBackup (W.receiptIdentity receipt) (W.receiptSequence receipt) (W.receiptSnapshot receipt))
  pure receipt

freshIntake :: CriticalEnvironment -> IO ()
freshIntake environment@(CriticalEnvironment _ _ _ _ _ reader _)=refresh 2
 where
  -- Custody RPC can age previously fresh scans; permit one further refresh.
  refresh :: Int -> IO ()
  refresh remaining=do
    now<-floor <$> getPOSIXTime
    result<-tryBridge (evalRead reader $ CheckIntake now)
    case result of
      Left (BridgeError code) | remaining>0 && code `elem` ["scanners_not_fresh","custody_not_reconciled"]->do
        when (code=="scanners_not_fresh") (evalWorker @'[WorkerObservation] environment observeChains)
        evalWorker @'[WorkerObservation] environment reconcileCustody
        refresh (remaining-1)
      _->either throwIO pure result

backupDecisions :: CriticalEnvironment -> IO ()
backupDecisions environment@(CriticalEnvironment _ _ _ _ _ reader _)=do
  c<-customer environment
  when (requireBackup $ customerPolicy c) $ do
    before<-evalRead reader ReadState
    when (ledgerBackup before<ledgerSequence before) $ do
      evalWorker @'[WorkerBackup] environment (\cap -> checkpointBackup cap $ ledgerSequence before)
      after<-evalRead reader ReadState
      require (ledgerBackup after>=ledgerSequence before) "backup_pending"

-- Explicit resume retains every recovery error; only the worker may defer custody.
recoverPending :: CriticalEnvironment -> IO ()
recoverPending environment@(CriticalEnvironment _ _ _ _ _ _ writer)=do
  locks<-tryBridge (evalWorker @'[WorkerRecovery] environment recoverNativeLocks)
  scanned<-tryBridge (evalWorker @'[WorkerObservation] environment observeChains)
  sources<-tryBridge (evalWorker @'[WorkerRecovery] environment recoverNativeSources)
  now<-floor <$> getPOSIXTime
  evalWrite writer (ExpireQuotes now)
  outcomes<-reconcilePending environment
  settled<-tryBridge (evalWorker @'[WorkerRecovery] environment recoverNativeSettlements)
  evalWorker @'[WorkerObservation] environment reconcileCustody
  mapM_ (either throwIO pure) (locks:scanned:sources:settled:outcomes)

-- Inspect each economic payment once, including its native replacement family.
reconcilePending :: CriticalEnvironment -> IO [Either BridgeError ()]
reconcilePending environment@(CriticalEnvironment _ _ _ _ _ reader _)=do
  pending<-evalRead reader PendingAttempts >>= mapM (evalRead reader . ReadAttempt)
  let families=M.elems $ M.fromList [(recordedPayment saved,saved)|saved<-pending]
  mapM (\saved -> tryBridge $ evalWorker @'[WorkerRecovery] environment $ \cap -> reconcilePayment cap (signedId $ recordedSigned saved)) families

tryBridge :: forall result. IO result -> IO (Either BridgeError result)
tryBridge work=try (work `catch` (\(_::IOException)->reject "worker_io_unavailable"))

guarded :: CriticalEnvironment -> IO a -> IO a
guarded (CriticalEnvironment _ _ _ _ _ _ writer) operation=operation `onException` evalWrite writer (Pause "payment_requires_reconciliation")

decode :: forall result. FromJSON result => Text -> IO result
decode proof=either (const $ reject "invalid_saved_payment") pure (eitherDecodeStrict' $ TE.encodeUtf8 proof)

loadActive :: CriticalEnvironment -> Text -> IO (RecordedAttempt,SigningReply)
loadActive (CriticalEnvironment rpc settings config _ _ reader _) txid = do
  recorded<-evalRead reader (ReadAttempt txid)
  require (recordedState recorded `elem` ["signed","broadcast_intent"]) "payment_requires_recovery"
  prepared<-evalRead reader (ReadPreparation $ recordedPayment recorded)
  require (preparedGeneration prepared==recordedGeneration recorded) "payment_requires_recovery"
  let saved=recordedSigned recorded
  case recordedChain recorded of
    "Native"->do
      family<-evalRead reader (ReadNativeFamily $ recordedPayment recorded)
      require (recorded `elem` map fst family) "native_replacement_family_changed"
      case family of
        [(first,_)]->verifySignedAttempt (N.nativeCall rpc native) (N.profile native) config prepared (recordedSigned first)
        _->nativePreparationPlan (N.profile native) config prepared >> pure ()
    _->verifySignedAttempt (N.nativeCall rpc native) (N.profile native) config prepared saved
  reply<-case recordedChain recorded of
    "Native"->NativeReply <$> (decode (signedPolicy saved) :: IO NativeSigned)
    "Solana"->SolanaReply <$> (decode (signedPolicy saved) :: IO SolanaSigned)
    _->reject "invalid_payout_asset"
  pure (recorded,reply)
 where
  native=nativeSettings settings

observeAttempt :: CriticalEnvironment -> RecordedAttempt -> SigningReply -> IO (RecordedAttempt,PaymentObservation)
observeAttempt (CriticalEnvironment rpc settings config _ _ reader _) recorded reply=case reply of
  NativeReply _->do
    (members,view)<-readSavedNativeFamily (N.nativeCall rpc native) native config reader (recordedPayment recorded)
    require (recorded `elem` map fst members) "native_replacement_family_changed"
    active<-activeNativeMember members view
    case active of
      Just (winner,payment,depth,value) | depth>0 || winner==recorded->do
        result<-nativeConfirmation (N.nativeCall rpc native) payment depth value
        pure (winner,result)
      _->pure (recorded,if recorded==fst(last members) then PaymentUnseen else PaymentWaiting)
  SolanaReply signed->do
    _<-S.solanaIdentity rpc solana
    result<-observeSolanaPayment (S.solanaCall rpc solana) config signed
    pure (recorded,result)
 where
  native=nativeSettings settings; solana=solanaSettings settings

recordOutcome :: CriticalEnvironment -> RecordedAttempt -> PaymentObservation -> IO ()
recordOutcome environment@(CriticalEnvironment _ _ _ _ _ _ writer) recorded observed=case observed of
  PaymentUnseen->when (recordedChain recorded=="Solana") $ do
    signed<-decode (signedPolicy $ recordedSigned recorded)
    proof<-expiry environment signed
    forM_ proof (evalWrite writer . RecordSolanaExpiry recorded)
  PaymentWaiting->require (recordedState recorded=="broadcast_intent") "unrecorded_broadcast_observed"
  PaymentConfirmed costs proof->evalWrite writer (SettlePayment recorded costs proof)
  PaymentFailed fee proof->evalWrite writer (FailSolana recorded fee proof)

expiry :: CriticalEnvironment -> SolanaSigned -> IO (Maybe Text)
expiry (CriticalEnvironment rpc settings config _ _ reader writer) signed=do
  let origins=(tokenOrigin settings,operatingOrigin settings)
  evalRead reader (CheckExpiryOrigins origins)
  -- Bind scratch to exact signed policy/bytes, origins and both provider URLs.
  -- Only their hash is persisted; credentials are never included in evidence.
  let binding=digest(BL.toStrict $ encode (signed,origins,S.solanaRpc solana,S.solanaVerifierRpc solana))
  previous<-evalRead reader (ReadExpiryProgress binding)
  (next,proof)<-solanaExpiryEvidence (S.solanaCall rpc solana)
    (fmap (\url->RPC.rpc rpc url Nothing) $ S.solanaVerifierRpc solana) (N.profile native) config origins signed binding previous
  forM_ next $ \progress->when (Just progress/=previous) $
    evalWrite writer (RecordExpiryProgress binding previous progress)
  pure proof
 where
  native=nativeSettings settings; solana=solanaSettings settings

proveMissing :: CriticalEnvironment -> W.Deposit -> IO Value
proveMissing (CriticalEnvironment rpc settings config _ _ reader _) source = do
  _<-N.nativeIdentity rpc native
  (binding,evidence)<-evalRead reader (ReadNativeSourceInspection $ W.depositId source)
  result<-inspectNativeSource (N.nativeCall rpc native) (N.readNativeTransaction native) native (defaultNativeDepth settings) (H.fingerprint config) source binding evidence
  case result of W.SourceMissing proof->pure proof; _->reject "source_loss_not_proven"
 where
  native=nativeSettings settings

refreshSource :: CriticalEnvironment -> Text -> IO ()
refreshSource environment@(CriticalEnvironment rpc settings config _ _ reader writer) identifier = do
  source<-evalRead reader (ReadPaymentSource identifier)
  forM_ source $ \binding->do
    let saved=W.sourceDeposit binding
    if W.depositAsset saved==Native && not(W.depositEligible saved) then do
      evalRead reader (CheckPaymentSource identifier)
      proof<-proveMissing environment saved
      evalWrite writer (RecordSourceCheck saved $ W.SourceMissing proof)
     else do
      case W.depositAsset saved of
        Native->N.nativeIdentity rpc native >> pure ()
        Wrapped->S.solanaIdentity rpc solana >> pure ()
        Sol->reject "unsupported_source_asset"
      observed<-verifyPaymentSource (N.nativeCall rpc native) (N.readNativeTransaction native) (S.solanaCall rpc solana)
        (fmap (\url->RPC.rpc rpc url Nothing) $ S.solanaVerifierRpc solana) (N.profile native) config binding
      evalWrite writer (RefreshPaymentSource saved observed)
    evalRead reader (CheckPaymentSource identifier)
 where
  native=nativeSettings settings; solana=solanaSettings settings

-- The caller owns this lifetime (run it alongside HTTP with structured concurrency).
-- Async cancellation and database failures escape; they are never retried as work.
runWorkerLoop :: (forall a. SomeOperationAt Program 'Worker 'Critical a -> IO a) -> IO ()
runWorkerLoop evaluate=forever $ do
  evaluate (workerRequest @'[WorkerCycle] runWorkerCycle) `catch` (\(BridgeError code)->hPutStrLn stderr ("worker: "<>T.unpack code))
  threadDelay 15000000
