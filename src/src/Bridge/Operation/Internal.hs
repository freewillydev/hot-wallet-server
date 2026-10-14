{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE FlexibleInstances, DataKinds, FunctionalDependencies, RoleAnnotations, TypeFamilies, TypeFamilyDependencies, ConstraintKinds, UndecidableSuperClasses, TypeApplications, ScopedTypeVariables, RankNTypes, QuantifiedConstraints, UndecidableInstances #-}
{-# OPTIONS_GHC -Werror=incomplete-patterns #-}
{-# LANGUAGE QualifiedDo, TypeOperators #-}
-- Closed grammar and capability contract. Handler selections cannot supply IO.
module Bridge.Operation.Internal (module Bridge.Operation.Internal, Severity(..), SomeOperationAt) where

import Data.Aeson (ToJSON,FromJSON(..),genericParseJSON,defaultOptions,Options(..))
import GHC.Generics (Generic)
import Bridge.Domain (Asset,Amount)
import Bridge.Wire
import Data.Kind (Type,Constraint)
import Data.Typeable (Typeable,eqT)
import Data.Type.Equality ((:~:)(Refl))
import Control.Operation
import Control.Operation.Severity
import Control.Operation.Flow (Flow)
import qualified Control.Operation.Flow as F
import Data.Text (Text)
import Data.Int (Int64)
import Data.Proxy (Proxy(..))

data Caller = Customer | Signer | Worker | Operator

-- All four callers have exactly one operation family. Severity is an index of
-- that family's GADT, so a caller can have safe and critical instructions without
-- inventing another class argument. Both dependencies reject new family instances.
-- Concrete instances live beside the evaluators; constructors stay private there.
data family Evaluation (severity :: Severity)

-- Closed effect capability; the general operation/pipeline machinery is supplied
-- by operation-capabilities. No evaluation environment enters a pure pipeline.
class (Typeable caller,Typeable severity,Typeable op)
    => Execution (caller :: Caller) (severity :: Severity) (op :: Severity -> Type -> Type)
    | caller -> op, op -> caller where
  authorizeOperation :: Evaluation severity -> Program caller severity a -> IO ()
  evaluateOperation :: Evaluation severity -> Program caller severity a -> IO a

type ExecutionContext caller severity a = (Typeable a, Execution caller severity (Command caller))

data CustomerRead a where
  PublicConfig :: CustomerRead PublicConfiguration
  OrderStatus :: Text -> Text -> CustomerRead OrderView
  PaymentInstructions :: Text -> Text -> CustomerRead PaymentInstruction

data CustomerWrite a where
  CreateOrder :: Text -> OrderRequest -> CustomerWrite OrderView

data OperatorRead a where
  NativeReviews :: OperatorRead [(Text,Text,Int64)]
  ServiceState :: OperatorRead ServiceStatus
  TreasuryReceipts :: OperatorRead [(Text,Asset,Amount)]

-- Methods construct composable syntax. Only the concrete critical module knows
-- the production instruction constructors; tests can use a separate trace carrier.
type family MethodStep value :: [Type] -> [Type] -> Type -> Type
type Method value before after result = Flow (MethodStep value) before after result

-- These combinators preserve the state indices; changing stages stays explicit.
whenFlow :: Bool -> Flow step state state () -> Flow step state state ()
whenFlow enabled action = if enabled then action else F.pure ()
traverseFlow_ :: (a -> Flow step state state b) -> [a] -> Flow step state state ()
traverseFlow_ action = foldr (\value rest -> action value F.>> rest) (F.pure ())

class OperatorService value where
  pauseService :: value -> Text -> Method value '[] '[] ()
  resumeService :: value -> Method value '[] '[] ()

-- Internal workflow capability: deliberately absent from DomainCaps.
class CustodySteps value where
  custodyScope :: value -> Method value before after a -> Method value before after a
  checkpointCustody :: value -> Method value '[] '[] ()
  observeCustody :: value -> Method value '[] '[] ()
  reconcileCustodyStep :: value -> Method value '[] '[] ()

class ResumeSteps value where
  checkResume :: value -> Method value '[] '[] ()
  recoverResume :: value -> Method value '[] '[] ()
  inspectResume :: value -> Method value '[] '[] (ResumeWork value)
  refreshResume :: value -> ResumeWork value -> Method value '[] '[] ()
  inspectResumeDraft :: value -> Method value '[] '[] (Maybe (ResumeDraft value))
  restoreResumeDraft :: value -> ResumeDraft value -> Method value '[] '[] ()
  finishResume :: value -> ResumeWork value -> Maybe (ResumeDraft value) -> Method value '[] '[] ()

class OperatorRepair value where
  repairCompletedOrder :: value -> Text -> Method value '[] '[] ()
  retrySolanaPayment :: value -> Text -> Text -> Method value '[] '[] ()
  cancelPreparation :: value -> Text -> Int -> Text -> Method value '[] '[] ()
  refundDeposit :: value -> Text -> Method value '[] '[] RefundAuthorization

class RetrySteps value where
  inspectRetry :: value -> Text -> Text -> Method value '[] '[] (Maybe (RetryWork value))
  refreshRetrySource :: value -> RetryWork value -> Method value '[] '[] ()
  proveRetryExpired :: value -> RetryWork value -> Method value '[] '[] Text
  commitRetryApproval :: value -> RetryWork value -> Text -> Method value '[] '[] ()

class CancellationSteps value where
  inspectCancellation :: value -> Text -> Int -> Text -> Method value '[] '[] (Maybe (CancellationWork value))
  refreshCancellationSource :: value -> CancellationWork value -> Method value '[] '[] ()
  beginCancellation :: value -> CancellationWork value -> Method value '[] '[] (CancellationCommit value)
  releaseCancellation :: value -> CancellationCommit value -> Method value '[] '[] ()
  finishCancellation :: value -> CancellationCommit value -> Method value '[] '[] ()

class OperatorNative value where
  rebroadcastNative :: value -> Text -> Int64 -> Text -> Method value '[] '[] Text
  draftNativeReplacement :: value -> Text -> Amount -> Text -> Method value '[] '[] Int64
  signNativeReplacement :: value -> Int64 -> Method value '[] '[] Text
  cancelNativeReplacement :: value -> Int64 -> Text -> Method value '[] '[] ()

-- Internal workflow capability: deliberately absent from DomainCaps.
class NativeSteps value where
  inspectRebroadcast :: value -> Text -> Int64 -> Text -> Method value '[] '[] (RebroadcastWork value)
  sendRebroadcast :: value -> RebroadcastWork value -> Method value '[] '[] Text
  inspectReplacementDraft :: value -> Text -> Amount -> Text -> Method value '[] '[] (Either Int64 (ReplacementDraftWork value))
  refreshReplacementDraft :: value -> ReplacementDraftWork value -> Method value '[] '[] ()
  issueReplacementDraft :: value -> ReplacementDraftWork value -> Method value '[] '[] Int64
  inspectReplacementSigning :: value -> Int64 -> Method value '[] '[] (Either Text (ReplacementSigningWork value))
  refreshReplacementSigning :: value -> ReplacementSigningWork value -> Method value '[] '[] ()
  issueReplacementSigning :: value -> ReplacementSigningWork value -> Method value '[] '[] Text

class OperatorSource value where
  coverLostSource :: value -> Text -> Int64 -> Amount -> Amount -> Text -> Method value '[] '[] ()
  approveCovered :: value -> Text -> Int64 -> Text -> Method value '[] '[] ()
  restoreSource :: value -> Text -> Int64 -> Text -> Method value '[] '[] ()

class OperatorTreasury value where
  classifySpend :: value -> Text -> Text -> Text -> Method value '[] '[] Int64
  initializeOperating :: value -> Text -> Text -> Text -> Method value '[] '[] Int64
  allocateReceipt :: value -> Text -> [(Text,Amount)] -> Text -> Method value '[] '[] Int64
  withdrawFees :: value -> Text -> Asset -> Amount -> Text -> Text -> Method value '[] '[] Text
  cancelFeeWithdrawal :: value -> Text -> Text -> Method value '[] '[] Text

-- Data families are generative and injective in BOTH indices. No type-family
-- injectivity annotation is needed. Each instance has its own output constructor.
data family Result (severity :: Severity) (op :: Type -> Type)
type PreparedResult = Result 'Critical SignPrepared
data instance Result 'Critical SignPrepared = PreparedResult { preparedOutput :: !SignedAttempt } deriving (Eq,Show,Generic)
instance ToJSON PreparedResult
instance FromJSON PreparedResult where
  parseJSON = genericParseJSON defaultOptions { rejectUnknownFields = True }
type ReplacementResult = Result 'Critical SignReplacement
data instance Result 'Critical SignReplacement = ReplacementResult { replacementOutput :: !SignedAttempt } deriving (Eq,Show,Generic)
instance ToJSON ReplacementResult
instance FromJSON ReplacementResult where
  parseJSON = genericParseJSON defaultOptions { rejectUnknownFields = True }
type DraftResult = Result 'Critical DraftReplacement
data instance Result 'Critical DraftReplacement = DraftResult { draftOutput :: !NativeDraft } deriving (Eq,Show,Generic)
instance ToJSON DraftResult
instance FromJSON DraftResult where
  parseJSON = genericParseJSON defaultOptions { rejectUnknownFields = True }
type CheckpointResult = Result 'Critical CheckpointCustody
data instance Result 'Critical CheckpointCustody = CheckpointResult { checkpointOutput :: !BackupReceipt } deriving (Eq,Show,Generic)
instance ToJSON CheckpointResult
instance FromJSON CheckpointResult where
  parseJSON = genericParseJSON defaultOptions { rejectUnknownFields = True }

-- Initial signing is tied to a durable decision, never caller-supplied bytes.
data CheckpointCustody a where
  CheckpointCustody :: Text -> Int64 -> CheckpointCustody CheckpointResult
data DraftReplacement a where
  DraftReplacement :: Text -> Text -> Amount -> DraftReplacement DraftResult
data SignReplacement a where
  SignReplacement :: Text -> Int64 -> SignReplacement ReplacementResult
data SignPrepared a where
  SignPrepared :: Text -> Text -> Int -> SignPrepared PreparedResult

-- Closed signer instruction set, compiled only after the payload equality proof.
data SigningOperation a where
  PreparedSigning :: SignPrepared a -> SigningOperation a
  ReplacementSigning :: SignReplacement a -> SigningOperation a
  DraftSigning :: DraftReplacement a -> SigningOperation a
  CheckpointSigning :: CheckpointCustody a -> SigningOperation a

class WorkerBackup value where
  checkpointBackup :: value -> Int64 -> Method value '[] '[] ()
  checkpointForUpgrade :: value -> Method value '[] '[] BackupReceipt
  checkpointPending :: value -> Method value '[state] '[BackupCovered state] ()

class WorkerObservation value where
  observeChains :: value -> Method value '[] '[] ()
  reconcileCustody :: value -> Method value '[] '[] ()
  inspectPayout :: value -> Text -> Method value '[] '[Text] [Text]

class WorkerRecovery value where
  recoverNativeSettlements :: value -> Method value '[] '[] ()
  recoverNativeSources :: value -> Method value '[] '[] ()
  recoverNativeLocks :: value -> Method value '[] '[] ()
  reconcilePayment :: value -> Text -> Method value '[] '[] ()
  reusePayout :: value -> [Text] -> Method value '[Text] '[SignedPayout] ()

class WorkerPreparation value where
  prepareOutgoing :: value -> Method value '[Text] '[PreparedPayout] ()

class WorkerSigning value where
  signPreparedPayment :: value -> Method value '[BackupCovered PreparedPayout] '[SignedPayout] Text

-- Internal workflow capability: deliberately absent from DomainCaps.
class SigningSteps value where
  signingScope :: value -> Method value before after a -> Method value before after a
  inspectSigning :: value -> Method value '[BackupCovered PreparedPayout] '[SigningWork value] (Maybe Text)
  reuseSignature :: value -> Text -> Method value '[SigningWork value] '[SignedPayout] Text
  issueSignature :: value -> Method value '[SigningWork value] '[SignedPayout] Text

class WorkerQueue value where
  queuePayment :: value -> Method value '[SignedPayout] '[QueuedPayout] Int64

class WorkerBroadcast value where
  broadcastPayment :: value -> Method value '[BackupCovered QueuedPayout] '[] ()

-- Internal workflow capability: deliberately absent from DomainCaps.
class BroadcastSteps value where
  broadcastScope :: value -> Method value before after a -> Method value before after a
  inspectBroadcast :: value -> Method value '[BackupCovered QueuedPayout] '[BroadcastWork value] Bool
  sendUnseenPayment :: value -> Method value '[BroadcastWork value] '[] ()
  recordObservedPayment :: value -> Method value '[BroadcastWork value] '[] ()

class WorkerCycle value where
  runWorkerCycle :: value -> Method value '[] '[] ()

-- Internal workflow capability: deliberately absent from DomainCaps.
class CycleSteps value where
  cycleScope :: value -> Method value before before () -> Method value before before ()
  recoverCycle :: value -> Method value '[] '[] ()
  cycleCanPay :: value -> Method value '[] '[] Bool
  cycleCandidates :: value -> Method value '[] '[] [Text]
  cyclePayout :: value -> Text -> Method value '[] '[] ()
  cycleOwnerFees :: value -> Method value '[] '[] ()

class OwnerFeeSteps value where
  ownerFeeCandidates :: value -> Method value '[] '[] [OwnerFeeWork value]
  reserveOwnerFee :: value -> OwnerFeeWork value -> Method value '[] '[] Bool

-- Runtime evidence stays opaque to the compiler and request selectors.
-- Only the corresponding concrete capability implementation constructs it.
data family ResumeWork value
data family ResumeDraft value
data family SigningWork value
data family BroadcastWork value
data family RebroadcastWork value
data family ReplacementDraftWork value
data family ReplacementSigningWork value
data family RetryWork value
data family CancellationWork value
data family CancellationCommit value
data family OwnerFeeWork value

-- Sequencing markers, not financial authority: every primitive still rechecks
-- the ledger. Signing and sending require the preceding backup step in the Flow.
data PreparedPayout = PreparedPayout Text
data SignedPayout = SignedPayout Text
data QueuedPayout = QueuedPayout Text
data BackupCovered state = BackupCovered state

type PayoutCapabilities value = (WorkerObservation value, WorkerPreparation value, WorkerSigning value, WorkerRecovery value, WorkerBackup value, WorkerQueue value, WorkerBroadcast value)
-- Each workflow constructor carries only the dictionaries its branch uses.
-- Interpretation proves the complete payload type before exposing that context.
data Workflow value (before :: [Type]) (after :: [Type]) result where
  PayoutWorkflow :: PayoutCapabilities value => value -> Text -> Workflow value '[] '[] ()
  CycleWorkflow :: CycleSteps value => value -> Workflow value '[] '[] ()
  ResumeWorkflow :: (ResumeSteps value, CustodySteps value) => value -> Workflow value '[] '[] ()
  SigningWorkflow :: SigningSteps value => value -> Workflow value '[BackupCovered PreparedPayout] '[SignedPayout] Text
  BroadcastWorkflow :: BroadcastSteps value => value -> Workflow value '[BackupCovered QueuedPayout] '[] ()
  RebroadcastWorkflow :: (NativeSteps value, CustodySteps value) => value -> Text -> Int64 -> Text -> Workflow value '[] '[] Text
  ReplacementDraftWorkflow :: (NativeSteps value, CustodySteps value) => value -> Text -> Amount -> Text -> Workflow value '[] '[] Int64
  ReplacementSigningWorkflow :: (NativeSteps value, CustodySteps value) => value -> Int64 -> Workflow value '[] '[] Text
  RetryWorkflow :: (RetrySteps value, CustodySteps value) => value -> Text -> Text -> Workflow value '[] '[] ()
  CancellationWorkflow :: (CancellationSteps value, CustodySteps value) => value -> Text -> Int -> Text -> Workflow value '[] '[] ()
  OwnerFeesWorkflow :: OwnerFeeSteps value => value -> Workflow value '[] '[] ()

instance (Typeable value, Typeable before, Typeable after, Typeable result, caps ~ '[])
    => Operation (Workflow value before after result) caps where
  type Context (Workflow value before after result) = Typeable (Workflow value before after result)
  type Outcome (Workflow value before after result) = Method value before after result
  data DSL (Workflow value before after result) where
    CompileWorkflow :: Context (Workflow value before after result) => DSL (Workflow value before after result)
  interpret (SomeOperation (payload :: actual)) CompileWorkflow =
    case eqT @actual @(Workflow value before after result) of
      Nothing -> Nothing
      Just Refl -> Just $ case payload of
        PayoutWorkflow value identifier -> F.do
          attempts <- inspectPayout value identifier
          case attempts of
            [] -> F.do
              prepareOutgoing value
              checkpointPending value
              signPreparedPayment value
              F.pure ()
            _ -> reusePayout value attempts
          queuePayment value
          checkpointPending value
          broadcastPayment value
        CycleWorkflow value -> cycleScope value $ F.do
          recoverCycle value
          enabled <- cycleCanPay value
          whenFlow enabled $ F.do
            candidates <- cycleCandidates value
            traverseFlow_ (cyclePayout value) candidates
            cycleOwnerFees value
        ResumeWorkflow value -> custodyScope value $ F.do
          checkResume value
          recoverResume value
          reviewed <- inspectResume value
          refreshResume value reviewed
          checkpointCustody value
          observeCustody value
          reconcileCustodyStep value
          draft <- inspectResumeDraft value
          case draft of
            Nothing -> F.pure ()
            Just work -> restoreResumeDraft value work
          finishResume value reviewed draft
        SigningWorkflow value -> signingScope value $ F.do
          saved <- inspectSigning value
          case saved of
            Nothing -> issueSignature value
            Just txid -> reuseSignature value txid
        BroadcastWorkflow value -> broadcastScope value $ F.do
          unseen <- inspectBroadcast value
          if unseen then sendUnseenPayment value else recordObservedPayment value
        RebroadcastWorkflow value txid anchor reason -> custodyScope value $ F.do
          work <- inspectRebroadcast value txid anchor reason
          checkpointCustody value
          sendRebroadcast value work
        ReplacementDraftWorkflow value parent fee reason -> custodyScope value $ F.do
          previous <- inspectReplacementDraft value parent fee reason
          case previous of
            Left decision -> F.pure decision
            Right work -> F.do
              refreshReplacementDraft value work
              reconcileCustodyStep value
              issueReplacementDraft value work
        ReplacementSigningWorkflow value decision -> custodyScope value $ F.do
          previous <- inspectReplacementSigning value decision
          case previous of
            Left txid -> F.pure txid
            Right work -> F.do
              refreshReplacementSigning value work
              checkpointCustody value
              observeCustody value
              reconcileCustodyStep value
              issueReplacementSigning value work
        RetryWorkflow value txid reason -> custodyScope value $ F.do
          previous <- inspectRetry value txid reason
          case previous of
            Nothing -> F.pure ()
            Just work -> F.do
              refreshRetrySource value work
              proof <- proveRetryExpired value work
              reconcileCustodyStep value
              commitRetryApproval value work proof
        CancellationWorkflow value identifier generation reason -> custodyScope value $ F.do
          previous <- inspectCancellation value identifier generation reason
          case previous of
            Nothing -> F.pure ()
            Just work -> F.do
              refreshCancellationSource value work
              reconcileCustodyStep value
              committed <- beginCancellation value work
              releaseCancellation value committed
              finishCancellation value committed
        OwnerFeesWorkflow value -> F.do
          candidates <- ownerFeeCandidates value
          let reserve [] = F.pure ()
              reserve (candidate:rest) = F.do
                saved <- reserveOwnerFee value candidate
                whenFlow (not saved) (reserve rest)
          reserve candidates

workflow :: forall value before after result.
            (Typeable value, Typeable before, Typeable after, Typeable result)
         => Workflow value before after result -> Maybe (Method value before after result)
workflow payload = interpret (SomeOperation payload)
  (CompileWorkflow :: Context (Workflow value before after result) => DSL (Workflow value before after result))

payoutFlow :: (Typeable value, PayoutCapabilities value) => value -> Text -> Maybe (Method value '[] '[] ())
payoutFlow value identifier = workflow (PayoutWorkflow value identifier)

-- One closed payload GADT carries caller, severity and the exact result type.
-- Family aliases retain the evaluator's caller -> family functional dependency.
data Command (caller :: Caller) (severity :: Severity) a where
  CustomerQuery :: CustomerRead a -> Command 'Customer 'Safe a
  CustomerChange :: CustomerWrite a -> Command 'Customer 'Critical a
  OperatorQuery :: OperatorRead a -> Command 'Operator 'Safe a
  OperatorChange :: (Capabilities (DomainCaps 'Operator 'Critical) (OperatorCommand 'Critical a),
                     UniqueCapabilities selected, Subset selected (DomainCaps 'Operator 'Critical),
                     Subset selected (PreparationCaps 'Operator 'Critical a))
                 => Proxy selected -> (forall value. Capabilities selected value => value -> Method value '[] '[] a)
                 -> Command 'Operator 'Critical a
  WorkerAction :: (Capabilities (DomainCaps 'Worker 'Critical) (WorkerCommand 'Critical a),
                     UniqueCapabilities selected, Subset selected (DomainCaps 'Worker 'Critical),
                     Subset selected (PreparationCaps 'Worker 'Critical a))
                 => Proxy selected -> (forall value. Capabilities selected value => value -> Method value '[] '[] a)
                 -> Command 'Worker 'Critical a
  SignerAction :: SigningOperation a -> Command 'Signer 'Critical a

type CustomerCommand = Command 'Customer
type OperatorCommand = Command 'Operator
type WorkerCommand = Command 'Worker
type SignerCommand = Command 'Signer

-- Concrete action constructors exist only in the evaluator module.
data family Action (caller :: Caller) (before :: [Type]) (after :: [Type]) a
type instance MethodStep (Command caller severity result) = Action caller

-- Each constructor stores the same closed execution capability as its operation.
-- Caller/severity cannot be weakened when the interpreter constructs the DSL.
data Program (caller :: Caller) (severity :: Severity) a where
  ReadOperator :: ExecutionContext 'Operator 'Safe a => OperatorRead a -> Program 'Operator 'Safe a
  OperatorDSL :: ExecutionContext 'Operator 'Critical a => Flow (Action 'Operator) '[] '[] a -> Program 'Operator 'Critical a
  WorkerDSL :: ExecutionContext 'Worker 'Critical a => Flow (Action 'Worker) '[] '[] a -> Program 'Worker 'Critical a
  SigningDSL :: ExecutionContext 'Signer 'Critical a => SigningOperation a -> Program 'Signer 'Critical a
  ReadCustomer :: ExecutionContext 'Customer 'Safe a => CustomerRead a -> Program 'Customer 'Safe a
  WriteCustomer :: ExecutionContext 'Customer 'Critical a => CustomerWrite a -> Program 'Customer 'Critical a

-- The library existential hides the command family. Its nominal capability
-- indices retain caller, severity and result without a second request wrapper.
class CompileOperation (caller :: Caller) (severity :: Severity) a value
    | value -> caller severity a where
  operationDSL :: value -> OperationDSL (Program caller severity a) value

-- Domain methods are real library capabilities on the hidden command payload.
-- Other callers retain their small closed GADTs (notably the signer boundary).
type family DomainCaps (caller :: Caller) (severity :: Severity) :: [Type -> Constraint] where
  DomainCaps 'Operator 'Critical = '[OperatorService, OperatorRepair, OperatorNative, OperatorSource, OperatorTreasury]
  DomainCaps 'Worker 'Critical = '[WorkerBackup, WorkerObservation, WorkerRecovery, WorkerPreparation, WorkerSigning, WorkerQueue, WorkerBroadcast, WorkerCycle]
  DomainCaps caller severity = '[]
type PreparationCaps caller severity a = CompileOperation caller severity a ': DomainCaps caller severity
-- The library owns the severity/caller/result-indexed existential. Selecting the
-- compilation DSL is pure; Program is produced only at explicit resolution.
pending :: forall caller severity a value.
           (Operation value (PreparationCaps caller severity a),
            Capabilities (PreparationCaps caller severity a) value,
            Subset (PreparationCaps caller severity a) (PreparationCaps caller severity a))
        => value -> SomeOperationAt Program caller severity a
pending = prepareOperation operationDSL . prepare

checkedOperation :: SomeOperationAt Program caller severity a -> Either Text (Program caller severity a)
checkedOperation = maybe (Left "operation_dictionary_mismatch") Right . resolveOperation

instance ExecutionContext caller severity a
    => CompileOperation caller severity a (Command caller severity a) where
  operationDSL _ = OperationDSL Compile

instance (ExecutionContext caller severity a,
          caps ~ PreparationCaps caller severity a, UniqueCapabilities caps)
    => Operation (Command caller severity a) caps where
  type Context (Command caller severity a) =
    (CompileOperation caller severity a (Command caller severity a), ExecutionContext caller severity a)
  type Outcome (Command caller severity a) = Program caller severity a
  data DSL (Command caller severity a) where
    Compile :: Context (Command caller severity a) => DSL (Command caller severity a)
  interpret (SomeOperation (value :: actual)) Compile =
    case eqT @actual @(Command caller severity a) of
      Just Refl -> case value of
        CustomerQuery op -> Just (ReadCustomer op)
        CustomerChange op -> Just (WriteCustomer op)
        OperatorQuery op -> Just (ReadOperator op)
        -- Restrict re-hides the carrier; recover its exact type before returning
        -- its associated method Flow. Both proofs stay inside interpretation.
        OperatorChange scope select -> either (const Nothing)
          (withCapabilities $ \(scoped :: hidden) -> case eqT @hidden @(Command caller severity a) of
            Just Refl -> Just (OperatorDSL $ select scoped)
            Nothing -> Nothing)
          (pipeline (Restrict scope) (prepare @(Command caller severity a) @(PreparationCaps caller severity a) value))
        WorkerAction scope select -> either (const Nothing)
          (withCapabilities $ \(scoped :: hidden) -> case eqT @hidden @(Command caller severity a) of
            Just Refl -> Just (WorkerDSL $ select scoped)
            Nothing -> Nothing)
          (pipeline (Restrict scope) (prepare @(Command caller severity a) @(PreparationCaps caller severity a) value))
        SignerAction op -> Just (SigningDSL op)
      Nothing -> Nothing

-- Retain caller identity through dispatch; a critical customer operation cannot
-- be substituted with a critical operator or signer operation as grammar grows.
data Plan (caller :: Caller) a where
  SafePlan :: SomeOperationAt Program caller 'Safe a -> Plan caller a
  CriticalPlan :: SomeOperationAt Program caller 'Critical a -> Plan caller a

type role Plan nominal nominal
safe :: (Typeable a, Execution 'Customer 'Safe CustomerCommand) => CustomerRead a -> Plan 'Customer a
safe = SafePlan . pending . CustomerQuery
customer :: (Typeable a, Execution 'Customer 'Critical CustomerCommand) => CustomerWrite a -> Plan 'Customer a
customer = CriticalPlan . pending . CustomerChange

operator :: forall selected a.
            (Typeable a, Execution 'Operator 'Critical OperatorCommand,
             Capabilities (DomainCaps 'Operator 'Critical) (OperatorCommand 'Critical a),
             UniqueCapabilities selected, Subset selected (DomainCaps 'Operator 'Critical),
             Subset selected (PreparationCaps 'Operator 'Critical a))
         => (forall value. Capabilities selected value => value -> Method value '[] '[] a) -> Plan 'Operator a
operator select=CriticalPlan (pending $ OperatorChange (Proxy @selected) select)
operatorRead :: (Typeable a, Execution 'Operator 'Safe OperatorCommand) => OperatorRead a -> Plan 'Operator a
operatorRead=SafePlan . pending . OperatorQuery

workerRequest :: forall selected a.
                 (Typeable a, Execution 'Worker 'Critical WorkerCommand,
                  Capabilities (DomainCaps 'Worker 'Critical) (WorkerCommand 'Critical a),
                  UniqueCapabilities selected, Subset selected (DomainCaps 'Worker 'Critical),
                  Subset selected (PreparationCaps 'Worker 'Critical a))
              => (forall value. Capabilities selected value => value -> Method value '[] '[] a) -> SomeOperationAt Program 'Worker 'Critical a
workerRequest select = pending (WorkerAction (Proxy @selected) select)

-- Pure HTTP/control assembly carries these closed instance requirements.
type CustomerOperations = (Execution 'Customer 'Safe CustomerCommand, Execution 'Customer 'Critical CustomerCommand)
class (Execution 'Operator 'Safe OperatorCommand, Execution 'Operator 'Critical OperatorCommand,
       forall a. Typeable a => OperatorService (OperatorCommand 'Critical a),
       forall a. Typeable a => OperatorRepair (OperatorCommand 'Critical a),
       forall a. Typeable a => OperatorNative (OperatorCommand 'Critical a),
       forall a. OperatorSource (OperatorCommand 'Critical a),
       forall a. OperatorTreasury (OperatorCommand 'Critical a)) => OperatorOperations
