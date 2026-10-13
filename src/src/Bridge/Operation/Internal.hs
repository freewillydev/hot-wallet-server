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

class OperatorWrite value where
  repairCompletedOrder :: value -> Text -> Program 'Operator 'Critical ()
  rebroadcastNative :: value -> Text -> Int64 -> Text -> Program 'Operator 'Critical Text
  draftNativeReplacement :: value -> Text -> Amount -> Text -> Program 'Operator 'Critical Int64
  signNativeReplacement :: value -> Int64 -> Program 'Operator 'Critical Text
  cancelNativeReplacement :: value -> Int64 -> Text -> Program 'Operator 'Critical ()
  coverLostSource :: value -> Text -> Int64 -> Amount -> Amount -> Text -> Program 'Operator 'Critical ()
  approveCovered :: value -> Text -> Int64 -> Text -> Program 'Operator 'Critical ()
  restoreSource :: value -> Text -> Int64 -> Text -> Program 'Operator 'Critical ()
  classifySpend :: value -> Text -> Text -> Text -> Program 'Operator 'Critical Int64
  initializeOperating :: value -> Text -> Text -> Text -> Program 'Operator 'Critical Int64
  allocateReceipt :: value -> Text -> [(Text,Amount)] -> Text -> Program 'Operator 'Critical Int64
  withdrawFees :: value -> Text -> Asset -> Amount -> Text -> Text -> Program 'Operator 'Critical Text
  cancelFeeWithdrawal :: value -> Text -> Text -> Program 'Operator 'Critical Text
  retrySolanaPayment :: value -> Text -> Text -> Program 'Operator 'Critical ()
  cancelPreparation :: value -> Text -> Int -> Text -> Program 'Operator 'Critical ()
  refundDeposit :: value -> Text -> Program 'Operator 'Critical RefundAuthorization
  pauseService :: value -> Text -> Program 'Operator 'Critical ()
  resumeService :: value -> Program 'Operator 'Critical ()

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

class WorkerOperations value where
  checkpointBackup :: value -> Int64 -> Program 'Worker 'Critical ()
  checkpointForUpgrade :: value -> Program 'Worker 'Critical BackupReceipt
  recoverNativeSettlements :: value -> Program 'Worker 'Critical ()
  recoverNativeSources :: value -> Program 'Worker 'Critical ()
  recoverNativeLocks :: value -> Program 'Worker 'Critical ()
  runWorkerCycle :: value -> Program 'Worker 'Critical ()
  observeChains :: value -> Program 'Worker 'Critical ()
  prepareOutgoing :: value -> Text -> Program 'Worker 'Critical ()
  reconcileCustody :: value -> Program 'Worker 'Critical ()
  signPreparedPayment :: value -> Text -> Program 'Worker 'Critical Text
  reconcilePayment :: value -> Text -> Program 'Worker 'Critical ()
  queuePayment :: value -> Text -> Program 'Worker 'Critical Int64
  broadcastPayment :: value -> Text -> Program 'Worker 'Critical ()

-- Actual identifiers travel between completed stages. These are sequencing
-- markers, NOT financial authority: each existing operation rechecks the ledger.
data PreparedPayout = PreparedPayout Text
data SignedPayout = SignedPayout Text
data QueuedPayout = QueuedPayout Text

-- Closed, bounded payout grammar; no arbitrary IO or retry instruction.
-- The constructor supplies the worker capability after the payload's Refl.
data PayoutStep value before after result where
  InspectPayout :: WorkerOperations value => PayoutStep value '[Text] '[Text] [Text]
  PreparePayout :: WorkerOperations value => PayoutStep value '[Text] '[PreparedPayout] ()
  SignPayout :: WorkerOperations value => PayoutStep value '[PreparedPayout] '[SignedPayout] ()
  ReusePayout :: WorkerOperations value => [Text] -> PayoutStep value '[Text] '[SignedPayout] ()
  QueuePayout :: WorkerOperations value => PayoutStep value '[SignedPayout] '[QueuedPayout] ()
  SendPayout :: WorkerOperations value => PayoutStep value '[QueuedPayout] '[] ()

payoutFlow :: WorkerOperations value => value -> Flow (PayoutStep value) '[Text] '[] ()
payoutFlow _ = F.do
  attempts <- F.step InspectPayout
  case attempts of
    [] -> F.do
      F.step PreparePayout
      F.step SignPayout
    _ -> F.step (ReusePayout attempts)
  F.step QueuePayout
  F.step SendPayout

-- One closed payload GADT carries caller, severity and the exact result type.
-- Family aliases retain the evaluator's caller -> family functional dependency.
data Command (caller :: Caller) (severity :: Severity) a where
  CustomerQuery :: CustomerRead a -> Command 'Customer 'Safe a
  CustomerChange :: CustomerWrite a -> Command 'Customer 'Critical a
  OperatorQuery :: OperatorRead a -> Command 'Operator 'Safe a
  OperatorChange :: OperatorWrite (OperatorCommand 'Critical a) => (forall value. OperatorWrite value => value -> Program 'Operator 'Critical a) -> Command 'Operator 'Critical a
  WorkerAction :: WorkerOperations (WorkerCommand 'Critical a) => (forall value. WorkerOperations value => value -> Program 'Worker 'Critical a) -> Command 'Worker 'Critical a
  SignerAction :: SigningOperation a -> Command 'Signer 'Critical a

type CustomerCommand = Command 'Customer
type OperatorCommand = Command 'Operator
type WorkerCommand = Command 'Worker
type SignerCommand = Command 'Signer

-- Concrete action constructors exist only in the evaluator module.
data family Action (caller :: Caller) a

-- Each constructor stores the same closed execution capability as its operation.
-- Caller/severity cannot be weakened when the interpreter constructs the DSL.
data Program (caller :: Caller) (severity :: Severity) a where
  ReadOperator :: ExecutionContext 'Operator 'Safe a => OperatorRead a -> Program 'Operator 'Safe a
  OperatorDSL :: ExecutionContext 'Operator 'Critical a => Action 'Operator a -> Program 'Operator 'Critical a
  WorkerDSL :: ExecutionContext 'Worker 'Critical a => Action 'Worker a -> Program 'Worker 'Critical a
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
  DomainCaps 'Operator 'Critical = '[OperatorWrite]
  DomainCaps 'Worker 'Critical = '[WorkerOperations]
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
      Just Refl -> Just $ case value of
        CustomerQuery op -> ReadCustomer op
        CustomerChange op -> WriteCustomer op
        OperatorQuery op -> ReadOperator op
        OperatorChange select -> select value
        WorkerAction select -> select value
        SignerAction op -> SigningDSL op
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

operator :: (Typeable a, Execution 'Operator 'Critical OperatorCommand, OperatorWrite (OperatorCommand 'Critical a))
         => (forall value. OperatorWrite value => value -> Program 'Operator 'Critical a) -> Plan 'Operator a
operator select=CriticalPlan (pending $ OperatorChange select)
operatorRead :: (Typeable a, Execution 'Operator 'Safe OperatorCommand) => OperatorRead a -> Plan 'Operator a
operatorRead=SafePlan . pending . OperatorQuery

workerRequest :: (Typeable a, Execution 'Worker 'Critical WorkerCommand, WorkerOperations (WorkerCommand 'Critical a))
              => (forall value. WorkerOperations value => value -> Program 'Worker 'Critical a) -> SomeOperationAt Program 'Worker 'Critical a
workerRequest select = pending (WorkerAction select)

-- Pure HTTP/control assembly carries these closed instance requirements.
type CustomerOperations = (Execution 'Customer 'Safe CustomerCommand, Execution 'Customer 'Critical CustomerCommand)
class (Execution 'Operator 'Safe OperatorCommand, Execution 'Operator 'Critical OperatorCommand,
       forall a. OperatorWrite (OperatorCommand 'Critical a)) => OperatorOperations
