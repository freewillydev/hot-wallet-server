{-# LANGUAGE ScopedTypeVariables #-}
-- Owns an unfunded temporary PostgreSQL cluster; never uses the caller's PG* DB.
module ProvisionCheck (contract,child) where
import Bridge.Store
import qualified Bridge.Store.Backup as Backup
import qualified Bridge.Store.Schema as S
import Bridge.Store.Catalog (verifyReadRole)
import Control.Exception
import Control.Concurrent (threadDelay)
import Control.Monad (forM_,void,unless)
import qualified Data.ByteString.Char8 as B
import Data.Profunctor.Product (p2,p3,p4)
import Data.List (sort,isInfixOf)
import Data.Int (Int64)
import qualified Data.Text as T
import qualified Database.PostgreSQL.Simple as PG
import Database.PostgreSQL.Simple.Types (Identifier(..))
import qualified Opaleye as O
import Paths_ecx_bridge (getDataFileName)
import System.Directory
import System.Environment (lookupEnv,setEnv,unsetEnv,getExecutablePath,getEnvironment)
import System.FilePath ((</>))
import System.IO (openTempFile,hClose)
import System.Posix.Files (setFileMode)
import System.Posix.Signals (signalProcess,sigKILL)
import System.Exit (ExitCode(..))
import System.Timeout (timeout)
import System.Process (readProcess,callProcess,withCreateProcess,proc,env,getPid,waitForProcess)
import Test.QuickCheck (quickCheckWithResult,stdArgs,maxSuccess,ioProperty,isSuccess)

data SqlOid
type NamespaceFields = (O.Field SqlOid,O.Field O.SqlText)
type ColumnFields = (O.Field O.SqlText,O.Field O.SqlText,O.Field O.SqlText,O.Field O.SqlText)

child :: FilePath -> IO ()
child root=evalSetup PG.defaultConnectInfo {PG.connectHost=root,PG.connectPort=29479,PG.connectUser="postgres",PG.connectDatabase="postgres"}
  (ProvisionDatabase "0123456789abcdef0123456789abcdef")

contract :: IO ()
contract=bracket directory removeDirectoryRecursive $ \root->do
  callProcess "initdb" ["-D",root</>"data","-U","postgres","--auth=trust","--no-locale"]
  let control args=callProcess "pg_ctl" (["-D",root</>"data"]<>args)
  bracket_ (control ["-l",root</>"postgres.log","-o","-k "<>root<>" -h '' -p 29479 -c shared_buffers=16MB -c max_connections=12","-w","start"])
    (control ["-m","immediate","-w","stop"]) $ do
      let admin=PG.defaultConnectInfo {PG.connectHost=root,PG.connectPort=29479,PG.connectUser="postgres",PG.connectDatabase="postgres"}
      result<-quickCheckWithResult stdArgs {maxSuccess=1} (ioProperty $ checks root admin >> pure True)
      unless(isSuccess result)(fail "database provisioning contract failed")
 where
  directory=do
    (path,h)<-openTempFile "/tmp" "ecx-provision-"
    hClose h; removeFile path; createDirectory path; setFileMode path 0o700; pure path

checks :: FilePath -> PG.ConnectInfo -> IO ()
checks root admin=bracket(PG.connect admin) PG.close $ \c->do
  let token="0123456789abcdef0123456789abcdef"
      run=evalSetup admin(ProvisionDatabase token)
      ddl sql=void(PG.execute_ c sql)
      refused expected action=(action >> fail "expected refusal") `catch` \(BridgeError actual)->unless(actual==expected)(fail $ "expected "<>T.unpack expected<>"; received "<>T.unpack actual)
      target=admin {PG.connectDatabase="ecx_bridge"}
  ddl "CREATE ROLE ecxbridgew NOLOGIN"
  refused "foreign_installation_roles" run
  ddl "DROP ROLE ecxbridgew"
  ddl "CREATE DATABASE ecx_bridge"
  refused "foreign_installation_database" run
  ddl "DROP DATABASE ecx_bridge"
  createDirectory(root</>"bad")
  original<-getDataFileName "schema.sql" >>= B.readFile
  B.writeFile(root</>"bad/schema.sql") $ B.unlines $ concatMap
    (\line->if line=="COMMIT;" then ["CREATE TABLE deliberately_invalid(;",line] else [line]) (B.lines original)
  prior<-lookupEnv "ecx_bridge_datadir"
  bracket_ (setEnv "ecx_bridge_datadir" (root</>"bad"))
    (maybe(unsetEnv "ecx_bridge_datadir")(setEnv "ecx_bridge_datadir") prior) $
      (run >> fail "invalid schema accepted") `catch` \(_::PG.SqlError)->pure ()
  -- Roles and DB survive; the entire schema+receipt transaction rolls back.
  bracket(PG.connect target) PG.close $ \db->do
    rows<-O.runSelect db $ do
      (schema,name)<-O.selectTable tables
      O.where_ (O.in_ [O.sqlStrictText "public",O.sqlStrictText "ecx_install"] schema)
      pure name
      :: IO [T.Text]
    check(null rows)
  refused "foreign_installation_roles" (evalSetup admin $ ProvisionDatabase "fedcba9876543210fedcba9876543210")
  -- Hold a DDL name collision until the child reaches the final schema statement, then
  -- kill the actual OS process (no Haskell exception cleanup can run there).
  -- Match the query prefix: pg_stat_activity may truncate the final DDL barrier.
  B.writeFile(root</>"bad/schema.sql") $ B.unlines $ concatMap
    (\line->if line=="COMMIT;" then ["CREATE TABLE public.provision_kill_barrier(id integer);",line] else [line]) (B.lines original)
  bracket(PG.connect target) PG.close $ \blocker->do
    PG.begin blocker
    void $ PG.execute_ blocker "CREATE TABLE public.provision_kill_barrier(id integer)"
    bracket_ (setEnv "ecx_bridge_datadir" (root</>"bad"))
      (maybe(unsetEnv "ecx_bridge_datadir")(setEnv "ecx_bridge_datadir") prior) $
      do
        executable<-getExecutablePath
        environment<-getEnvironment
        withCreateProcess (proc executable []) {env=Just(("ECX_PROVISION_CHILD",root):filter((/="ECX_PROVISION_CHILD").fst) environment)} $ \_ _ _ process->do
          let blocked=do
                rows<-O.runSelect c $ do
                  (db,event,query)<-O.selectTable activity
                  O.where_ (db O..== O.sqlStrictText "ecx_bridge" O..&& O.fromNullable (O.sqlStrictText "") event O..== O.sqlStrictText "Lock"
                    O..&& O.like query (O.sqlStrictText "%CREATE FUNCTION bridge_json_valid%"))
                  pure query
                  :: IO [T.Text]
                if null rows then threadDelay 20000 >> blocked else pure ()
          reached<-timeout 10000000 blocked
          pid<-getPid process >>= maybe(fail "child exited before interruption") pure
          signalProcess sigKILL pid
          status<-waitForProcess process
          unless(reached==Just ())(fail "child never reached schema install lock")
          unless(status/=ExitSuccess)(fail "child unexpectedly succeeded before SIGKILL")
    PG.rollback blocker
  -- Wait for the disconnected backend to finish rollback and release its lock.
  let retry=run `catch` \(BridgeError code)->if code=="database_provisioning_busy"
        then threadDelay 20000 >> retry else throwIO(BridgeError code)
  recovered<-timeout 10000000 retry
  unless(recovered==Just ())(fail "killed provisioner retained ownership lock")
  run; run
  evalSetup target(InitializeLedger $ T.replicate 64 "a")
  before<-bracket(PG.connect target) PG.close $ \db->do
    void $ O.runInsert db O.Insert {O.iTable=S.scanHealth,O.iRows=[(O.sqlStrictText "Native",O.toNullable $ O.sqlInt8 42,O.null,O.sqlInt8 42)],O.iReturning=O.rCount,O.iOnConflict=Nothing}
    (,) <$> (O.runSelect db $ O.selectTable S.deployment) <*> (O.runSelect db $ O.selectTable S.scanHealth)
      :: IO ([S.Deployment],[(T.Text,Maybe Int64,Maybe T.Text,Int64)])
  run
  after<-bracket(PG.connect target) PG.close $ \db->
    (,) <$> (O.runSelect db $ O.selectTable S.deployment) <*> (O.runSelect db $ O.selectTable S.scanHealth)
  check(before==after)
  bracket_ (setEnv "ecx_bridge_datadir" (root</>"bad"))
    (maybe(unsetEnv "ecx_bridge_datadir")(setEnv "ecx_bridge_datadir") prior) $
      refused "installation_receipt_mismatch" run
  forM_ ["ecxbridger","ecxbridges"] $ \role->
    bracket(PG.connect target {PG.connectUser=role}) PG.close $ \db->verifyReadRole db >>= check
  -- Real provisioning creates ecx_install.receipt, deliberately inaccessible to
  -- the runtime reader. Back up that exact layout, not an artificial fixture.
  let identity=T.replicate 64 "a"
      readerSettings=target {PG.connectUser="ecxbridger"}
      receiptNames :: PG.Connection -> IO [T.Text]
      receiptNames db=O.runSelect db $ do
        (schema,name)<-O.selectTable tables
        O.where_ (schema O..== O.sqlStrictText "ecx_install")
        pure name
      inventory :: PG.Connection -> IO [[T.Text]]
      inventory db=do
        common<-mapM (\(schema,table,namespace,column)->sort <$> O.runSelect db (do
          (space,name)<-O.selectTable $ O.tableWithSchema schema table $
            p2(O.requiredTableField namespace,O.requiredTableField column)
          O.where_ (space O..== O.sqlStrictText "public")
          pure (name :: O.Field O.SqlText)))
          [("information_schema","tables","table_schema","table_name")
          ,("pg_catalog","pg_sequences","schemaname","sequencename")
          ,("information_schema","routines","routine_schema","routine_name")
          ,("information_schema","triggers","trigger_schema","trigger_name")
          ,("pg_catalog","pg_indexes","schemaname","indexname")]
        actualConstraints<-O.runSelect db $ do
          (namespace,name)<-O.selectTable constraints
          (oid,schema)<-O.selectTable namespaces
          O.where_ (namespace O..== oid O..&& schema O..== O.sqlStrictText "public")
          pure name
        pure(common<>[sort actualConstraints])
      columns :: PG.Connection -> IO [(T.Text,T.Text,T.Text)]
      columns db=sort <$> O.runSelect db (do
        (schema,table,column,nullable)<-O.selectTable columnInfo
        O.where_ (schema O..== O.sqlStrictText "public")
        pure(table,column,nullable))
  objects<-bracket(PG.connect target) PG.close $ \db->do
    receiptNames db >>= same "source installer receipt" ["receipt"]
    inventory db
  unless(all (not . null) objects)(fail $ "empty source inventory category; counts="<>show(map length objects))
  columnState<-bracket(PG.connect target) PG.close columns
  archive<-withReader readerSettings identity False $ \reader->evalBackup reader(ExportLedger root)
  listing<-readProcess "pg_restore" ["--list",archivePath archive] ""
  unless(not $ "ecx_install" `isInfixOf` listing)(fail "installer schema present in archive")
  bracket (evalRestore target $ RestoreLedger (manifestPath archive) identity 0)
    (\(database,_)->Backup.discardRestore admin {PG.connectDatabase=T.unpack database}) $ \(database,n)->do
      unless(n==0 && database/="ecx_bridge")(fail $ "restore target/sequence: "<>show(database,n))
      let restoredSettings=admin {PG.connectDatabase=T.unpack database}
      refused "restored_database_identity_or_state_mismatch" (evalSetup restoredSettings $ ProvisionRestoredDatabase "wrong" n)
      refused "restored_database_identity_or_state_mismatch" (evalSetup restoredSettings $ ProvisionRestoredDatabase identity (n+1))
      evalSetup restoredSettings (ProvisionRestoredDatabase identity n)
      evalSetup restoredSettings (ProvisionRestoredDatabase identity n)
      forM_ ["ecxbridger","ecxbridges"] $ \role->
        bracket(PG.connect restoredSettings {PG.connectUser=role}) PG.close $ \db->verifyReadRole db >>= same "reader privileges after restore" True

      bracket(PG.connect admin {PG.connectDatabase=T.unpack database}) PG.close $ \db->do
        inventory db >>= sameInventory objects
        columns db >>= same "column nullability unchanged" columnState
        receiptNames db >>= same "restored installer receipt must be absent" []
        restored<-(,) <$> (O.runSelect db $ O.selectTable S.deployment) <*> (O.runSelect db $ O.selectTable S.scanHealth)
        let (rows,observations)=before
        same "restored deployment and observation rows" ([row {S.paused=1,S.pauseReason="restored_requires_reconciliation"} | row<-rows],observations) restored
  -- Supplying the existing source DB cannot select it as a restore/cleanup target.
  refused "invalid_restore_database" (Backup.discardRestore target)
  bracket(PG.connect target) PG.close $ \db->do
    inventory db >>= sameInventory objects
    columns db >>= same "column nullability unchanged" columnState
    receiptNames db >>= same "source installer receipt" ["receipt"]
    original<-(,) <$> (O.runSelect db $ O.selectTable S.deployment) <*> (O.runSelect db $ O.selectTable S.scanHealth)
    same "source deployment and observation rows unchanged" before original
  bracket(PG.connect readerSettings) PG.close $ \db->verifyReadRole db >>= same "reader privileges after restore" True
  archiveChecks c admin target token identity
  putStrLn "PASS: provisioned restricted-reader backup, installer receipt excluded, all public tables/sequences/functions/constraints/triggers/indexes restored, ledger and observation data preserved, paused isolated restore, reader remains restricted"
  putStrLn "PASS: foreign role/database refusal, schema rollback, SIGKILL during installation and successful retry, changed-schema refusal, read-only roles and initialized ledger/observation preservation"
 where
  same :: (Eq a,Show a) => String -> a -> a -> IO ()
  same label expected actual=unless(expected==actual)(fail $ label<>" expected="<>show expected<>" actual="<>show actual)
  sameInventory :: [[T.Text]] -> [[T.Text]] -> IO ()
  sameInventory expected actual=do
    same "inventory category count" (length expected) (length actual)
    forM_ (zip3 ["tables/views","sequences","functions","triggers","indexes","constraints"] expected actual) $ \(label,old,new)->
      unless(old==new)(fail $ "inventory "<>label<>" counts="<>show(length old,length new)
        <>" missing="<>show(take 8 $ filter (`notElem` new) old)<>" added="<>show(take 8 $ filter (`notElem` old) new))
  check True=pure ()
  check False=fail "provisioning invariant failed"
  -- information_schema synthesizes OID-based names for NOT NULL constraints.
  -- Compare real named constraints, and cover NOT NULL via column metadata above.
  constraints :: O.Table NamespaceFields NamespaceFields
  constraints=O.tableWithSchema "pg_catalog" "pg_constraint" $ p2(O.requiredTableField "connamespace",O.requiredTableField "conname")
  namespaces :: O.Table NamespaceFields NamespaceFields
  namespaces=O.tableWithSchema "pg_catalog" "pg_namespace" $ p2(O.requiredTableField "oid",O.requiredTableField "nspname")
  columnInfo :: O.Table ColumnFields ColumnFields
  columnInfo=O.tableWithSchema "information_schema" "columns" $ p4(O.requiredTableField "table_schema",O.requiredTableField "table_name",O.requiredTableField "column_name",O.requiredTableField "is_nullable")
  tables :: O.Table (O.Field O.SqlText,O.Field O.SqlText) (O.Field O.SqlText,O.Field O.SqlText)
  tables=O.tableWithSchema "information_schema" "tables" $ p2(O.requiredTableField "table_schema",O.requiredTableField "table_name")
  activity :: O.Table (O.Field O.SqlText,O.FieldNullable O.SqlText,O.Field O.SqlText) (O.Field O.SqlText,O.FieldNullable O.SqlText,O.Field O.SqlText)
  activity=O.tableWithSchema "pg_catalog" "pg_stat_activity" $ p3(O.requiredTableField "datname",O.requiredTableField "wait_event_type",O.requiredTableField "query")

-- The same disposable cluster exercises financial refusal before any catalog
-- mutation and durable pending/sealed prefixes left by an interrupted process.
archiveChecks :: PG.Connection -> PG.ConnectInfo -> PG.ConnectInfo -> T.Text -> T.Text -> IO ()
archiveChecks adminConnection admin target token identity=do
  let suffix=T.replicate 32 "c"
      archived="ecx_archive_"<>suffix
      run=evalSetup target (ArchiveInstallationDatabase token identity 0 suffix)
      preflight=evalSetup target (CheckInstallationArchive token identity 0)
      text=O.sqlStrictText; num=O.sqlInt8
      refused expected action=(void action >> fail "expected archive refusal") `catch`
        \(BridgeError actual)->unless(actual==expected)(fail $ "expected "<>T.unpack expected<>"; received "<>T.unpack actual)
      check label ok=unless ok(fail label)
      fixture action=bracket(PG.connect target) PG.close action
      catalog name=O.runSelect adminConnection $ do
        (database,allowed)<-O.selectTable $ O.tableWithSchema "pg_catalog" "pg_database" $ p2
          (O.requiredTableField "datname",O.requiredTableField "datallowconn")
        O.where_ (database O..== text name)
        pure (allowed :: O.Field O.SqlBool)
        :: IO [Bool]
      roles names=O.runSelect adminConnection $ do
        (name,login)<-O.selectTable $ O.tableWithSchema "pg_catalog" "pg_roles" $ p2
          (O.requiredTableField "rolname",O.requiredTableField "rolcanlogin")
        O.where_ (O.in_ (map text names) name)
        pure (name,login :: O.Field O.SqlBool)
        :: IO [(T.Text,Bool)]
      originals=["ecxbridgew","ecxbridger","ecxbridges"]
      archivedRoles ending=map (<>ending) ["ecx_archived_w_","ecx_archived_r_","ecx_archived_s_"]
      receipt ending phase=T.intercalate ":" ["ecx-archive-v1",token,identity,"0","ecx_bridge",ending,phase]
      barrier marker=PG.withTransaction adminConnection $ do
        forM_ originals $ \role->void $ PG.execute adminConnection "ALTER ROLE ? NOLOGIN" (PG.Only $ Identifier role)
        void $ PG.execute adminConnection "COMMENT ON DATABASE ecx_bridge IS ?" (PG.Only marker)
        void $ PG.execute_ adminConnection "ALTER DATABASE ecx_bridge ALLOW_CONNECTIONS false"
      post db key n=do
        void $ O.runInsert db O.Insert {O.iTable=S.events,O.iRows=[(text key,text "archive contract")],O.iReturning=O.rCount,O.iOnConflict=Nothing}
        void $ O.runInsert db O.Insert {O.iTable=S.postings,
          O.iRows=[(Nothing,text key,text "Native",text account,num delta)| (account,delta)<-[("unallocated",n),("external",negate n)]],O.iReturning=O.rCount,O.iOnConflict=Nothing}
  untouched<-fixture $ \db->O.runSelect db (O.selectTable S.deployment) :: IO [S.Deployment]
  preflight
  catalog "ecx_bridge" >>= check "preflight disabled empty database" . (==[True])
  roles originals >>= check "preflight disabled original roles" . (==[(name,True)|name<-sort originals]) . sort
  fixture (\db->O.runSelect db $ O.selectTable S.deployment) >>= check "preflight changed deployment" . (==untouched)
  refused "archive_ledger_identity_or_state_mismatch" (evalSetup target $ ArchiveInstallationDatabase token (T.replicate 64 "b") 0 suffix)
  refused "archive_ledger_identity_or_state_mismatch" (evalSetup target $ ArchiveInstallationDatabase token identity 1 suffix)
  fixture $ \db->do
    void $ O.runInsert db O.Insert {O.iTable=S.orders,
      O.iRows=[S.Order (text "archive-open") (text "cap") (text "idempotency") (text "request")
        (text "{}") (text "{}") (text "{}") (text "AwaitingDeposit") (num 10) (num 20) O.null O.null (num 0)],
      O.iReturning=O.rCount,O.iOnConflict=Nothing}
    void $ O.runInsert db O.Insert {O.iTable=S.reservations,
      O.iRows=[(text "archive-open",text "Wrapped",num 10,text "quote")],O.iReturning=O.rCount,O.iOnConflict=Nothing}
  beforeRefusal<-fixture $ \db->O.runSelect db (O.selectTable S.orders) :: IO [S.Order]
  refused "archive_open_orders" preflight
  fixture (\db->O.runSelect db $ O.selectTable S.orders) >>= check "preflight refusal changed orders" . (==beforeRefusal)
  refused "archive_open_orders" run
  catalog "ecx_bridge" >>= check "refusal disabled original database" . (==[True])
  roles originals >>= check "refusal disabled original roles" . (==[(name,True)|name<-sort originals]) . sort
  fixture $ \db->void $ O.runUpdate db O.Update {O.uTable=S.orders,
    O.uUpdateWith= \row->row {S.admissionState=text "ExpiredUnfunded"},
    O.uWhere= \row->S.orderId row O..== text "archive-open",O.uReturning=O.rCount}
  refused "archive_principal_reserved" run
  let withdrawal=T.replicate 64 "f"
      payment="fee:"<>withdrawal
  fixture $ \db->PG.withTransaction db $ do
    void $ O.runInsert db O.Insert {O.iTable=S.withdrawals,
      O.iRows=[S.Withdrawal (text withdrawal) (text "Native") (num 5) (text "recipient") (text "{}") (text "archive contract") (num 1)],O.iReturning=O.rCount,O.iOnConflict=Nothing}
    void $ O.runInsert db O.Insert {O.iTable=S.paymentRoots,
      O.iRows=[S.PaymentRoot (text payment) O.null (O.toNullable $ text withdrawal) O.null (text "Native") O.null (text "ready") O.null O.null O.null],O.iReturning=O.rCount,O.iOnConflict=Nothing}
    void $ O.runInsert db O.Insert {O.iTable=S.feeHolds,
      O.iRows=[(text payment,text "Native",num 1,num 0)],O.iReturning=O.rCount,O.iOnConflict=Nothing}
  refused "archive_unresolved_payments" run
  refused "archive_unresolved_payments" preflight
  fixture $ \db->PG.withTransaction db $ do
    void $ O.runUpdate db O.Update {O.uTable=S.feeHolds,
      O.uUpdateWith= \(key,asset,n,_)->(key,asset,n,num 1),O.uWhere=const(O.sqlBool True),O.uReturning=O.rCount}
    void $ O.runInsert db O.Insert {O.iTable=S.cancellations,
      O.iRows=[(text withdrawal,text "archive contract",num 2)],O.iReturning=O.rCount,O.iOnConflict=Nothing}
    void $ O.runUpdate db O.Update {O.uTable=S.paymentRoots,
      O.uUpdateWith= \row->row {S.rootPhase=text "cancelled"},O.uWhere=const(O.sqlBool True),O.uReturning=O.rCount}
  -- A crash after the first catalog commit must rerun the financial gate, not
  -- trust that the earlier read was enough. Failure leaves the barrier closed.
  barrier (receipt suffix "pending")
  refused "archive_principal_reserved" run
  catalog "ecx_bridge" >>= check "pending refusal reopened database" . (==[False])
  void $ PG.execute_ adminConnection "ALTER DATABASE ecx_bridge ALLOW_CONNECTIONS true"
  fixture $ \db->do
    void $ O.runUpdate db O.Update {O.uTable=S.reservations,
      O.uUpdateWith= \(key,asset,n,_)->(key,asset,n,text "released"),O.uWhere=const(O.sqlBool True),O.uReturning=O.rCount}
    post db "archive-unclassified" 7
  void $ PG.execute_ adminConnection "ALTER DATABASE ecx_bridge ALLOW_CONNECTIONS false"
  refused "archive_unresolved_balances" run
  void $ PG.execute_ adminConnection "ALTER DATABASE ecx_bridge ALLOW_CONNECTIONS true"
  fixture $ \db->post db "archive-classified" (-7)
  -- An existing reader still blocks retirement even though it cannot write.
  fixture $ \_->refused "archive_database_connections_active" run
  void $ PG.execute_ adminConnection "ALTER DATABASE ecx_bridge ALLOW_CONNECTIONS false"
  actual<-run
  check "wrong archived database" (actual==archived)
  run >>= check "archive replay changed name" . (==archived)
  catalog "ecx_bridge" >>= check "original database still exists after rename" . null
  catalog archived >>= check "archived database permits connections" . (==[False])
  roles originals >>= check "canonical roles survived archive" . null
  roles (archivedRoles suffix) >>= check "archived roles permit login" . (==[(name,False)|name<-sort(archivedRoles suffix)]) . sort
  -- Reopen only in this disposable fixture to assert exact retained histories.
  void $ PG.execute adminConnection "ALTER DATABASE ? ALLOW_CONNECTIONS true" (PG.Only $ Identifier archived)
  bracket(PG.connect target {PG.connectDatabase=T.unpack archived}) PG.close $ \db->do
    orders<-O.runSelect db (fmap S.orderId $ O.selectTable S.orders) :: IO [T.Text]
    events<-O.runSelect db (fmap fst $ O.selectTable S.events) :: IO [T.Text]
    payments<-O.runSelect db (fmap S.rootPhase $ O.selectTable S.paymentRoots) :: IO [T.Text]
    check "archived records were removed" (orders==["archive-open"] && sort events==["archive-classified","archive-unclassified"])
    check "terminal payment history was removed" (payments==["cancelled"])
  void $ PG.execute adminConnection "ALTER DATABASE ? ALLOW_CONNECTIONS false" (PG.Only $ Identifier archived)
  -- A fresh installation uses new roles; replay must leave it untouched.
  let nextToken=T.replicate 32 "d"
      nextSuffix=T.replicate 32 "e"
  evalSetup admin (ProvisionDatabase nextToken)
  evalSetup target (InitializeLedger identity)
  run >>= check "archive replay confused fresh installation" . (==archived)
  catalog "ecx_bridge" >>= check "archive replay disabled fresh installation" . (==[True])
  refused "foreign_installation_database" (evalSetup target $ ArchiveInstallationDatabase token identity 0 nextSuffix)
  refused "foreign_archive_database" (evalSetup target $ ArchiveInstallationDatabase nextToken identity 0 suffix)
  let nextReceipt=T.intercalate ":" ["ecx-archive-v1",nextToken,identity,"0","ecx_bridge",nextSuffix,"sealed"]
  barrier nextReceipt
  second<-evalSetup target (ArchiveInstallationDatabase nextToken identity 0 nextSuffix)
  check "sealed prefix was not resumed" (second=="ecx_archive_"<>nextSuffix)
  catalog second >>= check "sealed replay reopened database" . (==[False])
  let emptyToken=T.replicate 32 "1"
      emptySuffix=T.replicate 32 "2"
  evalSetup admin (ProvisionDatabase emptyToken)
  evalSetup target (InitializeLedger identity)
  evalSetup target (CheckInstallationArchive emptyToken identity 0)
  catalog "ecx_bridge" >>= check "empty preflight disabled database" . (==[True])
  roles originals >>= check "empty preflight disabled roles" . (==[(name,True)|name<-sort originals]) . sort
  empty<-evalSetup target (ArchiveInstallationDatabase emptyToken identity 0 emptySuffix)
  check "empty initialized ledger could not archive" (empty=="ecx_archive_"<>emptySuffix)
  putStrLn "PASS: archive preflight accepts empty ledgers and refuses unresolved orders/payments without changing deployment, orders or enabled roles/database; retirement refuses holds/balances/wrong identity/sequence/connections/foreign catalog state; pending/sealed prefixes replay, records survive, archive roles remain disabled and fresh provisioning stays isolated"
