-- Independent accounting oracle for lifecycle extraction. Expected values never
-- call Domain.settlement. PostgreSQL contracts cover durable commits; this model
-- compares the extracted decisions with independent accounting and old histories.
module LifecycleCheck (checks, payoutSafetyChecks, payoutGroupChecks) where

import Bridge.Domain hiding (fee)
import Bridge.Lifecycle
import qualified Bridge.Wire as W
import Bridge.Wire (PaymentTerms(..),CostLimits(..),PolicySnapshot(..),SignedAttempt(..),PaymentCosts(..))
import Control.Monad (foldM)
import Data.Aeson (Value(Null),object,(.=),encode)
import qualified Data.ByteString.Lazy as BL
import Data.Int (Int64)
import Data.List (nub,isPrefixOf)
import qualified Data.Map.Strict as M
import qualified Data.Set as Set
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Test.QuickCheck

-- Release-blocking regressions: no expected-failure wrapper. These must pass
-- before the unfinished strict-batching implementation may be published.
payoutSafetyChecks :: IO [Result]
payoutSafetyChecks = sequence
  [ check "an unfunded quote cannot borrow inventory from a round that can seal first" $ once $
      let facts=customerAdmission {queuedOrders=1,availableFloat=10}
      in counterexample "ready 100 can leave before new net 9 arrives; only 1 unit then remains to close its 100-unit round" $
        rejected (capacity 100 Wrapped 100 customerLimits facts NativeToWrapped 10)
  , check "opposite-direction intake preserves fees needed to close an existing small batch" $ once $
      let first=customerAdmission {nativeOrderBudget=budget 20 0,solanaOrderBudget=budget 40 0}
          after=first {queuedOrders=1,nativeOrderBudget=budget 20 10,solanaOrderBudget=budget 40 20}
      in counterexample "first net 9 needs a later closer; opposite net 100 consumes its last 10 native/20 SOL fee units" $
        not (capacity 100 Wrapped 0 customerLimits first NativeToWrapped 10==Right ()
          && capacityWith 100 customerLimits after WrappedToNative 102 [batch 100 Wrapped 9]==Right ())
  , check "batch headroom reserves every required closer, not just one queue slot" $ once $
      let threshold=toInteger(maxBound::Int64)
          facts=customerAdmission {availableFloat=threshold}
          limits=customerLimits {maximumQueued=2}
          largestNet=toInteger $ units $ net $ good $ quote $ money threshold
      in counterexample "net 1 plus the largest representable quote cannot reach the threshold with one remaining slot" $
        1+largestNet<threshold && rejected (capacity threshold Native 0 limits facts WrappedToNative 2)
  , check "reserved inventory remains usable by the order that completes a funded batch" $ once $
      let first=customerAdmission {availableFloat=100,nativeOrderBudget=budget 20 0,solanaOrderBudget=budget 40 0}
          after=first {queuedOrders=1,availableFloat=91,nativeOrderBudget=budget 20 10,solanaOrderBudget=budget 40 20}
      in counterexample "after admitted net 9 funds, the remaining 91 must admit gross 92/net 91 to complete the batch" $
        capacity 100 Wrapped 0 customerLimits first NativeToWrapped 10/=Right ()
        || capacity 100 Wrapped 9 customerLimits after NativeToWrapped 92==Right ()
  , check "higher current fees protect old batches while allowing their real closer" $ once $
      let facts=customerAdmission {queuedOrders=1,availableFloat=100,
            nativeOrderBudget=budget 40 10,solanaOrderBudget=budget 80 20}
          costs=CostLimits (money 20) (money 30) (money 10)
          decide direction input=decideBatchOrder (W.PayoutPolicy (money 100) (money 100) 0)
            customerLimits costs (customerRequest direction input) facts [batch 100 Wrapped 9]
      in conjoin [counterexample "unrelated intake spends the fee increase" $ decide WrappedToNative 102===Left "insufficient_fee_budget"
         ,counterexample "saved batch cannot consume its increased allowance" $ case decide NativeToWrapped 92 of
             Right (Just "existing",_)->True
             _->False]
  , check "free-capital consumers retain inventory and the higher saved/current closing fees" $ once $
      let outstanding=batch 100 Wrapped 9
      in conjoin
        [batchClosingCapacity customerCosts outstanding===Right (ClosingCapacity 91 1 10 20)
        ,batchClosingCapacity (CostLimits (money 20) (money 30) (money 10)) outstanding
          ===Right (ClosingCapacity 91 1 20 40)
        ,batchClosingCapacity (CostLimits (money 1) (money 1) (money 1)) outstanding
          ===Right (ClosingCapacity 91 1 10 20)
        ,batchClosingCapacity customerCosts outstanding {batchCommitted=100}
          ===Right (ClosingCapacity 0 0 0 0)]
  , check "depleted closing headroom permits zero debit without hiding actual insolvency" $
      forAll (chooseInteger (0,1000000)) $ \available->
      forAll (chooseInteger (0,1000000)) $ \reserved->
        conjoin [spendableAfterClosing available reserved===max 0 (available-reserved)
          ,spendableAfterClosing (-1) reserved===(-1)
          ,property (spendableAfterClosing available reserved<=available)]
  , check "fee reallocation preserves reserved refunds but protects closers from new spending" $ once $
      conjoin
        [checkFeeReallocation (money 10) 10 100 (budget 10 10)===Right ()
        ,checkFeeReallocation (money 11) 10 20 (budget 30 10)===Left "insufficient_fee_budget"
        ,checkFeeReallocation (money 11) 10 20 (budget 31 10)===Right ()
        ,checkFeeReallocation (money 10) 0 20 (budget 20 0)===Left "insufficient_fee_budget"
        ,checkFeeReallocation (money 10) 20 100 (budget 100 10)===Left "operating_reservation_missing"]
  , check "owner admission shares closing capacity but uses earned principal" $ once $
      let decide asset n limits facts groups=checkBatchMember (W.PayoutPolicy (money 100) (money 100) 0)
            limits customerCosts (BatchMember asset (money n) (money 0) [(if asset==Native then Native else Sol,money (if asset==Native then 10 else 20))]) facts groups
          existing=batch 100 Wrapped 9
          funded=customerAdmission {queuedOrders=1,availableFloat=0,nativeOrderBudget=budget 20 10,solanaOrderBudget=budget 40 20}
      in conjoin
        [decide Wrapped 91 customerLimits funded [existing]===Right (Just "existing")
        ,decide Native 100 customerLimits funded [existing]===Left "insufficient_fee_budget"
        ,decide Wrapped 1 customerLimits funded [existing]===Left "payout_batch_needs_inventory"
        ,decide Wrapped 91 customerLimits {maximumQueued=1} funded [existing]===Left "payout_batch_needs_capacity"]
  , check "owner cancellation cannot strand an unsealed customer's closer" $ once $
      let after=customerAdmission {queuedOrders=1,availableFloat=90}
          groups=[batch 100 Wrapped 9]
      in conjoin
        [checkBatchResources customerLimits customerCosts Wrapped after groups===Left "payout_batch_needs_inventory"
        ,checkBatchResources customerLimits customerCosts Wrapped after {availableFloat=91} groups===Right ()
        ,checkBatchResources customerLimits {maximumQueued=1} customerCosts Wrapped after {availableFloat=91} groups
          ===Left "payout_batch_needs_capacity"]
  ]
 where
  check name test=putStrLn name >> quickCheckWithResult stdArgs test
  budget balance held=FeeBudget balance held 0 (money 1000000000)
  rejected (Left _)=True
  rejected (Right _)=False
  batch threshold asset committed=BatchCapacity "existing" asset (money threshold) committed (money 10) (money 20) 100
  capacity threshold asset waiting limits facts direction input =
    capacityWith threshold limits facts direction input [batch threshold asset waiting | waiting>0]
  capacityWith threshold limits facts direction input batches =
    -- Baseline order admission must succeed; unrelated quote rejection is not
    -- evidence that the batch-capacity invariant holds.
    let request=customerRequest direction input
        admitted=good $ decideOrder limits customerCosts request facts
    in admitted `seq` (() <$ decideBatchOrder (W.PayoutPolicy (money threshold) (money threshold) 0)
      limits customerCosts request facts batches)

-- Candidate ownership protocol, independent of Store. This models exact quoted
-- deposits and immediate wrong-amount refunds. Amounts are net units. Pending
-- and funded conversions retain both fee allowances, as Store does. Only refunds
-- release the conversion allowance. Reorgs, late receipts and fee-policy changes
-- remain outside this model; passing it is not Store acceptance.
data BatchReceipt = PendingReceipt | ConversionReceipt | RefundReceipt deriving (Eq,Show)
data BatchModel = BatchModel Bool Asset [(Integer,BatchReceipt)] deriving (Eq,Show)
data CapacityModel = CapacityModel Integer Integer Integer Integer [BatchModel] deriving (Eq,Show)
data BatchStep = Offer Asset Integer | Fund Int Int | Expire Int Int | Seal Int | Pay Int | WrongAmount Int Int Integer
  deriving Show

payoutGroupChecks :: IO [Result]
payoutGroupChecks = putStrLn "Candidate batch ownership model (not Store acceptance)" >> sequence
  [ quickCheckWithResult stdArgs {maxSuccess=1000} $ forAll scenario $ \(threshold,start,actions)->
      let states=scanl (advance threshold) start actions
          changes=zip3 actions states (drop 1 states)
          exercised select=any (\(action,before,after)->select action && before/=after) changes
          paid Pay{}=True; paid _=False
          expired Expire{}=True; expired _=False
          refunded WrongAmount{}=True; refunded _=False
          both (CapacityModel _ _ _ _ batches)=all (\asset->any (\(BatchModel _ a _)->a==asset) batches) [Native,Wrapped]
      in checkCoverage $ cover 1 (exercised paid) "settlement"
        $ cover 5 (exercised expired) "expiry"
        $ cover 5 (exercised refunded) "immediate refund"
        $ cover 10 (any both states) "both assets"
        $ cover 5 (any (\(CapacityModel _ _ _ _ batches)->any ((>1).closers threshold) batches) states) "multiple closers"
        $ counterexample (show $ zip (Nothing:map Just actions) states)
          (all (solvent threshold) states && all conserved changes && all wellFormed states
            && all assigned changes
            && all (headroomMatches threshold) states
            && all (admissionMatches threshold) changes
            && all (capacityPreserved threshold) changes && all (closingProgress threshold) states)
  , quickCheckResult $ once $
      let bound=toInteger(maxBound::Int64); maximumAmount=money bound
      in conjoin
        [closingCapacity maximumAmount 1 maximumAmount maximumAmount
          ===Right (ClosingCapacity (bound-1) 2 (2*bound) (2*bound))
        ,closingCapacity (money 100) 0 (money 10) (money 20)===Right (ClosingCapacity 0 0 0 0)
        ,closingCapacity (money 100) 100 (money 10) (money 20)===Right (ClosingCapacity 0 0 0 0)
        ,closingCapacity (money 0) 1 (money 10) (money 20)===Left "invalid_payout_capacity"
        ,closingCapacity (money 100) (-1) (money 10) (money 20)===Left "invalid_payout_capacity"]
  , quickCheckResult $ once $
      let offered=advance 100 initial (Offer Wrapped 9)
          funded=advance 100 offered (Fund 0 0)
          closed=advance 100 (advance 100 funded (Offer Wrapped 91)) (Fund 0 1)
          paid=advance 100 (advance 100 (advance 100 closed (Seal 0)) (Pay 0)) (Pay 0)
      in counterexample "admitted funded net9 must retain usable capacity for its exact net91 closer" $
        case paid of CapacityModel 100 0 20 0 []->True; _->False
  , quickCheckResult $ once $
      let start=CapacityModel 100 200 20 40 []
          first=advance 100 start (Offer Wrapped 100)
          second=advance 100 first (Offer Wrapped 100)
          funded=advance 100 second (Fund 1 0)
          paid=advance 100 (advance 100 funded (Seal 1)) (Pay 1)
      in counterexample "independently funded cohort must pay while an earlier full cohort awaits its receipt" $
        paid==CapacityModel 100 100 20 20 [BatchModel False Wrapped [(100,PendingReceipt)]]
  , quickCheckResult $ once $
      let open=advance 100 initial (Offer Wrapped 9)
          blocked=advance 100 open (Offer Native 100)
      in blocked==open
  , quickCheckResult $ once $
      conjoin [let start=CapacityModel 100 100 nativeFees solFees []
                   before=advance 100 (advance 100 start (Offer asset 50)) (Offer asset 50)
                   after=advance 100 before (WrongAmount 0 0 49)
                   paid=advance 100 after (Pay 1)
                   replaced=advance 100 paid (Offer asset 50)
               in counterexample ("one refund must leave its replacement usable: "<>show replaced) $
                 fits 100 after && fits 100 paid && paid/=after && replaced/=paid
              | (asset,nativeFees,solFees)<-[(Wrapped,30,40),(Native,20,60)]]
  , quickCheckResult $ once $
      let first=advance 100 initial (Offer Wrapped 50)
          second=advance 100 first (Offer Wrapped 50)
          refunded=advance 100 second (WrongAmount 0 0 49)
          paid=advance 100 refunded (Pay 1)
      in counterexample "spent refund fee requires replenishment, never borrowing actual liabilities" $
        second/=first && solvent 100 refunded && solvent 100 paid
          && not(fits 100 paid) && advance 100 paid (Offer Native 100)==paid
  ]
 where
  initial=CapacityModel 100 100 20 40 []
  largestNet=toInteger $ units $ net $ good $ quote $ money $ toInteger(maxBound::Int64)
  remaining threshold (BatchModel sealed _ quotes)
    | sealed || null quotes=0
    | otherwise=max 0 (threshold-sum(map fst quotes))
  -- A real pending closer consumes the virtual allocation instead of being
  -- counted alongside it. Wrong deposits may spend the refund allowance and
  -- leave closing capacity needing replenishment, never an unfunded liability.
  closers threshold batch=(remaining threshold batch+largestNet-1) `div` largestNet
  -- Compare the production calculation with the independent model after every
  -- transition, including expiry, refunds and multiple legal closing quotes.
  headroomMatches threshold (CapacityModel _ _ _ _ batches)=and
    [closingCapacity (money threshold) (sum $ map fst members) (money 10) (money 20)
      ==Right (ClosingCapacity (remaining threshold batch) (closers threshold batch)
        (10*closers threshold batch) (20*closers threshold batch))
    | batch@(BatchModel False _ members)<-batches]
  required threshold asset batches=sum [sum(map fst quotes)+remaining threshold batch
    | batch@(BatchModel _ currency quotes)<-batches,currency==asset]
  fits threshold (CapacityModel native wrapped nativeFees solFees batches)=
    native>=required threshold Native batches && wrapped>=required threshold Wrapped batches
      && nativeFees>=feesHeld threshold Native batches && solFees>=feesHeld threshold Sol batches
      && sum [toInteger(length quotes)+closers threshold batch | batch@(BatchModel _ _ quotes)<-batches]<=10
  feesHeld threshold currency batches=sum
    [(if currency==Native then 10 else 20)*(closers threshold batch+toInteger(length
      [() | (_,receipt)<-quotes,receipt/=RefundReceipt || (asset==Native)==(currency==Native)]))
    | batch@(BatchModel _ asset quotes)<-batches]
  admissionMatches threshold (action@(Offer asset quantity),before@(CapacityModel native wrapped nativeFees solFees batches),after)=
    let actual=[BatchModel True a members | BatchModel _ a members<-batches]
        request=customerRequest (if asset==Wrapped then NativeToWrapped else WrappedToNative)
          (quantity+(quantity+98) `div` 99)
        facts=customerAdmission
          { queuedOrders=sum [length members | BatchModel _ _ members<-batches]
          , availableFloat=(if asset==Native then native else wrapped)-required threshold asset actual
          , nativeOrderBudget=FeeBudget nativeFees (feesHeld threshold Native actual) 0 (money 1000000)
          , solanaOrderBudget=FeeBudget solFees (feesHeld threshold Sol actual) 0 (money 1000000) }
        saved=[BatchCapacity (T.pack $ show i) a (money threshold) (sum $ map fst members)
          (money 10) (money 20) 10 | (i,BatchModel False a members)<-zip [0::Int ..] batches]
        result=decideBatchOrder (W.PayoutPolicy (money threshold) (money threshold) 0)
          customerLimits {maximumQueued=10} customerCosts request facts saved
    in case result of Right _->before/=after; Left _->before==after
  admissionMatches _ _=True
  -- Safety is unconditional. Closing progress is conditional on intact closing
  -- capacity: finite fee balances cannot cover unlimited wrong-deposit refunds.
  solvent threshold (CapacityModel native wrapped nativeFees solFees batches)=
    let actual=[BatchModel True asset members | BatchModel _ asset members<-batches]
    in fits threshold (CapacityModel native wrapped nativeFees solFees actual)
  capacityPreserved threshold (action,before,after)=case action of
    WrongAmount{} -> True -- the actual liability still must pass solvent
    _ -> not(fits threshold before) || fits threshold after
  closingProgress threshold state@(CapacityModel _ _ _ _ batches)=
    not(fits threshold state) || all usable
      [first | asset<-[Native,Wrapped],
        let candidates=[batch | batch@(BatchModel False currency _)<-batches,currency==asset,remaining threshold batch>0],
        first:_<-[candidates]]
   where
    usable batch@(BatchModel sealed asset members)=
      sealed || any ((==PendingReceipt).snd) members || remaining threshold batch==0
        || advance threshold state (Offer asset $ min largestNet $ remaining threshold batch)/=state
  clean=filter (\(BatchModel _ _ quotes)->not(null quotes))
  modifyAt index change values=[if n==index then change value else value | (n,value)<-zip [0..] values]
  advance threshold state@(CapacityModel native wrapped nativeFees solFees batches) action=case action of
    Offer asset quantity ->
      let targets=[index | (index,batch@(BatchModel sealed currency _))<-zip [0..] batches,
            not sealed,currency==asset,remaining threshold batch>0]
          add (BatchModel sealed currency quotes)=BatchModel sealed currency (quotes<>[(quantity,PendingReceipt)])
          candidate=case targets of
            []->batches<>[BatchModel False asset [(quantity,PendingReceipt)]]
            index:_->modifyAt index add batches
          next=CapacityModel native wrapped nativeFees solFees candidate
      in if quantity>0 && quantity<=largestNet && fits threshold next then next else state
    WrongAmount group member quantity ->case drop group batches of
      BatchModel False target quotes:_ | quantity>0 && quantity<=toInteger(maxBound::Int64)
        ,(_,PendingReceipt):_<-drop member quotes ->
          let source=if target==Native then Wrapped else Native
              retained=clean $ modifyAt group (const $ BatchModel False target
                [quote | (index,quote)<-zip [0..] quotes,index/=member]) batches
              -- Refunds have independent immediate admission, never borrowing a
              -- conversion group's threshold or changing its scheduling clock.
              refunded=retained<>[BatchModel True source [(quantity,RefundReceipt)]]
          in CapacityModel (native+if source==Native then quantity else 0)
            (wrapped+if source==Wrapped then quantity else 0) nativeFees solFees refunded
      _->state
    Fund group member ->CapacityModel native wrapped nativeFees solFees $ modifyAt group
      (\(BatchModel sealed asset quotes)->BatchModel sealed asset $ modifyAt member (\(n,receipt)->(n,if receipt==PendingReceipt then ConversionReceipt else receipt)) quotes) batches
    Expire group member ->CapacityModel native wrapped nativeFees solFees $ clean $ modifyAt group
      (\batch@(BatchModel sealed asset quotes)->if sealed then batch else BatchModel False asset
        [quote | (index,quote@(_,receipt))<-zip [0..] quotes,index/=member || receipt/=PendingReceipt]) batches
    Seal group ->CapacityModel native wrapped nativeFees solFees $ modifyAt group
      (\batch@(BatchModel _ asset quotes)->if not(null quotes) && all ((==ConversionReceipt).snd) quotes && sum(map fst quotes)>=threshold
        then BatchModel True asset quotes else batch) batches
    Pay group ->case drop group batches of
      BatchModel True asset ((quantity,_):quotes):_ ->CapacityModel
        (native-if asset==Native then quantity else 0)
        (wrapped-if asset==Wrapped then quantity else 0)
        (nativeFees-if asset==Native then 10 else 0) (solFees-if asset==Wrapped then 20 else 0) $
          clean $ modifyAt group (const $ BatchModel True asset quotes) batches
      _->state
  wellFormed (CapacityModel _ _ _ _ batches)=all
    (\(BatchModel sealed _ members)->not(null members) && all (\(_,receipt)->receipt/=RefundReceipt || sealed) members) batches
  -- Admission may append to exactly one existing cohort, or create a new one.
  -- It cannot move existing promises into a different cohort to free resources.
  assigned (Offer{},before@(CapacityModel _ _ _ _ old),after@(CapacityModel _ _ _ _ new))
    | before/=after = length new>=length old && length new<=length old+1
      && sum(map count new)==sum(map count old)+1
      && and [asset==asset' && sealed==sealed' && members `isPrefixOf` members'
        | (BatchModel sealed asset members,BatchModel sealed' asset' members')<-zip old new]
   where count (BatchModel _ _ members)=length members
  assigned _=True
  conserved (action,before@(CapacityModel n w nf sf batches),after@(CapacityModel n' w' nf' sf' _))=case action of
    WrongAmount group member quantity | before/=after ->case drop group batches of
      BatchModel False target quotes:_ | (_,PendingReceipt):_<-drop member quotes ->nf==nf' && sf==sf'
        && n'-n==(if target==Wrapped then quantity else 0)
        && w'-w==(if target==Native then quantity else 0)
      _->False
    Pay group | before/=after ->case drop group batches of
      BatchModel True asset ((quantity,receipt):_):_ | receipt/=PendingReceipt ->nf-nf'==(if asset==Native then 10 else 0) && sf-sf'==(if asset==Wrapped then 20 else 0)
        && n-n'==(if asset==Native then quantity else 0)
        && w-w'==(if asset==Wrapped then quantity else 0)
      _->False
    _->(n,w,nf,sf)==(n',w',nf',sf')
  scenario=do
    threshold<-elements [100,toInteger(maxBound::Int64)]
    start<-CapacityModel <$> chooseInteger (threshold,5*threshold) <*> chooseInteger (threshold,5*threshold) <*> chooseInteger (20,200) <*> chooseInteger (40,400) <*> pure []
    actions<-steps threshold
    pure(threshold,start,actions)
  groupIndex=frequency [(3,pure 0),(1,chooseInt (0,3))]
  steps threshold=resize 100 $ listOf $ oneof
    [Offer <$> elements [Native,Wrapped] <*> elements [1,9,threshold `div` 2,min largestNet (threshold-9),min largestNet threshold]
    ,Fund <$> groupIndex <*> chooseInt (0,2)
    ,Expire <$> groupIndex <*> chooseInt (0,2)
    ,Seal <$> groupIndex,Pay <$> groupIndex
    ,WrongAmount <$> groupIndex <*> chooseInt (0,2) <*> chooseInteger (1,99)]

data FundingCase = Convert Direction Integer Integer | Return Asset Integer | Revenue Asset Integer
  deriving (Eq,Show)
data History = History [FundingCase] [Int] deriving Show
type Balances = M.Map (Asset,Account) Integer

checks :: IO [Result]
checks = (++) <$> ((++) <$> payoutSafetyChecks <*> payoutGroupChecks) <*> sequence
  [ check "payout admission uses aggregate net amounts and the previous committed interval" $
      forAll (chooseInteger (1,1000000)) $ \n->forAll (chooseInt (0,1000)) $ \wait->
        let policy=W.PayoutPolicy (money $ 2*n) (money $ 3*n) 0
            due asset now amounts=payoutRoundDue policy asset now (Just(100,fromIntegral wait)) amounts
        in conjoin [due Native (100+fromIntegral wait) [money n,money n]===Right True
          ,due Wrapped (100+fromIntegral wait) [money n,money n]===Right False
          ,due Native (99+fromIntegral wait) [money n,money n]===Right (wait==0)
          ,payoutRoundDue policy Native 0 Nothing [money n,money n]===Right True
          ,payoutRoundDue policy Native 0 Nothing []===Right False]
  , check "payout totals and deadlines cannot overflow signed base units or timestamps" $ once $
      let big=money(toInteger(maxBound::Int64)); policy=W.PayoutPolicy big big 31536000
      in conjoin [payoutRoundDue policy Native 0 Nothing (replicate 1000 big)===Right True
        ,payoutRoundDue policy Native maxBound (Just(maxBound,1)) [big]===Right False
        ,payoutRoundDue policy Sol 0 Nothing [big]===Left "invalid_payout_round"
        ,checkPayoutPolicy policy {W.payoutIntervalSeconds=31536001}===Left "invalid_payout_policy"
        ,checkPayoutPolicy policy {W.nativePayoutThreshold=money 0}===Left "invalid_payout_policy"]
  , check "small orders preserve the slot inventory and fees needed to finish a payout batch" $
      forAll (chooseInteger (2,1000000)) $ \threshold->
      forAll (elements [NativeToWrapped,WrappedToNative]) $ \direction->
        let policy=W.PayoutPolicy (money threshold) (money threshold) 0
            limits=customerLimits {maximumQueued=3}
            facts=customerAdmission {queuedOrders=2,availableFloat=threshold}
            checkWith l f n=() <$ decideBatchOrder policy l customerCosts (customerRequest direction n) f []
            closingInput=threshold+(threshold+98) `div` 99
            room=limits {maximumQueued=4}
        in conjoin
          [checkWith limits facts 2===Left "payout_batch_needs_capacity"
          ,checkWith limits facts closingInput===Right ()
          ,checkWith room facts 2===Right ()
          ,checkWith room facts {availableFloat=threshold-1} 2===Left "payout_batch_needs_inventory"
          ,checkWith room facts {solanaOrderBudget=FeeBudget 39 0 0 (money 100)} 2===Left "insufficient_fee_budget"
          ,checkWith room facts {nativeOrderBudget=FeeBudget 19 0 0 (money 100)} 2===Left "insufficient_fee_budget"
          ,checkWith room facts {solanaOrderBudget=FeeBudget 40 0 0 (money 39)} 2===Left "operating_daily_limit"
          ,checkWith limits facts {solanaOrderBudget=FeeBudget 20 0 0 (money 20)} closingInput===Right ()]
  , check "two legal closers reserve two slots and both fee budgets without overflow" $ once $
      let threshold=toInteger(maxBound::Int64)
          policy=W.PayoutPolicy (money threshold) (money threshold) 0
          limits=customerLimits {maximumQueued=3}
          facts=customerAdmission {availableFloat=threshold,
            nativeOrderBudget=FeeBudget 30 0 0 (money 30),solanaOrderBudget=FeeBudget 60 0 0 (money 60)}
          capacity l f=() <$ decideBatchOrder policy l customerCosts (customerRequest WrappedToNative 2) f []
      in conjoin [capacity limits facts===Right ()
        ,capacity limits {maximumQueued=2} facts===Left "payout_batch_needs_capacity"
        ,capacity limits facts {nativeOrderBudget=FeeBudget 29 0 0 (money 30)}===Left "insufficient_fee_budget"
        ,capacity limits facts {solanaOrderBudget=FeeBudget 60 0 0 (money 59)}===Left "operating_daily_limit"]
  , check "economic phase round trips with one original principal event across winner changes" $
      forAll (chooseInt (0,7)) $ \generation->forAll (chooseInteger (0,1000000)) $ \nonce->
        let old=T.pack(show nonce); winner="winner-"<>old; original="settlement:"<>old
            phases=[Ready,Active generation,Settled winner original,Cancelled]
        in conjoin ([decodePaymentPhase(encodePaymentPhase phase)===Right phase | phase<-phases]
          <>[encodePaymentPhase(Settled "other-winner" original)===("settled",Nothing,Just "other-winner",Just original)])
  , check "economic phase refuses review mixed states and incomplete or out-of-range identities" $ once $
      conjoin [decodePaymentPhase fields===Left "invalid_payment_phase" | fields<-
        [("review",Nothing,Nothing,Nothing),("ready",Just 0,Nothing,Nothing)
        ,("cancelled",Nothing,Just "tx",Nothing),("active",Nothing,Nothing,Nothing)
        ,("active",Just(-1),Nothing,Nothing),("active",Just 8,Nothing,Nothing)
        ,("active",Just(maxBound::Int64),Nothing,Nothing),("active",Just 0,Just "tx",Nothing)
        ,("settled",Just 0,Just "tx",Just "settlement:tx"),("settled",Nothing,Nothing,Just "settlement:tx")
        ,("settled",Nothing,Just "",Just "settlement:tx"),("settled",Nothing,Just "tx",Nothing)
        ,("settled",Nothing,Just "tx",Just "network-fee:tx"),("settled",Nothing,Just "tx",Just "settlement:")
        ,("settled",Nothing,Just(T.replicate 161 "x"),Just "settlement:tx")
        ,("settled",Nothing,Just "tx",Just("settlement:"<>T.replicate 161 "x"))]]
  , check "lifecycle accounting agrees with an independent funding model" $
      forAllShrink fundingCases shrinkFunding $ \funding ->
        aggregate (settlement $ outgoing 0 funding) === expected funding
  , check "bounded delivery histories preserve principal identity and protected accounts" $
      forAllShrink histories shrinkHistory $ \history ->
        let actual=good $ decisions history; wanted=model history
        in conjoin [actual===wanted, actual===baseline history, property $ all (==0)
             [M.findWithDefault 0 (asset,account) actual | asset<-[Native,Wrapped,Sol],account<-[Backing,Liquidity,SourceDeficit]]]
  , check "model rejects deliberately duplicated principal" $ expectFailure $ once $
      let funding=Convert NativeToWrapped 100 1; history=History [funding] [0,0]
      in aggregate (concatMap (const $ settlement $ outgoing 0 funding) [0::Int,0]) === model history
  , check "model rejects deliberately altered fee accounting" $ expectFailure $ once $
      let funding=Convert WrappedToNative 100 1
      in M.adjust (+1) (Wrapped,Earned) (aggregate $ settlement $ outgoing 0 funding) === expected funding
  , check "settlement snapshot preserves funding and separates verified network costs" $
      forAllShrink fundingCases shrinkFunding $ \funding -> forAll (chooseInt (0,7)) $ \generation ->
        let facts=snapshot 0 funding
            queued=(settlementCurrent facts) {recordedGeneration=generation}
            current=facts {settlementCurrent=queued}
            outcome=successful current
            effect=case good (decideSettlement queued current outcome) of ApplySettlement x->x; _->error "new settlement replayed"
            expectedCustomer=case funding of
              Convert{}->Just(CustomerResolution "order-payment-0" False "Paid")
              Return{}->Just(CustomerResolution "order-payment-0" True "Refunded")
              Revenue{}->Nothing
        in conjoin [aggregate(settlementPrincipal effect)===expected funding
             ,settlementOutcome effect===outcome,settlementCustomer effect===expectedCustomer
             ,property $ all ((/=Operating).postingAccount) (settlementPrincipal effect)]
  , check "finalized Solana failure books only its exact fee and replay requires it" $
      forAll (chooseInteger (1,10)) $ \fee ->
        let facts=snapshot 0 (Convert NativeToWrapped 100 1); queued=settlementCurrent facts
            outcome=Failed (money fee) "failure-proof"
            effect=case good(decideSettlement queued facts outcome) of ApplySettlement x->x; _->error "new failure replayed"
            repeated=finished facts outcome
        in conjoin [settlementPrincipal effect===[],outcomeCosts outcome===PaymentCosts (money fee) (money 0)
             ,settlementCustomer effect===Just(CustomerResolution "order-payment-0" False "NeedsReview")
             ,decideSettlement queued repeated outcome===Right SettlementReplay
             ,decideSettlement queued repeated {settlementFailedCharge=Just(fee+1)} outcome===Left "failure_evidence_conflict"]
  , check "settlement refuses changed identity generation bytes proof and missing authority" $ once $ property refusalCases
  , check "preparation through queue and settlement preserves exact saved payment" $
      forAllShrink fundingCases shrinkFunding $ \funding ->
        let facts=initialPreparation funding
            prepared=created $ good $ decidePreparation (money 10) "{}" facts
            queued=sendFacts funding prepared
            unsigned=queued {sendAttempt=(sendAttempt queued) {recordedState="signed",recordedSequence=Nothing}}
            replay=facts {preparationPayment=preparedView prepared
              ,preparationHistory=LivePreparation (recordedChain $ sendAttempt queued) prepared,preparationAdmission=Nothing}
        in conjoin
          [ savedPayment(preparedView prepared)===savedPayment(preparationPayment facts)
          , decidePreparation (money 10) "{}" replay===Right(ReusePreparation prepared)
          , decidePreparation (money 10) "{\"changed\":true}" replay===Left "preparation_conflict"
          , decideQueue unsigned===Right CreateQueue
          , decideQueue queued===Right(ReuseQueue 5)
          , decideSend unsigned===Left "broadcast_intent_required"
          , decideSend queued {sendBackupSequence=4}===Left "backup_pending"
          , decideSend queued===Right(sendAttempt queued)
          , decideSend queued {sendReviewSequence=6}===Left "backup_pending"
          , decideSend queued {sendReviewSequence=6,sendBackupSequence=6}===Right(sendAttempt queued)
          , decisions (History [funding] [0,0,0])===Right(expected funding) ]
  , check "authorized retry replaces only its own prior fee hold" $
      forAllShrink fundingCases shrinkFunding $ \funding -> forAll (chooseInt (1,7)) $ \generation ->
      forAll arbitrary $ \expired ->
        let original=initialPreparation funding; admission=admitted original
            chain=recordedChain(settlementCurrent $ snapshot 0 funding)
            currency=if chain=="Native" then Native else Sol
            facts=original {preparationHistory=RetiredPreparation chain (Just generation)
              ,preparationAdmission=Just admission {priorPreparationFee=Just(PriorFeeHold currency (money 10) expired expired)
                ,initialOperatingHold=Nothing,preparationBudget=FeeBudget 1000 (if expired then 0 else 10) 0 (money 1000)}}
            result=created $ good $ decidePreparation (money 10) "{}" facts
        in conjoin [preparedGeneration result===generation,preparedFee result===money 10
             ,savedPayment(preparedView result)===savedPayment(preparationPayment original)
             ,decidePreparation (money 10) "{}" facts {preparationHistory=RetiredPreparation chain Nothing}===Left "preparation_retry_not_authorized"
             ,decidePreparation (money 10) "{}" facts {preparationHistory=RetiredPreparation chain (Just 8)}===Left "preparation_generation_limit"]
  , check "reserved refund preparation survives a closing shortfall but a larger retry does not" $ once $
      let original=initialPreparation (Return Native 100)
          admission=(admitted original) {preparationBudget=FeeBudget 20 20 0 (money 1000),preparationClosingFees=100}
          reserved=original {preparationAdmission=Just admission}
          retry=original {preparationHistory=RetiredPreparation "Native" (Just 1)
            ,preparationAdmission=Just admission {initialOperatingHold=Nothing
              ,priorPreparationFee=Just(PriorFeeHold Native (money 5) False False)
              ,preparationBudget=FeeBudget 25 5 0 (money 1000),preparationClosingFees=20}}
      in conjoin
        [property (case decidePreparation (money 10) "{}" reserved of Right CreatePreparation{}->True; _->False)
        ,decidePreparation (money 10) "{}" retry===Left "insufficient_fee_budget"
        ,property (case decidePreparation (money 5) "{}" retry of Right CreatePreparation{}->True; _->False)]
  , check "preparation rejects invalid plans missing holds and shared budget exhaustion" $ once preparationRefusals
  , check "queue and send reject changed generation stale readiness and replacement selection" $ once sendRefusals
  , check "readiness uses the exact sixty-second boundary without extending time" $
      forAll (chooseInteger (0,toInteger(maxBound::Int64)-61)) $ \time ->
        let now=fromInteger time
            facts=readyIntake {intakeTime=now,intakeScans=Just((now,"n"),(now,"t"),(now,"s")),intakeCustody=Just(3,3,now)}
        in conjoin [checkIntake facts===Right (),checkIntake facts {intakeTime=now+60}===Right ()
             ,checkIntake facts {intakeTime=now+61}===Left "scanners_not_fresh"
             ,checkIntake facts {intakeCustody=Just(4,3,now)}===Left "custody_not_reconciled"]
  , check "new admission uses ceiling one percent and retains both alternate cost holds" $
      forAll (chooseInteger (2,100000000)) $ \n -> forAll (elements [NativeToWrapped,WrappedToNative]) $ \direction ->
        let request=customerRequest direction n
            admitted=good $ decideOrder customerLimits customerCosts request customerAdmission
            charged=1+(n-1) `div` 100
            expectedCosts=if direction==NativeToWrapped then [("refund",Native,money 10),("conversion",Sol,money 20)]
              else [("conversion",Native,money 10),("refund",Sol,money 20)]
        in conjoin [net(admittedQuote admitted)===money(n-charged),admittedDeadline admitted===200,admittedGrace admitted===300
             ,admittedCosts admitted===expectedCosts
             ,decideOrder customerLimits customerCosts request customerAdmission {availableFloat=n-charged-1}===Left "insufficient_inventory"
             ,decideOrder customerLimits customerCosts request customerAdmission {nativeOrderBudget=FeeBudget 9 0 0 (money 1000000000)}===Left "insufficient_fee_budget"]
  , check "swaps have no arbitrary size bounds while net, reserves and withdrawal caps remain enforced" $ once $
      let largest=toInteger(maxBound::Int64)
          accepted direction n=
            let result=decideOrder customerLimits customerCosts (customerRequest direction n)
                  customerAdmission {availableFloat=largest}
            in case result of
              Right admitted->units(net $ admittedQuote admitted)==fromInteger(n-(n+99) `div` 100)
              Left _->False
      in conjoin
        [property $ and [accepted direction n | direction<-[NativeToWrapped,WrappedToNative],n<-[2,9999,100001,100000001,largest]]
        ,property $ and [quoteOrder(customerRequest direction n)==Left "nonpositive_net"
          | direction<-[NativeToWrapped,WrappedToNative],n<-[0,1]]
        ,amount(largest+1)===Left "amount_out_of_range"
        ,withdrawalInput (money 100) 100 (T.replicate 64 "a") Native (money 101) "owner" "earned"===Left "invalid_fee_withdrawal"]
  , check "native allocation retries never allocate twice or extend immutable instructions" $ once $
      let fresh=InstructionFacts NativeToWrapped "Provisioning" 200 Nothing Nothing 0
          saved=fresh {instructionStatus="AwaitingDeposit",savedInstruction=Just "owned-address",savedInstructionSequence=Just 4}
      in conjoin [decideNativeClaim "label" Nothing fresh (Just readyIntake)===Right(AllocationClaim "label" True)
           ,decideNativeClaim "label" (Just "label") fresh Nothing===Right(AllocationClaim "label" False)
           ,decideNativeClaim "other" (Just "label") fresh Nothing===Left "allocation_label_mismatch"
           ,decideInstruction saved "other-address"===Left "instruction_is_immutable"
           ,decideInstructionIssue True 3 saved Nothing===Left "backup_pending"
           ,decideInstructionIssue True 4 saved (Just(readyIntake,["quote"],["quote","quote"]))===Right True
           ,decideInstructionIssue True 4 saved {instructionIssued=1} Nothing===Right False
           ,decideInstructionIssue True 4 saved (Just(readyIntake {intakeTime=201},["quote"],["quote","quote"]))===Left "scanners_not_fresh"]
  , check "promotion preserves historical terms and refuses changed late additional or lost sources" $
      forAll (chooseInteger (2,100000000)) $ \n -> forAll (chooseInteger (0,n-1)) $ \charge ->
      forAll (elements [NativeToWrapped,WrappedToNative]) $ \direction ->
        let facts=customerPromotion direction n charge
            order=promotionOrder facts; receipt=promotionReceipt facts
            approved=case good(decidePromotion "fixture" 300 facts) of Just p->p; Nothing->error "promotion rejected"
            changed=receipt {W.depositAmount=money(n+1)}
        in conjoin [paymentAmount approved===money(n-charge),paymentRecipient approved===W.recipient(W.request order)
             ,decidePromotion "fixture" 301 facts===Right Nothing
             ,decidePromotion "fixture" 100 facts {promotionReceipt=changed}===Right Nothing
             ,decidePromotion "fixture" 100 facts {promotionReceipt=receipt {W.depositEligible=False}}===Right Nothing
             ,decidePromotion "fixture" 100 facts {conversionExists=True}===Right Nothing
             ,decidePromotion "other" 100 facts===Left "saved_order_terms_mismatch"]
  , check "mixed conversion refunds and earned withdrawals retain full principal and separate costs" $
      forAll (chooseInteger (2,1000000)) $ \n -> forAll (chooseInteger (1,1000)) $ \extra ->
      forAll (elements [NativeToWrapped,WrappedToNative]) $ \direction ->
        let order=promotionOrder $ customerPromotion direction n 1
            asset=sourceAsset direction; feeAsset=if asset==Native then Native else Sol
            allowance=if asset==Native then 10 else 20
            receipt=W.Deposit "extra" (Just "order") asset (money extra) "anchor" 2 True 110
            work=[("convert:order","original","paid")]
            facts=RefundFacts False work "verified-owner" [(T.pack(show feeAsset),allowance,"released")]
              (Just $ FeeBudget 1000 0 0 $ money 1000) 0 0
            refunded=good $ decideRefund (W.request order) receipt customerCosts facts
            withdrawn=good $ withdrawalInput (money 1000) 100 (T.replicate 64 "a") asset (money 1) "owner" "earned"
            histories=History [Convert direction n 1,Return asset extra,Revenue asset 1] [0,1,1,2,0]
        in conjoin [paymentAmount refunded===money extra,paymentAsset refunded===asset
             ,aggregate(settlement refunded)===expected(Return asset extra)
             ,decisions histories===Right(model histories)
             ,decideRefund (W.request order) receipt customerCosts facts {refundUnresolved=True}===Left "refund_would_race_payment"
             ,decideRefund (W.request order) receipt customerCosts facts {refundObligations=[("already","extra","paid")]}===Left "principal_already_resolved"
             ,decideRefund (W.request order) receipt customerCosts facts {refundBudget=Just(FeeBudget 1000 990 0 $ money 1000)}
                ===(if allowance>10 then Left "insufficient_fee_budget" else Right refunded)
             ,decideRefund (W.request order) receipt customerCosts facts
                {refundBudget=Just(FeeBudget (toInteger allowance) 0 0 $ money 1000),refundClosingFees=1}
                ===Left "insufficient_fee_budget"
             ,decideRefund (W.request order) receipt customerCosts facts
                {refundBudget=Just(FeeBudget (toInteger allowance) (toInteger allowance) 0 $ money 1000)
                ,refundReleasedFees=toInteger allowance,refundClosingFees=100}===Right refunded
             ,decideWithdrawal withdrawn (PaymentTerms (W.policy order) customerCosts) "earned" Nothing (Just(readyOperator,0))===Left "insufficient_earned_fees"]
  , check "expiry cannot free a received deposit or extend grace on clock rollback" $
      forAll (chooseInteger (0,toInteger(maxBound::Int64)-1)) $ \time ->
        let grace=fromInteger time in conjoin
          [shouldExpireQuote grace grace False===Right False,shouldExpireQuote (grace+1) grace False===Right True
          ,shouldExpireQuote (grace+1) grace True===Right False,shouldExpireQuote 0 grace False===Right False]
  , check "earned cancellation requires unsigned cleanup and exact replay reason" $ once $
      let outgoing=good $ withdrawalInput (money 1000) 100 (T.replicate 64 "a") Native (money 10) "owner" "earned"
          terms=PaymentTerms (PolicySnapshot 2 "finalized" "fixture" []) customerCosts
          saved=WithdrawalView outgoing terms "earned" 3 Nothing
      in conjoin [decideWithdrawal outgoing terms "earned" (Just saved) Nothing===Right False
           ,decideWithdrawal outgoing terms "changed" (Just saved) Nothing===Left "fee_withdrawal_conflict"
           ,decideWithdrawalCancellation "cancel" saved (WithdrawalWork False True)===Left "fee_withdrawal_payment_exists"
           ,decideWithdrawalCancellation "cancel" saved (WithdrawalWork True False)===Left "pause_before_operator_action"
           ,decideWithdrawalCancellation "cancel" saved (WithdrawalWork True True)===Right True
           ,decideWithdrawalCancellation "cancel" saved {withdrawalCancellation=Just("cancel",4)} UnpreparedWithdrawal===Right False]
  , check "treasury splits conserve an unbound receipt and never spend protected balances" $
      forAll (chooseInteger (1,1000000)) $ \n ->
        let receipt=W.Deposit "native:receipt:0" Nothing Native (money(n+2)) "anchor" 2 True 100
            facts=TreasuryFacts readyOperator receipt False False
            entries=good $ decideTreasury (PolicySnapshot 2 "finalized" "fixture" []) [("float",money n),("operating",money 2)] facts
            spent=good $ decideTreasurySpend (Native,money(n+1),money 1) n 1
        in conjoin [aggregate entries===M.fromList [((Native,Unallocated),negate(n+2)),((Native,Float),n),((Native,Operating),2)]
             ,sum(map postingDelta entries)===0,sum(map postingDelta spent)===0
             ,decideTreasurySpend (Native,money(n+1),money 1) (n-1) 1===Left "treasury_spend_exceeds_free_allocation"
             ,decideTreasury (PolicySnapshot 2 "finalized" "fixture" []) [("float",money(n+2))] facts {treasuryLinked=True}===Left "receipt_has_customer_obligation"
             ,property $ all ((`notElem` [Principal,Backing,Liquidity,Earned]).postingAccount) spent]
  , check "customer projection preserves conversion priority independently of row ordering and extra refunds" $
      forAll (chooseInt (1,6)) $ \count -> forAll arbitrary $ \review ->
      forAll (elements [Nothing,Just False,Just True]) $ \work ->
        let conversion=CustomerPayment "source" CustomerConversion PaymentPaid Nothing (Just("conversion",1))
            refunded=[CustomerPayment (T.pack $ show n) CustomerRefund PaymentPaid Nothing (Just(T.pack $ show n,fromIntegral(n+1))) | n<-[1..count]]
            extra=CustomerPayment "extra" CustomerRefund (if work==Nothing then PaymentReady else PaymentPaying) work Nothing
        in forAll (shuffle $ conversion:extra:refunded) $ \payments -> conjoin
          [projectCustomer "Refunded" review payments===Right(if review then "NeedsReview" else "Paid",Just "conversion")
          ,projectCustomer "Paid" False (conversion:extra {customerState=PaymentReview}:refunded)===Right("NeedsReview",Just "conversion")]
  , check "multiple refunds use original settlement order and retain the previous link during new work" $
      forAll (chooseInt (2,8)) $ \count -> forAll (elements [Nothing,Just False,Just True]) $ \work ->
        let completed=[CustomerPayment (T.pack $ show n) CustomerRefund PaymentPaid Nothing
                (Just(if n==count then "replacement-winner" else T.pack(show n),fromIntegral n)) | n<-[1..count]]
            active=CustomerPayment "new" CustomerRefund (if work==Nothing then PaymentReady else PaymentPaying) work Nothing
            status=case work of Nothing->"Refunding"; Just False->"Preparing"; Just True->"Paying"
        in forAll (shuffle completed) $ \payments -> conjoin
          [projectCustomer "Refunded" False payments===Right("Refunded",Just "replacement-winner")
          ,projectCustomer status False (active:payments)===Right(status,Just "replacement-winner")
          ,projectCustomer status True (active:payments)===Right("NeedsReview",Just "replacement-winner")]
  , check "customer status never invents settlement or an active generation" $ once $
      let ready=CustomerPayment "source" CustomerConversion PaymentReady Nothing Nothing
          paid=ready {customerState=PaymentPaid,customerSettlement=Just("winner",1)}
      in conjoin
        ([projectCustomer status False []===Right(status,Nothing) | status<-["Provisioning","AwaitingDeposit","ExpiredUnfunded"]]
        <>[projectCustomer "Ready" False [ready]===Right("Ready",Nothing)
        ,projectCustomer "NeedsReview" False [ready]===Right("NeedsReview",Nothing)
        ,projectCustomer "Paid" False []===Left "customer_payment_state_inconsistent"
        ,projectCustomer "Paid" False [paid {customerSettlement=Nothing}]===Left "customer_payment_state_inconsistent"
        ,projectCustomer "Paying" False [ready {customerState=PaymentPaying}]===Left "customer_payment_state_inconsistent"
        ,projectCustomer "Paid" False [paid,paid]===Left "ambiguous_customer_payments"
        ,projectCustomer "Refunded" False [paid {customerKind=CustomerRefund},paid {customerKind=CustomerRefund}]===Left "ambiguous_customer_payments"
        ,projectCustomer "invented" True [ready]===Left "unknown_order_status"])
  , check "paged customer history retains the same result with at most three display facts" $
      forAll (chooseInt (1,1010)) $ \count -> forAll (chooseInt (1,20)) $ \width ->
      forAll arbitrary $ \review ->
        let conversion=CustomerPayment "source" CustomerConversion PaymentPaid Nothing (Just("conversion",fromIntegral(count+1)))
            active=CustomerPayment "new" CustomerRefund PaymentPaying (Just True) Nothing
            refunds=[CustomerPayment (T.pack $ show n) CustomerRefund PaymentPaid Nothing (Just(T.pack $ show n,fromIntegral n)) | n<-[1..count]]
            chunks []=[]; chunks xs=let (page,rest)=splitAt width xs in page:chunks rest
        in forAll (shuffle $ conversion:active:refunds) $ \payments ->
          let summary=good $ foldM (\kept page->compactCustomerPayments $ kept<>page) [] (chunks payments)
          in conjoin [property(length summary<=3),projectCustomer "Paid" review summary===projectCustomer "Paid" review payments]
  , check "scan evidence binds its exact cursor origin asset and bounded batch" $
      forAll (elements scanAssets) $ \(chain,asset) -> forAll (chooseInteger (1,1000000)) $ \n ->
        let receipt=W.Deposit "receipt" Nothing asset (money n) "anchor" 2 True 100
            batch=W.ScanBatch chain "origin" (Just "prior") "next" 100 [receipt] []
        in conjoin [checkScan batch (Just "prior") ["origin"]===Right ()
             ,checkScan batch (Just "stale") ["origin"]===Left "stale_scan_cursor"
             ,checkScan batch (Just "prior") ["changed"]===Left "scan_origin_mismatch"
             ,checkScan batch (Just "prior") ["origin","origin"]===Left "duplicate_scan_origin"
             ,checkScan batch {W.scanDeposits=replicate 1001 receipt} (Just "prior") []===Left "invalid_scan_batch"
             ,checkScan batch {W.scanDeposits=[receipt {W.depositAsset=if asset==Sol then Native else Sol}]} (Just "prior") []===Left "scan_asset_mismatch"]
  , check "unavailable missing duplicated or future scan evidence cannot establish readiness" $ once $
      let rows=[("Native",Just 100,Nothing,"n"),("Solana",Just 100,Nothing,"s"),("SolanaOperating",Just 100,Nothing,"o")]
          checkRows xs=checkScans 100 (scanFacts xs)
      in conjoin [checkRows rows===Right (),checkRows (drop 1 rows)===Left "scanners_not_fresh"
           ,checkRows (rows<>rows)===Left "scanners_not_fresh"
           ,checkRows (("Native",Just 100,Just "provider_unavailable","n"):drop 1 rows)===Left "scanners_not_fresh"
           ,checkRows (("Native",Just 101,Nothing,"n"):drop 1 rows)===Left "scanners_not_fresh"
           ,checkIntake readyIntake {intakePaused=True}===Left "intake_paused"]
  , check "observing retained signed bytes is not evidence of an authorized outgoing transfer" $
      forAll (elements ["signed","broadcast_intent","settled","failed","review"]) $ \state ->
      forAll (elements ["Native","Solana","SolanaOperating"]) $ \chain ->
        let event=W.ChainEvent "transaction" "outgoing" "anchor" (object [])
            facts=ObservationFacts [(state,Just 1,Just "winner-proof")] [] []
            known=state `elem` ["broadcast_intent","settled","failed"]
        in conjoin [observationNeedsReview chain event facts===not known
             ,observationNeedsReview chain event facts {observationFormerWinners=["winner-proof"]}===not(known || state=="review" && chain=="Native")
             ,property $ observationNeedsReview chain event {W.chainEventKind="disputed"} facts
             ,property $ either (const False) (not . T.null) (checkObservation chain event)
             ,checkObservation chain event {W.chainEventKind="invented"}===Left "invalid_observation_kind"]
  , check "cleanup binds exact unsigned generation and preserves completed replay after later work" $
      forAllShrink fundingCases shrinkFunding $ \funding -> forAll (chooseInt (0,7)) $ \generation ->
      forAll arbitrary $ \eligible ->
        let prepared=(created $ good $ decidePreparation (money 10) "{}" $ initialPreparation funding) {preparedGeneration=generation}
            facts=CancellationFacts readyOperator Nothing (Just prepared) eligible
            pending=facts {cancellationPrevious=Just("cancel","{}",False)}
            done=pending {cancellationPrevious=Just("cancel","{}",True),cancellationUnsigned=Nothing}
            decide phase=decideCancellation phase prepared "cancel" "{}"
            signable=prepared {preparedDraft=Just "saved draft; signature reply may be lost"}
            unknown phase previous=decideCancellation phase signable "cancel" "{}"
              facts {cancellationPrevious=previous,cancellationUnsigned=Just signable}
        in conjoin [checkCancellableDraft prepared===Right ()
             ,checkCancellableDraft signable===Left "preparation_signature_outcome_unknown"
             ,unknown BeginCleanup Nothing===Left "preparation_signature_outcome_unknown"
             ,unknown FinishCleanup (Just("cancel","{}",False))===Left "preparation_signature_outcome_unknown"
             ,decide BeginCleanup facts===Right RequestCancellation
             ,decide BeginCleanup pending===Right KeepCancellation
             ,decide FinishCleanup pending===Right(CompleteCancellation $ eligible && generation<7)
             ,decide FinishCleanup done===Right KeepCancellation
             ,decide FinishCleanup facts===Left "preparation_cancellation_not_expected"
             ,decide FinishCleanup pending {cancellationUnsigned=Just prepared {preparedGeneration=generation+1}}===Left "preparation_cancellation_not_expected"
             ,decide FinishCleanup pending {cancellationUnsigned=Nothing}===Left "preparation_cancellation_not_expected"
             ,decide FinishCleanup pending {cancellationPrevious=Just("other","{}",False)}===Left "preparation_cancellation_conflict"
             ,decide BeginCleanup facts {cancellationOperator=readyOperator {operatorCustody=Nothing}}===Left "custody_not_reconciled"
             ,decide FinishCleanup done {cancellationOperator=readyOperator {operatorPaused=False}}===Left "pause_before_operator_action"]
  , check "Solana expiry retains exact bytes and separate retry binds current generation source and authority" $
      forAll (chooseInt (0,6)) $ \generation -> forAll (elements ["signed","broadcast_intent"]) $ \state ->
        let funding=Convert NativeToWrapped 100 1
            prepared=(created $ good $ decidePreparation (money 10) "{}" $ initialPreparation funding) {preparedGeneration=generation}
            attempt=(settlementCurrent $ snapshot 0 funding) {recordedGeneration=generation,recordedState=state}
            expiry=ExpiryFacts attempt prepared [signedId $ recordedSigned attempt]
            expired=attempt {recordedState="review",recordedObservation=Just "proof"}
            retry=RetryFacts readyOperator expired (Just "proof") [(fromIntegral generation,Just(signedId $ recordedSigned attempt),0,1)]
              (preparedView prepared) {savedStatus=PaymentReview} True
            approve=decideSolanaRetry expired "approved" Nothing . Just
        in conjoin [decideSolanaExpiry attempt "proof" Nothing (Just expiry)===Right True
             ,decideSolanaExpiry attempt "proof" (Just "proof") Nothing===Right False
             ,decideSolanaExpiry attempt "changed" (Just "proof") Nothing===Left "expiry_evidence_conflict"
             ,decideSolanaExpiry attempt "proof" Nothing (Just expiry {expiryUnretiredAttempts=["other"]})===Left "expiry_attempt_changed"
             ,decideSolanaExpiry attempt "proof" Nothing (Just expiry {expiryPreparation=prepared {preparedGeneration=generation+1}})===Left "expiry_attempt_changed"
             ,approve retry===Right True
             ,approve retry {retryExpiry=Nothing}===Left "solana_retry_not_expected"
             ,approve retry {retryHistory=[]}===Left "solana_retry_not_expected"
             ,approve retry {retryHistory=[(fromIntegral generation+1,Just "later",0,1)]}===Left "solana_retry_not_expected"
             ,approve retry {retrySourceEligible=False}===Left "source_not_eligible"
             ,approve retry {retryOperator=readyOperator {operatorPaused=False}}===Left "pause_before_operator_action"
             ,decideSolanaRetry expired "approved" (Just "approved") Nothing===Right False
             ,decideSolanaRetry expired "changed" (Just "approved") Nothing===Left "retry_approval_conflict"
             ,recordedSigned expired===recordedSigned attempt]
  , check "native replacement binds the latest broadcast family exact work and fresh paused authority" $
      forAll (chooseInt (0,6)) $ \drafts -> forAll (chooseInt (0,7)) $ \generation ->
        let funding=Return Native 100
            prepared=(created $ good $ decidePreparation (money 10) "{}" $ initialPreparation funding) {preparedGeneration=generation}
            parent=(settlementCurrent $ snapshot 0 funding) {recordedGeneration=generation}
            family=[parent]
        in conjoin [checkReplacementDraft readyOperator parent family drafts===Right ()
             ,checkReplacementDraft readyOperator parent family 7===Left "native_replacement_draft_limit"
             ,checkReplacementDraft readyOperator parent (replicate 8 parent) drafts===Left "native_replacement_not_current"
             ,checkReplacementDraft readyOperator {operatorPaused=False} parent family drafts===Left "pause_before_operator_action"
             ,checkReplacementSigning prepared parent family True ("work","work")===Right ()
             ,checkReplacementSigning prepared parent family False ("work","work")===Left "source_not_eligible"
             ,checkReplacementSigning prepared parent family True ("work","changed")===Left "native_replacement_work_changed"
             ,checkReplacementSigning prepared {preparedGeneration=generation+1} parent family True ("work","work")===Left "native_replacement_not_expected"
             ,checkReplacementParent parent {recordedState="signed"} family===Left "native_replacement_not_expected"]
  , check "changed native winners adjust only actual costs and reversing a winner restores the same allocation" $
      forAll (chooseInteger (1,4)) $ \oldFee -> forAll (chooseInteger (5,10)) $ \newFee ->
        let base=settlementCurrent $ snapshot 0 (Return Native 100)
            old=base {recordedState="settled"}
            new=base {recordedSigned=(recordedSigned base) {signedId="replacement",signedBytes="saved replacement bytes"}}
            family=[old,new]; costs n=PaymentCosts (money n) (money 0)
            result=good $ decideNativeWinner family "replacement" (costs newFee) "proof" (NativeWinnerFacts old family $ costs oldFee)
            changed=new {recordedState="settled",recordedObservation=Just $ changedObservation result}
            back=[old {recordedState="review"},changed]
            reversed=good $ decideNativeWinner back (signedId $ recordedSigned old) (costs oldFee) "earlier winner" (NativeWinnerFacts changed back $ costs newFee)
        in conjoin [changedWinner result===new,changedFee result===newFee-oldFee
             ,aggregate(winnerPostings result)===M.fromList [((Native,Operating),oldFee-newFee),((Native,External),newFee-oldFee)]
             ,aggregate(winnerPostings result<>winnerPostings reversed)===M.empty
             ,property $ all ((`elem` [Operating,External]).postingAccount) (winnerPostings result)
             ,decideNativeWinner family "replacement" (costs newFee) "proof" (NativeWinnerFacts old [old] $ costs oldFee)===Left "native_replacement_family_changed"
             ,decideNativeWinner family "replacement" (costs 11) "proof" (NativeWinnerFacts old family $ costs oldFee)===Left "invalid_native_settlement"]
  , check "native evidence reviews preserve idempotency across rebroadcast metadata without erasing settlement" $ once $
      let prior="original settlement"; decision=NativeUnavailable "native_settled_payment_unseen"
          Just(state,raw)=good $ decideNativeReview decision prior []
          approved=TE.decodeUtf8 $ BL.toStrict $ encode $ object ["reason" .= ("native_settled_payment_unseen"::T.Text)
            ,"rebroadcastRecovery" .= (5::Int),"operatorReason" .= ("resend saved bytes"::T.Text),"rebroadcastProof" .= object []]
      in conjoin [decideNativeReview decision prior [(state,raw)]===Right Nothing
           ,decideNativeReview decision prior [(state,approved)]===Right Nothing
           ,property $ good(decideNativeReview NativeConfirming prior [(state,raw)])/=Nothing
           ,decideNativeReview (NativeUnavailable "") prior []===Left "invalid_native_recovery_reason"
           ,decideNativeReview decision prior [(state,raw),(state,raw)]===Left "duplicate_native_recovery_state"]
  , check "source loss unavailable and return histories retain liabilities and post the deficit exactly once" $
      forAll (chooseInteger (1,1000000)) $ \n -> forAll (chooseInteger (0,1000000)) $ \part ->
        let source=W.Deposit "native:source:0" (Just "order") Native (money n) "anchor" 0 False 100
            proof=object []; missing=good $ decideSourceCheck source True Nothing (W.SourceMissing proof)
            effect=maybe (error "missing loss") id missing
            old=Just(sourceState effect,sourceLoss effect,sourceCheckEvidence effect)
            unavailable=maybe (error "missing unavailable") id $ good $ decideSourceCheck source True old (W.SourceUnavailable proof)
            unseen=Just(sourceState unavailable,sourceLoss unavailable,sourceCheckEvidence unavailable)
            returned=maybe (error "missing return") id $ good $ decideSourceCheck source {W.depositEligible=True} True unseen (W.SourceRestored proof)
            split=min part n; cover=[Posting Native Float (-split),Posting Native Earned (split-n),Posting Native SourceDeficit n]
            restore=good $ sourceReturnPostings Native n (fromInteger n,fromInteger split,fromInteger(n-split))
        in conjoin [sourceLoss effect===fromInteger n,sourcePostings unavailable===[]
             ,decideSourceCheck source True old (W.SourceMissing proof)===Right Nothing
             ,aggregate(sourcePostings effect<>sourcePostings returned)===M.empty
             ,aggregate(cover<>restore)===M.empty
             ,property $ all ((`elem` [SourceDeficit,External]).postingAccount) (sourcePostings effect)
             ,decideSourceCheck source True Nothing (W.SourceUnavailable proof)===Right(Just $ SourceEffect "unavailable" 0 "{}" 0 [])
             ,decideSourceCheck source False Nothing (W.SourcePending proof)===Right Nothing
             ,decideSourceCheck source True Nothing (W.SourceMissing Null)===Left "invalid_source_recovery_evidence"
             ,sourceReturnPostings Native (n+1) (fromInteger n,fromInteger split,fromInteger(n-split))===Left "source_loss_return_mismatch"]
  , check "covering a source loss spends only exact free native float and earned capital at the current loss" $
      forAll (chooseInteger (1,1000000)) $ \n -> forAll (chooseInteger (0,n)) $ \capital ->
        let source=W.Deposit "native:source:0" (Just "order") Native (money n) "anchor" 0 False 100
            facts=LossCoverFacts source (Just(fromInteger n,4)) False (Just(2,2,100)) capital (n-capital)
            cover=decideLossCover source 4 100 (money capital) (money(n-capital))
            postings=good $ cover facts
        in conjoin [sum(map postingDelta postings)===0
             ,aggregate postings===normalize(M.fromList [((Native,Float),-capital),((Native,Earned),capital-n),((Native,SourceDeficit),n)])
             ,cover facts {lossAlreadyCovered=True}===Left "source_loss_already_covered"
             ,cover facts {lossLatest=Just(fromInteger n,5)}===Left "source_loss_not_proven"
             ,cover facts {lossCustody=Just(3,2,100)}===Left "source_loss_custody_not_current"
             ,cover facts {lossFreeFloat=capital-1}===Left "insufficient_loss_capital"
             ,property $ all ((`notElem` [Principal,Operating,Backing,Liquidity]).postingAccount) postings]
  , check "source approval is bound to current loss or restoration exact suspended work and completed cleanup" $
      forAll arbitrary $ \covered -> forAll (elements ["ready","paying"]) $ \previous ->
        let source=W.Deposit "native:source:0" (Just "order") Native (money 10) "anchor" 0 (not covered) 100
            facts=SourceApprovalFacts PaymentReview source (Just(if covered then "missing" else "restored",if covered then 10 else 0,5))
              (if covered then Just 4 else Nothing) (Just(previous,3,"work")) "work" False
            approve=decideSourceApproval covered 5
        in conjoin [approve facts===Right(previous,3)
             ,approve facts {approvalStatus=PaymentReady}===Left "source_approval_not_expected"
             ,approve facts {approvalWorkHash="changed"}===Left "source_review_work_changed"
             ,approve facts {approvalCleanupPending=True}===Left "preparation_cancellation_pending"
             ,approve facts {approvalReview=Nothing}===Left "source_review_context_missing"
             ,approve facts {approvalCover=Nothing}===(if covered then Left "source_loss_not_covered" else Right(previous,3))]
  , check "same-byte rebroadcast requires paid native work an applicable missing review and retained source backing" $
      forAll (elements [("confirming","native_confirmation_policy_pending"),("unavailable","native_settled_payment_unseen")]) $ \review ->
        let snapshot'=snapshot 0 (Return Native 100)
            saved=(settlementCurrent snapshot') {recordedState="settled",recordedObservation=Just "original"}
            view=(settlementPayment snapshot') {savedStatus=PaymentPaid}
            facts=RebroadcastFacts True view True [saved] ("original",fst review,snd review)
        in conjoin [checkRebroadcast saved facts===Right ()
             ,checkRebroadcast saved facts {rebroadcastPaused=False}===Left "pause_before_operator_action"
             ,checkRebroadcast saved facts {rebroadcastSourceEligible=False}===Left "source_not_eligible"
             ,checkRebroadcast saved facts {rebroadcastReview=("original","unavailable","rpc_timeout")}===Left "native_rebroadcast_not_missing"
             ,checkRebroadcast saved facts {rebroadcastFamily=[]}===Left "native_replacement_family_changed"
             ,checkRebroadcast saved {recordedState="signed"} facts===Left "native_rebroadcast_payment_changed"
             ,checkRebroadcast saved facts {rebroadcastReview=("changed",fst review,snd review)}===Left "native_rebroadcast_not_missing"]
  , check "shared generation history keeps unsigned cleanup separate from proved approved expiry" $
      forAll (chooseInt (1,8)) $ \count -> forAll (vectorOf count arbitrary) $ \expired ->
        let rows=[(fromIntegral g,if retired then SolanaRetired (T.pack $ show g) True True else UnsignedCleanup Nothing True)
                 | (g,retired)<-zip [0::Int ..] expired]
            attempts=[(T.pack $ show g,fromIntegral g) | (g,True)<-zip [0::Int ..] expired]
        in conjoin [successorGeneration True rows attempts===Just count
             ,successorGeneration False rows attempts===(if or expired then Nothing else Just count)
             ,successorGeneration True rows (attempts<>[("future",fromIntegral count)])===Nothing
             ,successorGeneration True (rows<>rows) attempts===Nothing
             ,successorGeneration True ((0,OpenGeneration):drop 1 rows) attempts===Nothing
             ,successorGeneration True ((0,UnsignedCleanup Nothing False):drop 1 rows) attempts===Nothing
             ,conjoin [successorGeneration allowExpiry ((0,UnsignedCleanup (Just draft) True):drop 1 rows) attempts===Nothing
                      | allowExpiry<-[False,True],draft<-["signed-compatible-draft","", "null"]]
             ,successorGeneration True ((0,SolanaRetired "0" True False):drop 1 rows) attempts===Nothing
             ,successorGeneration True ((0,SolanaRetired "0" False True):drop 1 rows) attempts===Nothing
             ,successorGeneration True ((0,UnsignedCleanup Nothing True):drop 1 rows) (("signed",0):attempts)===Nothing]
  ]
 where
  check name test=putStrLn name >> quickCheckWithResult stdArgs {maxSuccess=300} test

fundingCases :: Gen FundingCase
fundingCases = do
  n<-frequency [(8,chooseInteger (2,100000000)),(1,pure 2),(1,pure $ toInteger(maxBound::Int64))]
  oneof
    [ Convert <$> elements [NativeToWrapped,WrappedToNative] <*> pure n <*> chooseInteger (0,n-1)
    , Return <$> elements [Native,Wrapped] <*> pure n
    , Revenue <$> elements [Native,Wrapped] <*> pure n ]

shrinkFunding :: FundingCase -> [FundingCase]
shrinkFunding (Convert direction n f) =
  [Convert direction smaller (min f $ smaller-1) | smaller<-shrink n,smaller>=2]
  <>[Convert direction n smaller | smaller<-shrink f,smaller>=0,smaller<n]
shrinkFunding (Return asset n) = [Return asset smaller | smaller<-shrink n,smaller>0]
shrinkFunding (Revenue asset n) = [Revenue asset smaller | smaller<-shrink n,smaller>0]

histories :: Gen History
histories = do
  count<-chooseInt (1,6)
  payments<-vectorOf count fundingCases
  lengthOfTrace<-chooseInt (0,24)
  deliveries<-vectorOf lengthOfTrace (chooseInt (0,count-1))
  -- Include every payment and at least one exact redelivery. Shrinking below
  -- can isolate the minimal delivery while keeping all indices well formed.
  pure $ History payments (take 24 deliveries<>[0..count-1]<>[0])

shrinkHistory :: History -> [History]
shrinkHistory (History payments deliveries) =
  [History payments fewer | fewer<-shrinkList (const []) deliveries]
  <>[History (before<>(smaller:after)) deliveries
     | index<-[0..length payments-1],(before,current:after)<-[splitAt index payments]
     ,smaller<-shrinkFunding current]

outgoing :: Int -> FundingCase -> Payment
outgoing index funding = good $ do
  source<-case funding of
    Convert direction n f -> historicalQuote (money n) (money f) >>= conversion order receipt direction
    Return asset n -> refund order receipt asset (money n)
    Revenue asset n -> earnedFees order asset (money n)
  payment key source "unchanged-recipient"
 where
  key="payment-"<>T.pack(show index); order="order-"<>key; receipt="receipt-"<>key

-- Only this adapter uses production accounting. Deduplication here is the
-- baseline Store contract, not a new production implementation of replay.
baseline :: History -> Balances
baseline (History payments deliveries) = aggregate $
  concat [settlement(outgoing index $ payments!!index) | index<-nub deliveries]

-- Unlike the baseline adapter, the new adapter delegates replay/authorization to
-- decideSettlement. Updating the in-memory facts models only a committed result;
-- actual all-or-nothing persistence is tested against PostgreSQL, not assumed here.
decisions :: History -> Either T.Text Balances
decisions (History payments deliveries) = snd <$> foldM step (initial,M.empty) deliveries
 where
  initial=M.fromList [(index,snapshot index funding) | (index,funding)<-zip [0..] payments]
  step (states,balances) index = do
    let facts=states M.! index; queued=settlementCurrent(initial M.! index); outcome=successful facts
    decision<-decideSettlement queued facts outcome
    case decision of
      SettlementReplay->pure (states,balances)
      ApplySettlement effects->pure (M.insert index (finished facts outcome) states,
        normalize $ M.unionWith (+) balances (aggregate $ settlementPrincipal effects))

snapshot :: Int -> FundingCase -> SettlementFacts
snapshot index funding = SettlementFacts queued view (Just(currency,money 10)) Nothing Nothing
 where
  p=outgoing index funding; native=paymentAsset p==Native; currency=if native then Native else Sol
  view=PaymentView p (PaymentTerms (PolicySnapshot 2 "finalized" "fixture" []) (CostLimits (money 10) (money 10) (money 10))) PaymentPaying
  queued=RecordedAttempt (paymentId p) (if native then "Native" else "Solana") 0 (money 10) "broadcast_intent" (Just 5) Nothing
    (SignedAttempt ("transaction-"<>T.pack(show index)) "exact-saved-bytes" "exact-saved-policy" Nothing)

successful :: SettlementFacts -> SettlementOutcome
successful facts = Succeeded (PaymentCosts (money 1) (money $ if recordedChain(settlementCurrent facts)=="Native" then 0 else 2)) "finality-proof"

finished :: SettlementFacts -> SettlementOutcome -> SettlementFacts
finished facts outcome = facts
  { settlementCurrent=queued {recordedState=outcomeState outcome,recordedObservation=Just $ outcomeRecord outcome}
  , settlementPayment=(settlementPayment facts) {savedStatus=if paid then PaymentPaid else PaymentReview}
  , settlementHold=Nothing,settlementPriorWinner=if paid then Just(signedId $ recordedSigned queued) else Nothing
  , settlementFailedCharge=case outcome of Failed cost _->Just(toInteger $ units cost); _->Nothing }
 where queued=settlementCurrent facts; paid=case outcome of Succeeded{}->True; Failed{}->False

refusalCases :: Bool
refusalCases = and
  [ reject "settlement_attempt_changed" queued {recordedGeneration=1} facts outcome
  , reject "settlement_attempt_changed" queued {recordedState="signed"} facts outcome
  , reject "settlement_attempt_changed" queued {recordedSequence=Nothing} facts outcome
  , reject "settlement_attempt_changed" queued {recordedSigned=(recordedSigned queued) {signedBytes="other"}} facts outcome
  , reject "settlement_attempt_changed" queued facts {settlementPayment=settlementPayment(snapshot 1 funding)} outcome
  , reject "settlement_not_expected" queued facts {settlementPayment=(settlementPayment facts) {savedStatus=PaymentReady}} outcome
  , reject "payment_intent_not_settleable" queued facts {settlementHold=Nothing} outcome
  , reject "payment_intent_not_settleable" queued facts {settlementHold=Just(Native,money 10)} outcome
  , reject "payment_intent_not_settleable" queued facts {settlementHold=Just(Sol,money 9)} outcome
  , reject "payment_already_settled" queued facts {settlementPriorWinner=Just "other-winner"} outcome
  , reject "settlement_fee_or_evidence_invalid" queued facts (Succeeded (PaymentCosts (money 0) (money 0)) "proof")
  , reject "settlement_fee_or_evidence_invalid" queued facts (Succeeded (PaymentCosts (money 9) (money 2)) "proof")
  , reject "settlement_fee_or_evidence_invalid" queued facts (Succeeded (PaymentCosts (money 1) (money 0)) "")
  , reject "settlement_fee_or_evidence_invalid" queued facts (Succeeded (PaymentCosts (money 1) (money 0)) $ T.replicate 32769 "x")
  , reject "settlement_evidence_conflict" queued (finished facts outcome) (Succeeded (outcomeCosts outcome) "changed")
  , reject "settlement_evidence_conflict" queued (finished facts outcome) (Succeeded (PaymentCosts (money 2) (money 2)) "finality-proof")
  , reject "settlement_fee_or_evidence_invalid" nativeQueued nativeFacts (Succeeded (PaymentCosts (money 1) (money 1)) "proof")
  , reject "invalid_failure_evidence" nativeQueued nativeFacts (Failed (money 1) "proof")
  , reject "invalid_failure_evidence" queued facts (Failed (money 0) "proof")
  , reject "invalid_failure_evidence" queued facts (Failed (money 11) "proof")
  , decideSettlement queued (facts {settlementPayment=(settlementPayment facts) {savedStatus=PaymentReview}}) outcome
      ==decideSettlement queued facts outcome
  ]
 where
  funding=Convert NativeToWrapped 100 1
  facts=snapshot 0 funding; queued=settlementCurrent facts; outcome=successful facts
  nativeFacts=snapshot 0 (Return Native 100); nativeQueued=settlementCurrent nativeFacts
  reject code original current observed=decideSettlement original current observed==Left code

readyIntake :: IntakeFacts
readyIntake = IntakeFacts 100 False (Just((100,"native"),(100,"tokens"),(100,"sol"))) (Just(1,1,100))

initialPreparation :: FundingCase -> PreparationFacts
initialPreparation funding = PreparationFacts view InitialPreparation (Just admission)
 where
  view=(settlementPayment $ snapshot 0 funding) {savedStatus=PaymentReady}
  held=20
  admission=PreparationAdmission readyIntake False True Nothing (Just $ money held)
    (toInteger $ units $ paymentAmount $ savedPayment view) (FeeBudget 1000 held 0 (money 1000)) 0

admitted :: PreparationFacts -> PreparationAdmission
admitted facts=case preparationAdmission facts of Just admission->admission; Nothing->error "fixture admission missing"
created :: PreparationDecision -> PreparedPayment
created (CreatePreparation prepared)=prepared
created ReusePreparation{}=error "new preparation unexpectedly reused"

sendFacts :: FundingCase -> PreparedPayment -> SendFacts
sendFacts funding prepared = SendFacts readyIntake prepared queued True
  (Just(signedId $ recordedSigned queued,False)) 0 True 5
 where queued=settlementCurrent $ snapshot 0 funding

preparationRefusals :: Property
preparationRefusals = conjoin $
  [counterexample (T.unpack code) $ decidePreparation quantity plan facts===Left code
    | (code,quantity,plan,facts)<-
      [("invalid_payment_record",money 10,"",base)
      ,("invalid_payment_record",money 10,"null",base)
      ,("invalid_saved_payment",money 10,"{",base)
      ,("order_fee_limit_exceeded",money 0,"{}",base)
      ,("order_fee_limit_exceeded",money 21,"{}",base)
      ,("payment_not_ready",money 10,"{}",base {preparationPayment=(preparationPayment base) {savedStatus=PaymentReview}})
      ,("preparation_retry_requires_recovery",money 10,"{}",base {preparationHistory=RetiredPreparation "wrong-chain" (Just 1)})]]
  <>[counterexample (T.unpack code) $ decidePreparation (money 10) "{}" base {preparationAdmission=Just changed}===Left code
    | (code,changed)<-
      [("intake_paused",original {preparationIntake=readyIntake {intakePaused=True}})
      ,("scanners_not_fresh",original {preparationIntake=readyIntake {intakeTime=161}})
      ,("destination_payment_unresolved",original {destinationBusy=True})
      ,("source_not_eligible",original {preparationSourceEligible=False})
      ,("operating_reservation_missing",original {initialOperatingHold=Nothing})
      ,("operating_reservation_missing",original {initialOperatingHold=Just $ money 9})
      ,("insufficient_fee_budget",original {preparationBudget=FeeBudget 9 20 0 (money 1000)})
      ,("operating_daily_limit",original {preparationBudget=FeeBudget 1000 20 991 (money 1000)})]]
  <>[decidePreparation (money 10) "{}" earned {preparationAdmission=Just (admitted earned) {pendingEarnedBalance=99}}===Left "earned_reservation_missing"]
 where
  base=initialPreparation (Convert NativeToWrapped 100 1); original=admitted base
  earned=initialPreparation (Revenue Native 100)

sendRefusals :: Property
sendRefusals = conjoin
  [counterexample (T.unpack code) $ decideSend changed===Left code | (code,changed)<-
    [("intake_paused",base {sendIntake=readyIntake {intakePaused=True}})
    ,("scanners_not_fresh",base {sendIntake=readyIntake {intakeScans=Nothing}})
    ,("custody_not_reconciled",base {sendIntake=readyIntake {intakeCustody=Just(2,1,100)}})
    ,("payment_not_sendable",base {sendAttempt=(sendAttempt base) {recordedGeneration=1}})
    ,("source_not_eligible",base {sendSourceEligible=False})
    ,("native_replacement_not_current",base {sendNativeSelection=Just("old",False)})
    ,("native_replacement_draft_pending",base {sendNativeSelection=Just("transaction-0",True)})
    ,("broadcast_intent_required",base {sendAttempt=(sendAttempt base) {recordedSequence=Nothing}})]]
 where
  funding=Return Native 100
  prepared=created $ good $ decidePreparation (money 10) "{}" (initialPreparation funding)
  base=sendFacts funding prepared

-- The model owns its paid set and independently calculates account changes.
model :: History -> Balances
model (History payments deliveries) = snd $ foldl step (Set.empty,M.empty) deliveries
 where
  step prior@(paid,balances) index
    | Set.member index paid = prior
    | otherwise = (Set.insert index paid,normalize $ M.unionWith (+) balances (expected $ payments!!index))

expected :: FundingCase -> Balances
expected funding = normalize $ M.fromListWith (+) $ case funding of
  Convert direction n f ->
    let (source,destination)=case direction of NativeToWrapped->(Native,Wrapped); WrappedToNative->(Wrapped,Native)
    in [((source,Principal),-n),((source,Float),n-f),((source,Earned),f)
       ,((destination,Float),f-n),((destination,External),n-f)]
  Return asset n -> [((asset,Principal),-n),((asset,External),n)]
  Revenue asset n -> [((asset,FeePending),-n),((asset,External),n)]

aggregate :: [Posting] -> Balances
aggregate = normalize . M.fromListWith (+) . map (\p->((postingAsset p,postingAccount p),postingDelta p))
normalize :: Balances -> Balances
normalize = M.filter (/=0)
money :: Integer -> Amount
money = good . amount
good :: Show e => Either e a -> a
good = either (error . show) id


customerCosts :: CostLimits
customerCosts=CostLimits (money 10) (money 10) (money 10)
customerLimits :: OrderLimits
customerLimits=OrderLimits (money 100000000) 100 100 100 (money 1000000000) (money 1000000000)
customerAdmission :: OrderAdmissionFacts
customerAdmission=OrderAdmissionFacts readyIntake 0 100000000 budget budget
 where budget=FeeBudget 1000000000 0 0 (money 1000000000)
readyOperator :: OperatorFacts
readyOperator=OperatorFacts 100 True (Just(1,1,100))
customerRequest :: Direction -> Integer -> W.OrderRequest
customerRequest direction n=W.OrderRequest direction (money n) "recipient" (if direction==NativeToWrapped then "refund" else "") Nothing "key"
customerPromotion :: Direction -> Integer -> Integer -> PromotionFacts
customerPromotion direction n charge=PromotionFacts order receipt 300 False
 where
  order=W.OrderView "order" (customerRequest direction n) (good $ historicalQuote (money n) (money charge))
    "AwaitingDeposit" 200 (Just "instruction") Nothing (PolicySnapshot 2 "finalized" "fixture" [])
  receipt=W.Deposit "original" (Just "order") (sourceAsset direction) (money n) "anchor" 2 True 100
