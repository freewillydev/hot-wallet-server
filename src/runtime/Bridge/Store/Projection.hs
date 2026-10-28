-- Relational facts for specific closed Store/migration operations. No connection,
-- evaluator or write capability is exported. Phase and restrictions stay distinct.
module Bridge.Store.Projection (paymentStates, paymentAmounts, immediateRefunds, payoutCohort, assignedPayouts, unassignedPayments, activePayments, readyPayments, orderObligations, openOrders, queuedOrders, workIntents, sourceRestricted, successorReady) where

import qualified Bridge.Store.Schema as S
import qualified Opaleye as O
import qualified Opaleye.Exists as E

-- Immutable net funding for conversions, refunds and already reserved owner fees.
paymentAmounts :: O.Select (S.TextField,S.TextField,S.IntField)
paymentAmounts = O.unionAll (do
    row<-O.selectTable S.obligations
    pure (S.obligationId row,S.obligationAsset row,S.obligationAmount row)) (do
    row<-O.selectTable S.withdrawals
    pure (O.sqlStrictText "fee:" O..++ S.withdrawalId row,S.asset row,S.quantity row))

-- Refund authorization is already durable; batching grants no further authority.
immediateRefunds :: O.Select S.TextField
immediateRefunds = do
  row<-O.selectTable S.obligations
  O.where_ (S.obligationKind row O..== O.sqlStrictText "refund")
  pure (S.obligationId row)

-- Complete unassigned liabilities for capacity accounting, not a single sealing
-- cohort. Stable per-batch assignments are still required. Reviewed conversions
-- stay visible when readiness changes.
-- Pending quotes have no payment root yet; owner withdrawals have no order hold.
payoutCohort :: O.Select (S.TextField,S.TextField,S.IntField,O.Field O.SqlBool)
payoutCohort = O.unionAll (do
  (key,asset,n,phase)<-O.selectTable S.reservations
  O.where_ (phase O..== O.sqlStrictText "quote")
  pure (key,asset,n,O.sqlBool False)) (do
  (root,state)<-paymentStates
  let key=S.rootId root
  O.where_ (O.not $ O.in_ (map O.sqlStrictText ["settled","cancelled"]) (S.rootPhase root))
  assigned<-E.exists $ do
    (member,_)<-O.selectTable S.payoutMembers
    O.where_ (member O..== key)
    pure ()
  refund<-E.exists $ do
    identifier<-immediateRefunds
    O.where_ (identifier O..== key)
    pure ()
  O.where_ (O.not assigned O..&& O.not refund)
  (funded,asset,n)<-paymentAmounts
  O.where_ (funded O..== key)
  pure (key,asset,n,state O..== O.sqlStrictText "ready"))

unassignedPayments :: O.Select (S.TextField,S.TextField,S.IntField)
unassignedPayments = do
  (key,asset,n,ready)<-payoutCohort
  O.where_ ready
  pure (key,asset,n)

-- Stable subject ownership survives promotion: pending order IDs become payment
-- IDs without moving to another batch. Refunds never inherit that assignment.
assignedPayouts :: O.Select (S.TextField,S.TextField,S.TextField,S.IntField,O.Field O.SqlBool)
assignedPayouts = O.unionAll (do
  (key,asset,n,phase)<-O.selectTable S.reservations
  (group,order,_)<-O.selectTable S.payoutAssignments
  O.where_ (phase O..== O.sqlStrictText "quote"
    O..&& O.matchNullable (O.sqlBool False) (O..== key) order)
  pure (group,key,asset,n,O.sqlBool False)) $ O.unionAll (do
  (key,asset,n,ready)<-payoutCohort
  ob<-O.selectTable S.obligations
  (group,order,_)<-O.selectTable S.payoutAssignments
  O.where_ (S.obligationId ob O..== key O..&& S.obligationKind ob O..== O.sqlStrictText "conversion"
    O..&& O.matchNullable (O.sqlBool False) (O..== S.obligationOrder ob) order)
  pure (group,key,asset,n,ready)) (do
  (key,asset,n,ready)<-payoutCohort
  (group,_,withdrawal)<-O.selectTable S.payoutAssignments
  O.where_ (O.matchNullable (O.sqlBool False) (\w->key O..== O.sqlStrictText "fee:" O..++ w) withdrawal)
  pure (group,key,asset,n,ready))

orderObligations :: O.Select (S.TextField,S.TextField,S.TextField,S.TextField)
orderObligations = do
  ob<-O.selectTable S.obligations
  (root,state)<-paymentStates
  O.where_ (S.rootId root O..== S.obligationId ob)
  pure (S.obligationId ob,S.obligationOrder ob,S.obligationDeposit ob,state)

-- Keep recovery/archive checks broader than admission: an expired reviewed
-- receipt is still unresolved even though its conversion no longer queues.
openOrders :: O.Select S.OrderFields
openOrders = do
  (order,unpaid,settled)<-ordersWithPayments
  O.where_ (unpaid O..|| (O.not settled O..&& S.admissionState order O../= O.sqlStrictText "ExpiredUnfunded"))
  pure order

-- Queue slots belong to live quotes and authorized payments. Reviewed receipts
-- retain Principal/refund reserves independently of their expired quote.
queuedOrders :: O.Select S.OrderFields
queuedOrders = do
  (order,unpaid,_)<-ordersWithPayments
  quoted<-E.exists $ do
    (key,_,_,phase)<-O.selectTable S.reservations
    O.where_ (key O..== S.orderId order O..&& phase O..== O.sqlStrictText "quote")
    pure ()
  O.where_ (unpaid O..|| quoted)
  pure order

ordersWithPayments :: O.Select (S.OrderFields,O.Field O.SqlBool,O.Field O.SqlBool)
ordersWithPayments = do
  order<-O.selectTable S.orders
  let work=do
        ob<-O.selectTable S.obligations
        root<-O.selectTable S.paymentRoots
        O.where_ (S.obligationOrder ob O..== S.orderId order O..&& S.rootId root O..== S.obligationId ob)
        pure root
  unpaid<-E.exists $ do
    root<-work
    O.where_ (O.not $ O.in_ (map O.sqlStrictText ["settled","cancelled"]) (S.rootPhase root))
    pure ()
  settled<-E.exists $ do
    root<-work
    O.where_ (S.rootPhase root O..== O.sqlStrictText "settled")
    pure ()
  pure (order,unpaid,settled)

-- Compatibility preimage for existing work-bound recovery approvals only.
-- Newly materialized roots with no preparation never contributed an old intent.
workIntents :: O.Select (S.TextField,S.TextField,S.IntField,O.FieldNullable O.SqlText)
workIntents = do
  root<-O.selectTable S.paymentRoots
  prepared<-E.exists $ do
    (key,_,_,_,_,_)<-S.workPreparations
    O.where_ (key O..== S.rootId root)
    pure ()
  O.where_ prepared
  pure (S.rootId root,S.rootChain root,O.ifThenElse (S.rootPhase root O..== O.sqlStrictText "active") (O.sqlInt8 0) (O.sqlInt8 1),S.rootCommon root)

-- The caller checks the overflow row. Active ownership excludes competing ready
-- work even when that active payment itself needs review.
activePayments, readyPayments :: O.Select (S.TextField,S.TextField)
activePayments=O.limit 3 $ do
  root<-O.selectTable S.paymentRoots
  O.where_ (S.rootPhase root O..== O.sqlStrictText "active")
  pure (S.rootId root,S.rootChain root)
readyPayments=O.orderBy (O.asc fst) $ do
  (root,state)<-paymentStates
  O.where_ (S.rootPhase root O..== O.sqlStrictText "ready" O..&& state O..== O.sqlStrictText "ready")
  pure (S.rootId root,S.rootChain root)

paymentStates :: O.Select (S.PaymentRootFields,S.TextField)
paymentStates = do
  root<-O.selectTable S.paymentRoots
  restricted<-sourceRestricted (S.rootId root)
  retryable<-successorReady (S.rootId root)
  let phase=S.rootPhase root; text=O.sqlStrictText
      state=O.ifThenElse (phase O..== text "settled") (text "paid") $
        O.ifThenElse (phase O..== text "cancelled") (text "cancelled") $
        O.ifThenElse (restricted O..|| (phase O..== text "ready" O..&& O.not retryable)) (text "review") $
        O.ifThenElse (phase O..== text "active") (text "paying") $
        O.ifThenElse (phase O..== text "ready") (text "ready") (text "review")
  pure (root,state)

-- An eligible-again receipt does not itself clear a recorded work-bound review.
-- Coverage also needs this obligation's immutable approval of that active cover.
sourceRestricted :: S.TextField -> O.Select (O.Field O.SqlBool)
sourceRestricted identifier = E.exists $ do
  (obligation,deposit)<-S.obligationReceipts
  source<-O.selectTable S.deposits
  O.where_ (obligation O..== identifier O..&& deposit O..== S.depositId source)
  pending<-E.exists $ do
    (_,receipt,_,_,proof,sequenceNo)<-O.selectTable S.sourceChecks
    let subject=O.jsonBuildObject $ O.jsonBuildObjectField "reason" (O.sqlStrictText "source_eligibility_lost")
          <> O.jsonBuildObjectField "reviewedObligations"
            (O.sqlArray id [O.jsonBuildObject $ O.jsonBuildObjectField "intent" identifier])
    O.where_ (receipt O..== S.depositId source O..&& json proof O..@> json subject)
    approved<-E.exists $ do
      (key,n)<-S.sourceApprovals
      O.where_ (key O..== identifier O..&& n O..>= sequenceNo)
      pure ()
    O.where_ (O.not approved)
    pure ()
  covered<-E.exists $ do
    receipt<-S.accountedLosses
    (cover,key,quantity,_,_)<-S.activeSourceCovers
    (payment,_,_,_,_,_,proof,n)<-O.selectTable S.sourceRecoveryDecisions
    O.where_ (receipt O..== S.depositId source O..&& key O..== receipt O..&& quantity O..== S.depositAmount source
      O..&& payment O..== identifier O..&& n O..> cover
      O..&& json proof O..@> json (O.jsonBuildObject $ O.jsonBuildObjectField "sourceCover" cover))
    pure ()
  O.where_ (pending O..|| (S.depositEligible source O..== O.sqlInt8 0 O..&& O.not covered))
  pure ()
 where
  -- Fixed typed cast of the schema-checked JSON text, never caller SQL.
  json :: O.Field a -> O.Field O.SqlJsonb
  json=O.unsafeCastSqlType

-- Queue/display filter only. The locked preparation decision also validates the
-- full bounded generation history, source, holds, current budget and readiness.
successorReady :: S.TextField -> O.Select (O.Field O.SqlBool)
successorReady identifier = do
  previous<-E.exists $ do
    (key,_,_,_,_,_)<-S.workPreparations
    O.where_ (key O..== identifier)
    pure ()
  successor<-E.exists $ do
    (key,g,_,_,retired,cancelled)<-S.workPreparations
    O.where_ (key O..== identifier O..&& g O..< O.sqlInt8 7)
    cleanup<-E.exists $ do
      (payment,generation,_,_,done)<-S.workCancellations
      O.where_ (payment O..== key O..&& generation O..== g O..&& done O..== O.sqlInt8 1
        O..&& cancelled O..== O.sqlInt8 1 O..&& O.isNull retired)
      pure ()
    expiry<-E.exists $ do
      (tx,_,_,_)<-O.selectTable S.solanaRetryApprovals
      O.where_ (O.matchNullable (O.sqlBool False) (O..== tx) retired O..&& cancelled O..== O.sqlInt8 0)
      pure ()
    later<-E.exists $ do
      (payment,generation,_,_,_,_)<-S.workPreparations
      O.where_ (payment O..== key O..&& generation O..> g)
      pure ()
    remaining<-E.exists $ do
      (tx,payment,_,_,_,_)<-S.workAttempts
      expired<-E.exists $ do
        (saved,_,_)<-O.selectTable S.solanaExpiries
        O.where_ (saved O..== tx)
        pure ()
      O.where_ (payment O..== key O..&& O.not expired)
      pure ()
    O.where_ ((cleanup O..|| expiry) O..&& O.not later O..&& O.not remaining)
    pure ()
  pure (O.not previous O..|| successor)
