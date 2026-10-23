-- Closed offline installer operation. Never adopts, resumes or replaces a ledger.
module Bridge.Store.Provision (provisionDatabase,provisionRestoredDatabase,initializeLedger,checkInstallationArchive,archiveInstallationDatabase) where
import Bridge.Error
import qualified Bridge.Store.Schema as S
import qualified Bridge.Store.Projection as P
import Bridge.Store.Catalog (claimWorker,verifyReadRole)
import Data.Int (Int64)
import Bridge.Identity (digest)
import Control.Exception (bracket,onException)
import Control.Monad (forM_,void,when)
import Data.Time.Clock.POSIX (getPOSIXTime)
import qualified Opaleye.Exists as Exists
import qualified Data.ByteString.Char8 as B
import Data.Profunctor.Product (p2,p3,p4,p8)
import Data.Scientific (Scientific)
import qualified Data.Map.Strict as M
import Data.Text (Text)
import qualified Data.Text as T
import qualified Database.PostgreSQL.Simple as PG
import Database.PostgreSQL.Simple.Types (Identifier(..),Query(..))
import qualified Opaleye as O
import qualified Opaleye.Internal.Locking as Locking
import Opaleye.Internal.Column (Field_(Column),unColumn)
import qualified Opaleye.Internal.HaskellDB.PrimQuery as E
import Paths_ecx_bridge (getDataFileName)

-- The unique NOLOGIN owner binds CREATE DATABASE atomically to the root journal.
-- A COMMENT written after database creation would leave an ambiguous crash gap.
-- All catalog/data reads and receipt writes use Opaleye; only DDL uses execute.
provisionDatabase :: PG.ConnectInfo -> Text -> IO ()
provisionDatabase settings token=do
  require (T.length token==32 && T.all (`elem` ("0123456789abcdef"::String)) token) "invalid_installation_token"
  require (PG.connectDatabase settings=="postgres" && PG.connectUser settings=="postgres") "provision_requires_postgres_admin"
  bytes<-getDataFileName "schema.sql" >>= B.readFile
  let lines'=B.lines bytes
  require (length(filter(=="BEGIN;") lines')==1 && length(filter(=="COMMIT;") lines')==1
    && last(filter(not.B.null) lines')=="COMMIT;") "unexpected_installation_schema_structure"
  let sql=B.unlines $ filter(\line->line/="BEGIN;" && line/="COMMIT;") lines'
      checksum=digest bytes
      owner="ecx_setup_"<>token
      names=["ecxbridgew","ecxbridger","ecxbridges",owner]
      label="ecx-install:"<>token
  bracket (PG.connect settings) PG.close $ \admin->do
    locked<-O.runSelect admin $ pure (Column(E.FunExpr "pg_catalog.pg_try_advisory_lock"
      [unColumn(O.sqlInt4 1162041393),unColumn(O.sqlInt4 19)]) :: O.Field O.SqlBool)
    require (locked==[True]) "database_provisioning_busy"
    PG.withTransaction admin $ do
      roles<-O.runSelect admin $ do
        (name,super,db,role,replication,bypass,login,oid)<-O.selectTable rolesTable
        O.where_ (O.in_ (map O.sqlStrictText names) name)
        let comment=Column(E.FunExpr "pg_catalog.shobj_description" [unColumn oid,unColumn(O.sqlStrictText "pg_authid")]) :: O.FieldNullable O.SqlText
        pure (name,super O..|| db O..|| role O..|| replication O..|| bypass,login,comment)
        :: IO [(Text,Bool,Bool,Maybe Text)]
      if null roles then do
        -- An existing database is never adopted merely because roles are absent.
        databases<-databaseOwners admin
        require (null databases) "foreign_installation_database"
        forM_ names $ \name->do
          void $ PG.execute admin (if name==owner
            then "CREATE ROLE ? NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS"
            else "CREATE ROLE ? LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS") (PG.Only $ Identifier name)
          void $ PG.execute admin "COMMENT ON ROLE ? IS ?" (Identifier name,label)
      else require (length roles==4 && all (\(name,privileged,login,comment)->
        not privileged && login==(name/=owner) && comment==Just label) roles) "foreign_installation_roles"
    databases<-databaseOwners admin
    case databases of
      []->void $ PG.execute admin "CREATE DATABASE ecx_bridge OWNER ? TEMPLATE template0 ALLOW_CONNECTIONS false" (PG.Only $ Identifier owner)
      [saved] | saved==owner->pure ()
      _->reject "foreign_installation_database"
    PG.withTransaction admin $ do
      void $ PG.execute_ admin "REVOKE ALL ON DATABASE ecx_bridge FROM PUBLIC"
      void $ PG.execute_ admin "ALTER DATABASE ecx_bridge ALLOW_CONNECTIONS true"
    bracket (PG.connect settings {PG.connectDatabase="ecx_bridge"}) PG.close $ \target->PG.withTransaction target $ do
      schemas<-O.runSelect target $ do
        (_,name)<-O.selectTable namespaces
        O.where_ (name O..== O.sqlStrictText "ecx_install")
        pure name
        :: IO [Text]
      if null schemas then do
        existing<-O.runSelect target $ O.limit 1 $ do
          (_,namespace,_)<-O.selectTable relations
          (oid,name)<-O.selectTable namespaces
          O.where_ (namespace O..== oid O..&& name O..== O.sqlStrictText "public")
          pure name
          :: IO [Text]
        require (null existing) "unrecognized_installation_schema"
        void $ PG.execute_ target "CREATE SCHEMA ecx_install AUTHORIZATION postgres; REVOKE ALL ON SCHEMA ecx_install FROM PUBLIC; CREATE TABLE ecx_install.receipt(token text PRIMARY KEY, migration_hash text NOT NULL); REVOKE ALL ON ecx_install.receipt FROM PUBLIC"
        void $ PG.execute_ target (Query sql)
        count<-O.runInsert target O.Insert {O.iTable=receipt,O.iRows=[(O.sqlStrictText token,O.sqlStrictText checksum)],O.iReturning=O.rCount,O.iOnConflict=Nothing}
        require (count==1) "installation_receipt_failed"
      else do
        saved<-O.runSelect target (O.selectTable receipt) :: IO [(Text,Text)]
        require (saved==[(token,checksum)]) "installation_receipt_mismatch"
      void $ PG.execute_ target "REVOKE ALL ON SCHEMA public FROM PUBLIC; REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC; REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM PUBLIC; GRANT CONNECT ON DATABASE ecx_bridge TO ecxbridgew,ecxbridger,ecxbridges; GRANT USAGE ON SCHEMA public TO ecxbridgew,ecxbridger,ecxbridges; GRANT SELECT,INSERT,UPDATE,DELETE ON ALL TABLES IN SCHEMA public TO ecxbridgew; GRANT USAGE,SELECT ON ALL SEQUENCES IN SCHEMA public TO ecxbridgew; GRANT SELECT ON ALL TABLES IN SCHEMA public TO ecxbridger,ecxbridges; GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO ecxbridger,ecxbridges"

initializeLedger :: PG.ConnectInfo -> Text -> IO ()
initializeLedger settings identity = do
  require (T.length identity==64 && T.all (`elem` ("0123456789abcdef"::String)) identity) "invalid_deployment_identity"
  bracket (PG.connect settings) PG.close $ \c->PG.withTransaction c $ do
    claimWorker c >>= flip require "worker_already_running"
    existing<-O.runSelect c (O.selectTable S.deployment) :: IO [S.Deployment]
    case existing of
      []->do
        let exists table=Exists.exists (O.selectTable table >> pure ())
        occupied<-O.runSelect c $ foldr (O..||) (O.sqlBool False) <$> sequence
          [exists S.payoutCohorts, exists S.payoutAssignments, exists S.payoutRounds, exists S.payoutMembers, exists S.withdrawals, exists S.cancellations, exists S.events
          ,exists S.postings, exists S.audit, exists S.custody
          ,exists S.intentIds, exists S.orders, exists S.deposits
          ,exists S.obligations, exists S.reservations, exists S.orderCosts
          ,exists S.operatingReservations, exists S.operatingClock, exists S.operatingCosts
          ,exists S.scanHealth, exists S.checkpoints, exists S.nativeAllocations
          ,exists S.sourceChecks, exists S.sourceReturns, exists S.sourceLossCovers
          ,exists S.observationEvidence, exists S.treasuryAllocations, exists S.treasurySpends
          ,exists S.scanOrigins, exists S.chainEvents, exists S.preparations
          ,exists S.feeHolds, exists S.attempts, exists S.sourceRecoveryDecisions
          ,exists S.preparationCancellations, exists S.solanaExpiries, exists S.solanaRetryApprovals
          ,exists S.replacementDecisions, exists S.replacementCancellationRows, exists S.replacementMemberRows
          ,exists S.nativeRecoveryRows, exists S.nativeWinnerChanges, exists S.legacyHints]
        require (occupied==[False]) "initialization_requires_empty_ledger"
        now<-floor <$> getPOSIXTime
        _<-O.runInsert c O.Insert {O.iTable=S.deployment,
          O.iRows=[S.Deployment (O.sqlInt8 1) (O.sqlInt8 23) (O.sqlStrictText identity) (O.sqlInt8 0) (O.sqlInt8 0) (O.sqlInt8 1) (O.sqlStrictText "installation_requires_reconciliation")],
          O.iReturning=O.rCount,O.iOnConflict=Nothing}
        _<-O.runInsert c O.Insert {O.iTable=S.custody,O.iRows=[(O.sqlInt8 1,O.sqlInt8 0,O.null,O.null,O.null)],O.iReturning=O.rCount,O.iOnConflict=Nothing}
        void $ O.runInsert c O.Insert {O.iTable=S.operatingClock,O.iRows=[(O.sqlInt8 1,O.sqlInt8 now)],O.iReturning=O.rCount,O.iOnConflict=Nothing}
      [r] | S.singleton r==1 && S.schemaVersion r==23 && S.fingerprint r==identity
        && S.criticalSequence r>=0 && S.backupSequence r>=0 && S.backupSequence r<=S.criticalSequence r
        && S.paused r `elem` [0,1]->pure ()
      _->reject "ledger_profile_or_schema_mismatch"

-- Preflight uses the same ownership, exclusive worker and financial gates as
-- retirement without changing any role, database property or ledger record.
-- Success is not transferable authority: actual retirement repeats the checks.
checkInstallationArchive :: PG.ConnectInfo -> Text -> Text -> Int64 -> IO ()
checkInstallationArchive settings token identity sequenceNo = do
  (source,restored,owner,label)<-archiveInputs settings token identity sequenceNo
  let originals=["ecxbridgew","ecxbridger","ecxbridges"]
  bracket (PG.connect settings {PG.connectDatabase="postgres"}) PG.close $ \admin->do
    archiveProvisioningLock admin
    when (not restored) $ archiveRoles admin [owner] False label
    state<-archiveDatabaseState admin source
    require (state==[(owner,True,Nothing)]) "foreign_installation_database"
    archiveRoles admin originals True label
    archiveConnectRoles admin source originals
    bracket (PG.connect settings) PG.close $ \target->PG.withTransaction target $ do
      pid<-archiveTargetGate target restored token identity sequenceNo
      archiveNoSessions admin source (Just pid)

-- A closed offline retirement, never a reset or a transfer. The installer must
-- retain its verified custody archive and journal before invoking this operation.
-- Catalog receipts bind retries to this exact old deployment and frozen sequence.
-- Pending receipts may reopen only for postgres while all service roles remain
-- NOLOGIN; sealed receipts never reopen the database. No ledger row is changed.
archiveInstallationDatabase :: PG.ConnectInfo -> Text -> Text -> Int64 -> Text -> IO Text
archiveInstallationDatabase settings token identity sequenceNo suffix = do
  (source,restored,owner,label)<-archiveInputs settings token identity sequenceNo
  require (archiveHex 32 suffix) "invalid_installation_archive"
  let destination="ecx_archive_"<>suffix
      originals=["ecxbridgew","ecxbridger","ecxbridges"]
      archived=map (<>suffix) ["ecx_archived_w_","ecx_archived_r_","ecx_archived_s_"]
      binding=T.intercalate ":" ["ecx-archive-v1",token,identity,T.pack(show sequenceNo),source,suffix]
      pending=binding<>":pending"
      sealed=binding<>":sealed"
  bracket (PG.connect settings {PG.connectDatabase="postgres"}) PG.close $ \admin->do
    archiveProvisioningLock admin
    when (not restored) $ archiveRoles admin [owner] False label
    destinationState<-archiveDatabaseState admin destination
    if not(null destinationState) then do
      require (destinationState==[(owner,False,Just sealed)]) "foreign_archive_database"
      archiveRoles admin archived False sealed
      archiveNoSessions admin destination Nothing
    else do
      collisions<-archiveRoleState admin archived
      require (null collisions) "foreign_archive_roles"
      initial<-archiveDatabaseState admin source
      phase<-case initial of
        [(saved,True,Nothing)] | saved==owner->pure Nothing
        [(saved,_,Just receipt')] | saved==owner && receipt'==pending->pure(Just False)
        [(saved,False,Just receipt')] | saved==owner && receipt'==sealed->pure(Just True)
        _->reject "foreign_installation_database"
      archiveRoles admin originals (phase==Nothing) label
      archiveConnectRoles admin source originals
      when (phase/=Just True) $ do
        -- A pending retry can have died during its temporary postgres reopen.
        -- Close it again and refuse surviving sessions before opening one here.
        when (phase==Just False) $ do
          void $ PG.execute admin "ALTER DATABASE ? ALLOW_CONNECTIONS false" (PG.Only $ Identifier source)
          archiveNoSessions admin source Nothing
          void $ PG.execute admin "ALTER DATABASE ? ALLOW_CONNECTIONS true" (PG.Only $ Identifier source)
        let closePending=when (phase==Just False) $
              void $ PG.execute admin "ALTER DATABASE ? ALLOW_CONNECTIONS false" (PG.Only $ Identifier source)
        bracket (PG.connect settings `onException` closePending) PG.close $ \target->
          (PG.withTransaction target $ do
            pid<-archiveTargetGate target restored token identity sequenceNo
            archiveNoSessions admin source (Just pid)
            -- Commit the connection barrier before certifying the absence of
            -- other sessions. A connection racing that commit cannot be missed.
            PG.withTransaction admin $ do
              forM_ originals $ \name->void $ PG.execute admin "ALTER ROLE ? NOLOGIN" (PG.Only $ Identifier name)
              void $ PG.execute admin "REVOKE ALL ON DATABASE ? FROM PUBLIC" (PG.Only $ Identifier source)
              void $ PG.execute admin "COMMENT ON DATABASE ? IS ?" (Identifier source,pending)
              void $ PG.execute admin "ALTER DATABASE ? ALLOW_CONNECTIONS false" (PG.Only $ Identifier source)
            archiveNoSessions admin source (Just pid)
            void $ PG.execute admin "COMMENT ON DATABASE ? IS ?" (Identifier source,sealed)
          ) `onException` closePending
      -- Target session and its worker lock have closed. The sealed connection
      -- barrier now preserves the checked ledger across process death or retry.
      finalState<-archiveDatabaseState admin source
      require (finalState==[(owner,False,Just sealed)]) "archive_database_not_sealed"
      archiveRoles admin originals False label
      archiveNoSessions admin source Nothing
      PG.withTransaction admin $ do
        void $ PG.execute admin "ALTER DATABASE ? RENAME TO ?" (Identifier source,Identifier destination)
        forM_ (zip originals archived) $ \(old,new)->do
          void $ PG.execute admin "ALTER ROLE ? RENAME TO ?" (Identifier old,Identifier new)
          void $ PG.execute admin "COMMENT ON ROLE ? IS ?" (Identifier new,sealed)
    pure destination

archiveHex :: Int -> Text -> Bool
archiveHex n value=T.length value==n && T.all (`elem` ("0123456789abcdef"::String)) value

archiveInputs :: PG.ConnectInfo -> Text -> Text -> Int64 -> IO (Text,Bool,Text,Text)
archiveInputs settings token identity sequenceNo=do
  let source=T.pack $ PG.connectDatabase settings
      restored=T.length source==44 && "ecx_restore_" `T.isPrefixOf` source && archiveHex 32 (T.drop 12 source)
  require (archiveHex 32 token && archiveHex 64 identity && sequenceNo>=0) "invalid_installation_archive"
  require (PG.connectUser settings=="postgres" && (source=="ecx_bridge" || restored)) "archive_requires_postgres_admin"
  pure (source,restored,if restored then "postgres" else "ecx_setup_"<>token,"ecx-install:"<>token)

-- Private implementation shared only by the two closed archival operations.
archiveProvisioningLock :: PG.Connection -> IO ()
archiveProvisioningLock c=do
  locked<-O.runSelect c $ pure (Column(E.FunExpr "pg_catalog.pg_try_advisory_lock"
    [unColumn(O.sqlInt4 1162041393),unColumn(O.sqlInt4 19)]) :: O.Field O.SqlBool)
  require (locked==[True]) "database_provisioning_busy"

archiveTargetGate :: PG.Connection -> Bool -> Text -> Text -> Int64 -> IO Int
archiveTargetGate c restored token identity sequenceNo=do
  claimWorker c >>= flip require "worker_already_running"
  archiveLedgerGate c identity sequenceNo
  when (not restored) $ do
    checksum<-digest <$> (getDataFileName "schema.sql" >>= B.readFile)
    saved<-O.runSelect c (O.selectTable receipt) :: IO [(Text,Text)]
    require (saved==[(token,checksum)]) "installation_receipt_mismatch"
  pids<-O.runSelect c $ pure (Column(E.FunExpr "pg_catalog.pg_backend_pid" []) :: O.Field O.SqlInt4)
  case pids of [pid]->pure pid; _->reject "archive_backend_identity_missing"

-- Terminal histories remain intact, including old replacement losers and payout
-- cohorts. These queries cannot be submitted through an online reader or writer.
archiveLedgerGate :: PG.Connection -> Text -> Int64 -> IO ()
archiveLedgerGate c identity sequenceNo = do
  locked<-O.runSelect c $ Locking.forUpdate $ do
    row<-O.selectTable S.deployment
    O.where_ (S.singleton row O..== O.sqlInt8 1)
    pure (S.singleton row)
  require (locked==[1::Int64]) "corrupt_deployment"
  rows<-O.runSelect c (O.selectTable S.deployment) :: IO [S.Deployment]
  require (case rows of
    [row]->S.singleton row==1 && S.schemaVersion row==23 && S.fingerprint row==identity
      && S.paused row==1 && S.criticalSequence row==sequenceNo && S.backupSequence row==sequenceNo
    _->False) "archive_ledger_identity_or_state_mismatch"
  let absent code query=O.runSelect c (Exists.exists query) >>= flip require code . (==[False])
      text=O.sqlStrictText; num=O.sqlInt8
  absent "archive_open_orders" $ P.openOrders >> pure ()
  absent "archive_unresolved_payments" $ do
    row<-O.selectTable S.paymentRoots
    O.where_ (O.not $ O.in_ (map text ["settled","cancelled"]) (S.rootPhase row))
    pure ()
  absent "archive_principal_reserved" $ do
    (_,_,_,phase)<-O.selectTable S.reservations
    O.where_ (phase O../= text "released")
    pure ()
  absent "archive_operating_reserved" $ do
    (_,_,_,_,phase)<-O.selectTable S.operatingReservations
    O.where_ (O.in_ (map text ["quote","obligation"]) phase)
    pure ()
  absent "archive_fees_reserved" $ do
    (_,_,released)<-S.feeReservations
    O.where_ (released O..== num 0)
    pure ()
  absent "archive_cleanup_pending" $ do
    (_,_,_,_,done)<-S.workCancellations
    O.where_ (done O..== num 0)
    pure ()
  absent "archive_signature_outcome_unknown" $ do
    (_,_,_,draft,_,cancelled)<-S.workPreparations
    O.where_ (cancelled O..== num 1 O..&& O.not(O.isNull draft))
    pure ()
  absent "archive_replacement_pending" $ do
    (key,_,_,_,_,_)<-S.replacementDrafts
    cancelled<-Exists.exists $ do
      (saved,_,_)<-S.replacementCancellations
      O.where_ (saved O..== key)
      pure ()
    signed<-Exists.exists $ do
      (saved,_,_)<-S.replacementMembers
      O.where_ (saved O..== key)
      pure ()
    O.where_ (O.not cancelled O..&& O.not signed)
    pure ()
  absent "archive_chain_review" $ do
    event<-O.selectTable S.chainEvents
    O.where_ (S.eventReview event O../= num 0 O..|| S.eventKind event O..== text "awaiting_verifier")
    pure ()
  absent "archive_native_review" $ do
    (_,state)<-S.nativeRecovery
    O.where_ (state O../= text "reconfirmed")
    pure ()
  absent "archive_source_review" $ do
    (key,state)<-S.sourceRecovery
    covered<-Exists.exists $ do
      saved<-S.accountedLosses
      O.where_ (saved O..== key)
      pure ()
    O.where_ (state O../= text "restored" O..&& O.not covered)
    pure ()
  absent "archive_deposit_review" $ do
    deposit<-O.selectTable S.deposits
    covered<-Exists.exists $ do
      saved<-S.accountedLosses
      O.where_ (saved O..== S.depositId deposit)
      pure ()
    O.where_ ((S.depositAllocated deposit O..== num 0 O..|| S.depositEligible deposit O..== num 0) O..&& O.not covered)
    pure ()
  absent "archive_history_incomplete" $ do
    (chain,_)<-O.selectTable S.checkpoints
    O.where_ (O.in_ (map text ["history-progress-v1:Solana","history-progress-v1:SolanaOperating"]) chain)
    pure ()
  absent "archive_observation_incomplete" $ do
    (_,_,problem,_)<-O.selectTable S.scanHealth
    O.where_ (O.not(O.isNull problem))
    pure ()
  when (sequenceNo>0) $ do
    custody<-O.runSelect c (O.selectTable S.custody) :: IO [(Int64,Int64,Maybe Int64,Maybe Int64,Maybe Text)]
    require (case custody of
      [(1,revision,Just checked,Just at,Nothing)]->checked==revision && at>=0
      _->False) "archive_custody_not_reconciled"
  booked<-O.runSelect c $ O.aggregate (p3(O.groupBy,O.groupBy,O.sumInt8)) $ do
    (_,_,asset,account,delta)<-O.selectTable S.postings
    pure (asset,account,delta)
    :: IO [(Text,Text,Scientific)]
  let totals=M.fromListWith (+) [(asset,n)|(asset,_,n)<-booked]
      recognized=["external","principal","unallocated","float","earned","fee_pending","operating","backing","lp","source_deficit"]
  require (all (==0) totals && all (\(asset,account,n)->asset `elem` ["Native","Wrapped","Sol"]
    && account `elem` recognized && (account=="external" || n>=0)) booked) "archive_invalid_journal"
  require (all (\(_,account,n)->account `notElem` ["principal","unallocated","fee_pending","source_deficit"] || n==0) booked)
    "archive_unresolved_balances"

archiveRoleState :: PG.Connection -> [Text] -> IO [(Text,Bool,Bool,Maybe Text)]
archiveRoleState c names=O.runSelect c $ do
  (name,super,db,role,replication,bypass,login,oid)<-O.selectTable rolesTable
  O.where_ (O.in_ (map O.sqlStrictText names) name)
  let comment=Column(E.FunExpr "pg_catalog.shobj_description" [unColumn oid,unColumn(O.sqlStrictText "pg_authid")]) :: O.FieldNullable O.SqlText
  pure (name,super O..|| db O..|| role O..|| replication O..|| bypass,login,comment)

archiveRoles :: PG.Connection -> [Text] -> Bool -> Text -> IO ()
archiveRoles c names login label=do
  rows<-archiveRoleState c names
  require (length rows==length names && all (\(_,privileged,enabled,comment)->not privileged && enabled==login && comment==Just label) rows)
    "foreign_installation_roles"
  memberships<-O.runSelect c $ O.limit 1 $ do
    (name,_,_,_,_,_,_,oid)<-O.selectTable rolesTable
    (member,role)<-O.selectTable $ O.tableWithSchema "pg_catalog" "pg_auth_members" $ p2
      (O.requiredTableField "member",O.requiredTableField "roleid")
    O.where_ (O.in_ (map O.sqlStrictText names) name O..&& (member O..== oid O..|| role O..== oid))
    pure name
    :: IO [Text]
  require (null memberships) "inherited_installation_role"

archiveDatabaseState :: PG.Connection -> Text -> IO [(Text,Bool,Maybe Text)]
archiveDatabaseState c expected=O.runSelect c $ do
  (name,owner,enabled,oid)<-O.selectTable databaseCatalog
  (role,_,_,_,_,_,_,roleOid)<-O.selectTable rolesTable
  O.where_ (name O..== O.sqlStrictText expected O..&& owner O..== roleOid)
  let comment=Column(E.FunExpr "pg_catalog.shobj_description" [unColumn oid,unColumn(O.sqlStrictText "pg_database")]) :: O.FieldNullable O.SqlText
  pure (role,enabled,comment)

archiveConnectRoles :: PG.Connection -> Text -> [Text] -> IO ()
archiveConnectRoles c source allowed=do
  foreignRoles<-O.runSelect c $ O.limit 1 $ do
    (database,_,_,dbOid)<-O.selectTable databaseCatalog
    (name,super,_,_,_,_,login,oid)<-O.selectTable rolesTable
    let connect=Column(E.FunExpr "pg_catalog.has_database_privilege"
          [unColumn oid,unColumn dbOid,unColumn(O.sqlStrictText "CONNECT")]) :: Flag
    O.where_ (database O..== O.sqlStrictText source O..&& login O..&& O.not super O..&& connect
      O..&& O.not(O.in_ (map O.sqlStrictText allowed) name))
    pure name
    :: IO [Text]
  require (null foreignRoles) "foreign_installation_database_access"

archiveNoSessions :: PG.Connection -> Text -> Maybe Int -> IO ()
archiveNoSessions c source own=do
  sessions<-O.runSelect c $ O.limit 1 $ do
    (database,pid)<-O.selectTable $ O.tableWithSchema "pg_catalog" "pg_stat_activity" $ p2
      (O.requiredTableField "datname",O.requiredTableField "pid")
    O.where_ (database O..== O.sqlStrictText source)
    forM_ own $ \expected->O.where_ (pid O../= O.sqlInt4 expected)
    pure (pid :: O.Field O.SqlInt4)
    :: IO [Int]
  require (null sessions) "archive_database_connections_active"
  prepared<-O.runSelect c $ O.limit 1 $ do
    database<-O.selectTable $ O.tableWithSchema "pg_catalog" "pg_prepared_xacts" (O.requiredTableField "database")
    O.where_ (database O..== O.sqlStrictText source)
    pure database
    :: IO [Text]
  require (null prepared) "archive_prepared_transaction_pending"

databaseCatalog :: O.Table (Txt,Oid,Flag,Oid) (Txt,Oid,Flag,Oid)
databaseCatalog=O.tableWithSchema "pg_catalog" "pg_database" $ p4
  (O.requiredTableField "datname",O.requiredTableField "datdba",O.requiredTableField "datallowconn",O.requiredTableField "oid")

-- Closed recovery setup: grant service roles on an already restored paused ledger.
-- No initialization, database rename or financial-row mutation is permitted.
provisionRestoredDatabase :: PG.ConnectInfo -> Text -> Int64 -> IO ()
provisionRestoredDatabase settings identity sequenceNo=do
  let name=T.pack $ PG.connectDatabase settings
  require (PG.connectUser settings=="postgres" && sequenceNo>=0 && T.length name==44
    && "ecx_restore_" `T.isPrefixOf` name
    && T.all (`elem` ("0123456789abcdef"::String)) (T.drop 12 name)) "invalid_restored_database_target"
  bracket (PG.connect settings) PG.close $ \db->PG.withTransaction db $ do
    claimWorker db >>= flip require "worker_already_running"
    rows<-O.runSelect db (O.selectTable S.deployment) :: IO [S.Deployment]
    require (case rows of
      [r]->S.singleton r==1 && S.schemaVersion r==23 && S.fingerprint r==identity
        && S.criticalSequence r==sequenceNo && S.paused r==1
        && S.pauseReason r=="restored_requires_reconciliation"
      _->False) "restored_database_identity_or_state_mismatch"
    forM_ ["ecxbridgew","ecxbridger","ecxbridges"] $ \role->do
      present<-O.runSelect db $ do
        (n,super,createDB,createRole,replication,bypass,login,_)<-O.selectTable rolesTable
        O.where_ (n O..== O.sqlStrictText role)
        pure (super O..|| createDB O..|| createRole O..|| replication O..|| bypass,login)
        :: IO [(Bool,Bool)]
      case present of
        []->void $ PG.execute db "CREATE ROLE ? LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS" (PG.Only $ Identifier role)
        [(False,True)]->pure ()
        _->reject "unsafe_restored_service_role"
      memberships<-O.runSelect db $ do
        (n,_,_,_,_,_,_,oid)<-O.selectTable rolesTable
        member<-O.selectTable $ O.tableWithSchema "pg_catalog" "pg_auth_members" (O.requiredTableField "member")
        O.where_ (n O..== O.sqlStrictText role O..&& member O..== oid)
        pure n
        :: IO [Text]
      require (null memberships) "inherited_restored_service_role"
    void $ PG.execute db "REVOKE ALL ON DATABASE ? FROM PUBLIC" (PG.Only $ Identifier name)
    void $ PG.execute db "GRANT CONNECT ON DATABASE ? TO ecxbridgew,ecxbridger,ecxbridges" (PG.Only $ Identifier name)
    void $ PG.execute_ db "REVOKE ALL ON SCHEMA public FROM PUBLIC; REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC; REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM PUBLIC; GRANT USAGE ON SCHEMA public TO ecxbridgew,ecxbridger,ecxbridges; GRANT SELECT,INSERT,UPDATE,DELETE ON ALL TABLES IN SCHEMA public TO ecxbridgew; GRANT USAGE,SELECT ON ALL SEQUENCES IN SCHEMA public TO ecxbridgew; GRANT SELECT ON ALL TABLES IN SCHEMA public TO ecxbridger,ecxbridges; GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO ecxbridger,ecxbridges"
    forM_ ["ecxbridger","ecxbridges"] $ \role->do
      void $ PG.execute db "SET LOCAL ROLE ?" (PG.Only $ Identifier role)
      verifyReadRole db >>= flip require "unsafe_restored_reader_role"
      void $ PG.execute_ db "RESET ROLE"

data SqlOid
type Oid=O.Field SqlOid
type Txt=O.Field O.SqlText
type Flag=O.Field O.SqlBool
rolesTable :: O.Table (Txt,Flag,Flag,Flag,Flag,Flag,Flag,Oid) (Txt,Flag,Flag,Flag,Flag,Flag,Flag,Oid)
rolesTable=O.tableWithSchema "pg_catalog" "pg_roles" $ p8
  (O.requiredTableField "rolname",O.requiredTableField "rolsuper",O.requiredTableField "rolcreatedb",O.requiredTableField "rolcreaterole"
  ,O.requiredTableField "rolreplication",O.requiredTableField "rolbypassrls",O.requiredTableField "rolcanlogin",O.requiredTableField "oid")
namespaces :: O.Table (Oid,Txt) (Oid,Txt)
namespaces=O.tableWithSchema "pg_catalog" "pg_namespace" $ p2 (O.requiredTableField "oid",O.requiredTableField "nspname")
relations :: O.Table (Oid,Oid,Txt) (Oid,Oid,Txt)
relations=O.tableWithSchema "pg_catalog" "pg_class" $ p3 (O.requiredTableField "oid",O.requiredTableField "relnamespace",O.requiredTableField "relname")
receipt :: O.Table (Txt,Txt) (Txt,Txt)
receipt=O.tableWithSchema "ecx_install" "receipt" $ p2 (O.requiredTableField "token",O.requiredTableField "migration_hash")
databaseOwners :: PG.Connection -> IO [Text]
databaseOwners c=O.runSelect c $ do
  (name,owner)<-O.selectTable $ O.tableWithSchema "pg_catalog" "pg_database" $ p2 (O.requiredTableField "datname",O.requiredTableField "datdba")
  (role,_,_,_,_,_,_,oid)<-O.selectTable rolesTable
  O.where_ (name O..== O.sqlStrictText "ecx_bridge" O..&& owner O..== oid)
  pure role
