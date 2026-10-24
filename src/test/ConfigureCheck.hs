module ConfigureCheck (contract,walletProperty) where
import qualified Bridge.Config as C
import qualified NodeSetup
import qualified Bootstrap
import qualified InstallConfig
import qualified ReconfigureFiles as RF
import qualified Reconfigure
import qualified RotationFiles as RD
import qualified Token
import qualified Token.Operation as TO
import Bridge.SDKBuild (sdkLibraryPath)
import System.Environment (getEnv,setEnv,getExecutablePath)
import System.Info (os,arch)
import Bridge.File (hashHandle)
import Bridge.Identity (digest)
import qualified Data.Text.Encoding as TE
import GHC.IO.Handle (hDuplicate,hDuplicateTo)
import qualified Data.Aeson.Key as Key
import System.Posix.Signals (signalProcess,nullSignal)
import System.Timeout (timeout)
import Control.Exception (evaluate,finally,AsyncException(ThreadKilled),SomeException)
import qualified Data.ByteString.Char8 as B8
import Crypto.MAC.HMAC (hmac,HMAC)
import Crypto.Hash (SHA256,Digest,hash)
import qualified Data.ByteString.Base58 as B58
import Crypto.Random (getRandomBytes)
import Bridge.AdminKey (savePrivate,readPrivate)
import Bridge.Wallet (mnemonic,mixWalletEntropy,walletKey,nativeDescriptors)
import Bridge.NativeKey (deriveChild)
import qualified Bridge.Native as N
import Bridge.Wire (Profile(..))
import qualified Bridge.Wire as W
import Bridge.Domain (units,amount,gasLamports,gasEcxFee)
import Bridge.Error (BridgeError(..),require)
import Bridge.RPC (fieldValue)
import qualified Data.Aeson.KeyMap as KM
import Data.IORef
import Control.Monad (unless,forM,forM_)
import qualified Data.ByteArray.Encoding as Hex
import Data.Word (Word8)
import Test.QuickCheck hiding ((.&.))
import Bridge.SolanaMessage (base58,Transaction(..))
import qualified Data.ByteString.Base64 as B64
import Control.Exception (bracket,try,throwIO)
import Crypto.Error (CryptoFailable(..))
import qualified Crypto.PubKey.Ed25519 as Ed
import qualified Data.ByteArray as BA
import qualified Data.ByteString as B
import qualified Data.ByteString.Lazy as L
import qualified Data.Text as T
import Data.Aeson (encode,eitherDecodeStrict',Value(..),object,(.=),toJSON)
import qualified Data.Map.Strict as M
import Data.List (sort,isInfixOf,isPrefixOf,isSuffixOf)
import Data.Bits ((.&.),shiftR)
import System.Directory
import System.FilePath ((</>))
import System.IO (openTempFile,hClose,hPutStrLn,hFlush,hGetChar,hGetContents,withBinaryFile,stdin,IOMode(ReadMode))
import System.Posix.Files (setFileMode,getFileStatus,fileMode,linkCount,createLink,createSymbolicLink)
import System.Posix.User (getEffectiveUserID,getEffectiveGroupID)
import System.Process
import System.Exit (ExitCode(..))

-- Real executable, disposable private keys, no network/database/service changes.
contract :: IO Bool
contract=bracket temporary removeDirectoryRecursive $ \directory->do
  Just executable<-findExecutable "ecx-bridge"
  let seed=B.replicate 32 7
  secret<-case Ed.secretKey seed of CryptoPassed key->pure key; _->fail "test key"
  let public=BA.convert(Ed.toPublic secret)::B.ByteString
      owner=T.unpack(base58 public)
      history=T.unpack(base58 $ B.replicate 64 1)
      run input=readCreateProcessWithExitCode ((proc executable ["configure","--advanced"]) {cwd=Just directory}) input
      key=directory</>"key.json"; worker=directory</>"worker.auth"; signer=directory</>"signer.auth"
      invalidUnlock=directory</>"invalid-unlock"; unlock=directory</>"unlock"
  savePrivate key (L.toStrict $ encode $ B.unpack(seed<>public))
  savePrivate worker "worker:password";savePrivate signer "signer:password"
  savePrivate invalidUnlock (B.singleton 255);savePrivate unlock " exact unlock secret "
  -- Field order is explicitly sorted, and booleans/numbers retain their JSON types.
  let fields=["false","1200",owner,owner,"test-deployment","10000","1000"
        ,"invalid-number","4","2100000","10000000","10000","100000",owner
        ,"00000047dcc9d64b767687d6a5e610c411dd85db5460e824c0f7284f5514bc47"
        ,"16000","1","http://127.0.0.1:29432","test-wallet","[]","","300","8080","8081"
        ,history,history,"https://api.devnet.solana.com","-"]
      answers=["","L2LSignetDevnet","import"]<>fields<>["no","yes","release","installer","release.pem","candidate",key,"existing",worker,signer,"-","-","-","-","-","-","no"]
  (code,_,_)<-run (unlines answers)
  if code/=ExitSuccess then putStrLn "FAIL configure contract: advanced-settings" >> pure False else do
    let out=directory</>".ecx-bridge"
    config<-C.loadConfig(out</>"worker.json")
    other<-C.loadConfig(out</>"signer.json")
    modes<-mapM (fmap ((.&. 0o777) . fileMode) . getFileStatus . (out</>)) ["worker.json","signer.json","setup.json","sources.json"]
    entries<-listDirectory out
    sources<-either fail pure . (eitherDecodeStrict' :: B.ByteString -> Either String (M.Map String FilePath)) =<< B.readFile(out</>"sources.json")
    originalKey<-B.readFile key
    originalWorker<-B.readFile worker
    originalSigner<-B.readFile signer
    before<-B.readFile(out</>"worker.json")
    (again,_,_)<-run "\n"
    after<-B.readFile(out</>"worker.json")
    (cancelled,_,_)<-run ((directory</>"cancelled")<>"\n")
    partial<-doesDirectoryExist(directory</>"cancelled")
    let local=directory</>"source-setup"
        sourceAnswers=[local,"L2LSignetDevnet","import"]<>fields<>["no","yes","invalid-mode","source",directory,worker,key,"existing",worker,signer,invalidUnlock,unlock,"-","-","-","-","-","no"]
    (sourceCode,sourceOutput,_)<-run (unlines sourceAnswers)
    sourceSetup<-either fail pure . (eitherDecodeStrict' :: B.ByteString -> Either String Value) =<< B.readFile(local</>"setup.json")
    sourceWorker<-C.loadConfig(local</>"worker.json")
    sourceSigner<-C.loadConfig(local</>"signer.json")
    let phrase=unwords (replicate 11 "abandon"<>["about"])
        restored=directory</>"restored-setup"
        wallet=directory</>"recovered-wallet"
        phraseFile=directory</>"recovery.txt"
    savePrivate phraseFile (B.pack $ map (fromIntegral . fromEnum) phrase)
    (restoredCode,restoredOutput,_)<-run $ unlines $
      [restored,"L2LSignetDevnet","restore",phraseFile,wallet]
      <>take 3 fields<>drop 4 fields<>["no","yes","source",directory,worker,"existing",worker,signer,"-","-","-","-","-","-","no"]
    restoredConfig<-C.loadConfig(restored</>"signer.json")
    recovered<-B.readFile(wallet</>"solana.keypair.json")
    recoveredPhrase<-B.readFile(wallet</>"solana-recovery.txt")
    secretModes<-mapM (fmap ((.&. 0o777) . fileMode) . getFileStatus . (wallet</>)) ["solana-recovery.txt","solana.keypair.json"]
    (pipeCode,pipeStdout,pipeOutput)<-run $ unlines [directory</>"pipe","L2LSignetDevnet","generate"]
    let interrupted=directory</>"interrupted-setup"
        retained=directory</>"retained-wallet"
    (interruptedCode,_,_)<-run $ unlines [interrupted,"L2LSignetDevnet","restore",phraseFile,retained]
    retainedKey<-B.readFile(retained</>"solana.keypair.json")
    settingsRemain<-doesDirectoryExist interrupted
    nativeChecked<-nativeSeedContract directory
    simplifiedChecked<-simpleContract directory executable
    require simplifiedChecked "interactive_wallet_mode_contract_failed"
    importedChecked<-importContract directory executable
    require importedChecked "import_wallet_mode_contract_failed"
    reconfigureFilesContract
    privateRecordCrashContract
    rotationFilesContract
    -- A verified pre-created ATA has no local creation attempt. Do not block
    -- ordinary reconciliation, and never silently skip an existing corrupt file.
    externalAta<-Bootstrap.initialAccounting directory config "owned SOL"
    let ownerText=T.pack owner; mint=Bootstrap.canonicalMint
        attempt=directory</>"ata-creation.json"
    ata<-TO.runSafe (TO.Request $ Token.AssociatedAddress sdkLibraryPath ownerText mint)
    let operation=Token.Associated ownerText mint ata ownerText 2039280 (base58 $ B.replicate 32 1)
    let rejectIntent value=case (eitherDecodeStrict' (L.toStrict $ encode value)::Either String Token.Request) of
          Left _->True; Right _->False
        Object fields=toJSON operation
    require (all (\verb->rejectIntent $ Object $ KM.insert "verb" (String verb) fields)
      ["mint","burn","create","metadata","nonce_mint","create_nonce"]
      && rejectIntent (Object $ KM.insert "amount" (String "1") fields)) "ata_setup_accepts_only_closed_intent"
    unsigned<-TO.runSafe (TO.Request $ Token.Prepare sdkLibraryPath operation)
    -- Fixture signing stays in the test; production exposes only guarded ATA setup.
    Transaction _ _ message<-either (fail . T.unpack) pure (Token.validate operation unsigned)
    let signedBytes=BA.convert(Ed.sign secret (Ed.toPublic secret) message)::B.ByteString
        signature=base58 signedBytes
        saved=Token.Saved operation signature (TE.decodeUtf8 $ B64.encode (B.singleton 1<>signedBytes<>message)) Nothing
    _<-either (fail . T.unpack) pure (Token.validateSaved saved)
    savePrivate attempt (L.toStrict $ encode saved)
    localAta<-Bootstrap.initialAccounting directory config "owned SOL"
    localReplay<-Bootstrap.initialAccounting directory config "owned SOL"
    B.writeFile attempt "{}"
    corruptAta<-try(Bootstrap.initialAccounting directory config "owned SOL") :: IO (Either BridgeError (Maybe Value))
    historyPreflight<-preflightContract
    backupAccessContract directory
    backupChecked<-backupTimeoutContract directory
    handoffChecked<-backupHandoffCancellation directory
    expectedKey<-either (const $ fail "fixture mnemonic") pure (walletKey phrase)
    let expectedSetup=object ["existing" .= False,"method" .= ("source"::String),"sourceRoot" .= directory,"restic" .= worker]
    let checks=
          [("bootstrap-accounting",externalAta==Nothing && either (const True) (const False) corruptAta
            && localAta==localReplay && localAta==Just(object ["operation" .= ("initialize-operating"::T.Text)
              ,"deposit" .= ("sol-operating:"<>C.solanaOperatingHistoryStart config),"transaction" .= signature,"reason" .= ("owned SOL"::T.Text)]))
          ,("history-preflight",historyPreflight),("backup-handoff",handoffChecked)
          ,("backup-timeout",backupChecked),("native-seed",nativeChecked)
          ,("worker-signer-identity",C.fingerprint config==C.fingerprint other && C.nativeCookie config/=C.nativeCookie other)
          ,("payout-policy-default",C.payoutPolicy config==W.defaultPayoutPolicy && C.payoutPolicy other==W.defaultPayoutPolicy)
          ,("owner-policy-legacy-disabled",C.ownerFeeRecipients config==Nothing && C.ownerFeeRecipients other==Nothing)
          ,("gas-offer-interactive-disabled",C.gasTopUpOffer config==Nothing && C.gasTopUpOffer other==Nothing)
          ,("private-files",sort entries==["interface.json","setup.json","signer.json","sources.json","worker.json"] && all(==0o600)modes)
          ,("import-sources",sources==M.fromList [("solana.keypair.json",key),("native-worker.auth",worker),("native-signer.auth",signer)]
            && originalKey==L.toStrict(encode $ B.unpack(seed<>public)) && originalWorker=="worker:password" && originalSigner=="signer:password")
          ,("source-selection",sourceCode==ExitSuccess && sourceSetup==expectedSetup && not ("PUBLIC key file" `isInfixOf` sourceOutput) && not ("signed installer directory" `isInfixOf` sourceOutput))
          ,("unlock-validation",C.nativeUnlockFile sourceWorker==Nothing && C.nativeUnlockFile sourceSigner==Just unlock
            && "invalid_native_unlock_file" `isInfixOf` sourceOutput && not (" exact unlock secret " `isInfixOf` sourceOutput))
          ,("restore-identity",restoredCode==ExitSuccess && C.custodyOwner restoredConfig==base58(B.drop 32 expectedKey)
            && recovered==L.toStrict(encode $ B.unpack expectedKey) && recoveredPhrase==B.pack(map (fromIntegral . fromEnum) (phrase<>"\n"))
            && not (phrase `isInfixOf` restoredOutput) && all (==0o600) secretModes)
          ,("configure-no-generation",pipeCode/=ExitSuccess && "wallet_generation_only_during_start" `isInfixOf` (pipeStdout<>pipeOutput))
          ,("restore-interruption",interruptedCode/=ExitSuccess && not settingsRemain && retainedKey==recovered)
          ,("overwrite-cancellation",before==after && again/=ExitSuccess && cancelled/=ExitSuccess && not partial)]
    mapM_ (\(name,ok)->unless ok $ putStrLn $ "FAIL configure contract: "<>name) checks
    pure(all snd checks)
 where
  temporary=do
    -- Setup publications require protected, non-symlink ancestors. System temp
    -- paths can be world-writable (or /var symlink aliases on macOS).
    parent<-getCurrentDirectory
    (path,h)<-openTempFile parent "ecx-configure-test"
    hClose h;removeFile path;createDirectory path;setFileMode path 0o700
    pure path

-- Use a secure workspace parent: the publisher deliberately refuses /tmp's
-- world-writable ancestor. No installed paths, services or credentials are used.
reconfigureFilesContract :: IO ()
reconfigureFilesContract=bracket temporary removeDirectoryRecursive $ \directory->do
  uid<-getEffectiveUserID;gid<-getEffectiveGroupID
  let first=directory</>"first";second=directory</>"second";journal=directory</>"journal"
      large=B.replicate 32768 120
      firstFile=RF.ConfigFile first (Just "old") "new" 0o640 uid gid
      secondFile=RF.ConfigFile second Nothing large 0o600 uid gid
      files=[firstFile,secondFile]
      refuse action=do
        result<-try(action >> pure ()) :: IO (Either SomeException ())
        require (either (const True) (const False) result) "configuration_file_refusal_failed"
  savePrivate first "old";setFileMode first 0o640
  RF.stageConfigFiles journal files
  saved<-RF.loadConfigFiles journal
  before<-B.readFile first
  absent<-not <$> doesFileExist second
  require (saved==files && before=="old" && absent) "configuration_file_staging_mutated_target"
  -- Resume an interruption after the first rename, preserving mode and group.
  B.writeFile first "new"
  RF.publishConfigFiles journal files
  RF.publishConfigFiles journal files
  actual<-mapM B.readFile [first,second]
  modes<-mapM (fmap ((.&. 0o7777).fileMode) . getFileStatus) [first,second]
  require (actual==["new",large] && modes==[0o640,0o600]) "configuration_file_publication_failed"
  refuse (RF.publishConfigFiles journal [firstFile,secondFile {RF.configAfter="different"}])
  B.writeFile first "third-party"
  refuse (RF.publishConfigFiles journal files)
  B.writeFile first "new";setFileMode first 0o600
  refuse (RF.publishConfigFiles journal files)
  setFileMode first 0o640
  let alias=directory</>"hardlink"
  createLink first alias
  refuse (RF.publishConfigFiles journal files)
  removeFile alias
  let symbolic=directory</>"symlink"
  createSymbolicLink first symbolic
  refuse (RF.stageConfigFiles (directory</>"symlink-journal")
    [firstFile {RF.configPath=symbolic,RF.configBefore=Just "new"}])
  let snapshot=journal</>"0.old"
  B.writeFile snapshot "tampered"
  refuse (RF.loadConfigFiles journal)
  B.writeFile snapshot "old"
  manifest<-B.readFile(journal</>"manifest.json")
  B.appendFile (journal</>"manifest.json") " "
  refuse (RF.loadConfigFiles journal)
  B.writeFile (journal</>"manifest.json") manifest
  setFileMode directory 0o770
  refuse (RF.publishConfigFiles journal files)
  setFileMode directory 0o700
  retained<-RF.loadConfigFiles journal
  require (retained==files) "configuration_file_archive_changed"
 where
  temporary=do
    parent<-getCurrentDirectory
    (path,handle)<-openTempFile parent ".configuration-file-test"
    hClose handle;removeFile path;createDirectory path;setFileMode path 0o700
    pure path

-- Real configure-file command, published BIP-39 vectors and disposable keys.
-- No RPC, node creation, signing, services or funded wallets are involved.
importContract :: FilePath -> FilePath -> IO Bool
importContract parent executable=do
  let phrase=unwords(replicate 11 "abandon"<>["about"])
      solPhrase="legal winner thank year wave sausage worth useful legal winner thank yellow"
  key<-either (const $ fail "fixture Solana mnemonic") pure (walletKey solPhrase)
  -- Independent PBKDF2/HMAC vector, also covered by walletProperty below.
  require (Hex.convertToBase Hex.Base16 (B.take 32 key)==("6987bdb06aa8a243a3019f41489ffa8e609c953a885a748d1849a8df760aa479"::B.ByteString))
    "solana_import_derivation_vector_mismatch"
  let fields=
        [("serverIp",show ("127.0.0.1"::String)),("domain",show ("bridge.example.invalid"::String))
        ,("websiteDirectory","Nothing"),("cloudflareTunnelToken","Nothing"),("ecxSeedBip39",show phrase),("solSeedBip39",show solPhrase)
        ,("assetMintAddress",show $ T.unpack Bootstrap.canonicalMint)
        ,("feeRateWrapBps","100"),("feeRateUnwrapBps","100")
        ,("payoutThresholdEcx",show ("0.002"::String)),("payoutThresholdWrappedEcx",show ("0.003"::String))
        ,("minimumPayoutIntervalHours","7")
        ,("solGasTopUp",show ("0.005"::String)),("solGasTopUpFeeEcx",show ("0.005"::String))
        ,("ownerEcxXpub",show ("xpub6CUGRUonZSQ4TWtTMmzXdrXDtypWKiKrhko4egpiMZbpiaQL2jkwSB1icqYh2cfDfVxdx4df189oLKnC5fSwqPfgyP3hooxujYzAu3fDVmz"::String))
        ,("ownerSolPubkey",show ("5oNDL3swdJJF1g9DzJiZ4ynHXgszjAEpUkxVYejchzrY"::String))
        ,("externalLinkSolscan",show ("https://solscan.io/token/"<>T.unpack Bootstrap.canonicalMint))
        ,("externalLinkOrca",show ("https://www.orca.so/pools/nNKg814Wq3uTkoG4fM8LzvBQv4Fu2iCgKFmK2YmPQzM"::String))
        ,("solanaRpcUrl",show ("https://primary.example.invalid"::String))
        ,("solanaVerifierRpcUrl",show ("https://verifier.example.invalid"::String))
        ,("backupRepositoryUrl",show ("rest:https://backup.example.invalid/repository"::String))
        ,("backupPassword",show ("test-backup-password-only"::String)),("resticExecutable",show executable)
        ,("updatePublicKey",show ("/root/release-public.pem"::String)),("updateReleaseDirectory",show ("/root/new-release"::String))
        ,("updateSetupDirectory",show ("/var/lib/hot-wallet-server/.ecx-bridge"::String))
        ,("freshCustodyAttestation",show ("NEW_UNUSED_KEYS_WITH_NO_EXISTING_BRIDGE_LEDGER"::String))
        ,("initialFundingOwnership",show ("test owned initial SOL"::String))]
      record values="InstallConfig {"<>concat [separator<>name<>" = "<>value | ((name,value),separator)<-zip values ("":repeat ",")]<>"}"
      replace name value=map (\(k,v)->(k,if k==name then value else v)) fields
      withoutGas=filter (\(name,_)->name `notElem` ["solGasTopUp","solGasTopUpFeeEcx"]) fields
      -- Recompute checksums so malformed versions/metadata/curve points reach
      -- semantic validation rather than failing only at Base58Check.
      xpub=read $ maybe (error "missing test xpub") id (lookup "ownerEcxXpub" fields) :: String
      payload=maybe (error "invalid test xpub") (B.take 78) $
        B58.decodeBase58 B58.bitcoinAlphabet (B8.pack xpub)
      sha value=BA.convert(hash value :: Digest SHA256) :: B.ByteString
      encoded value=T.unpack $ base58 (value<>B.take 4(sha $ sha value))
      badXpubs=["xpub",init xpub<>"1","1"<>xpub
        ,encoded (B.pack [0x04,0x35,0x87,0xcf]<>B.drop 4 payload)
        ,encoded (B.take 4 payload<>B.singleton 0<>B.replicate 8 1<>B.drop 13 payload)
        ,encoded (B.take 45 payload<>B.singleton 4<>B.replicate 32 0)
        ,encoded (B.take 45 payload<>B.singleton 2<>B.replicate 32 255)
        ,encoded (B.take 45 payload<>B.singleton 2<>B.replicate 32 0)]
      receiveAddress="bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4"::String
      addressFields=replace "ownerEcxXpub" (show receiveAddress)
      badAddresses=[init receiveAddress<>"5","tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx"," "<>receiveAddress
        ,"0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"]
      output=parent</>"record-setup"
      conf=parent</>"server.conf"
      invoke path destination=readProcessWithExitCode executable ["configure-file",path,destination] ""
      secretFree out=all (not . (`isInfixOf` out)) [phrase,solPhrase,T.unpack(base58 key),"test-backup-password-only"]
      commented values="-- private configuration\nInstallConfig {- outer {- nested -} comment -}\n  { "<>
        concat [name<>" {- assignment -} = "<>value<>" -- field comment\n"<>separator
          | ((name,value),separator)<-zip values (replicate (length values-1) ","<>[""])]<>"}\n"
      punctuation="fixture , = { } -- {- -} \\\" password"::String
      acceptedRecords=
        [(record(reverse fields),fields)
        ,(record withoutGas,replace "solGasTopUp" (show ("0"::String)))
        ,(record $ filter ((/="solGasTopUpFeeEcx").fst) fields,fields)
        ,(commented(reverse fields),fields)
        ,("(("<>record fields<>"))",fields)
        ,(record $ replace "backupPassword" (show punctuation),replace "backupPassword" (show punctuation))
        ,(record $ replace "backupPassword" "\"fixture\\\n  \\password-12345678\"",replace "backupPassword" (show ("fixturepassword-12345678"::String)))
        ,(record $ replace "websiteDirectory" "(Nothing)",fields)
        ,(record $ replace "initialFundingOwnership" "['f','i','x','t','u','r','e']",replace "initialFundingOwnership" (show ("fixture"::String)))]
  gasTopUpAmountsContract (read $ record fields)
  forM_ (zip [0::Int ..] acceptedRecords) $ \(n,(source,expected))->do
    let path=parent</>("record-syntax-"<>show n<>".conf")
        bytes=B8.pack source
    savePrivate path bytes
    (retained,parsed)<-InstallConfig.readInstallConfig path
    require (retained==bytes && parsed==read(record expected)) "record_normalization_changed_values_or_bytes"
    (code,out,err)<-readProcessWithExitCode executable ["check-install-config",path] ""
    require (code==ExitSuccess && out=="Installation configuration valid; no services changed.\n"
      && null err && secretFree out) "record_validation_command_failed"
  let marker="secretSentinelNeverPrintThis"
      malformed=
        [(record $ filter ((/="solSeedBip39").fst) fields,"missing fields: solSeedBip39")
        ,(record $ fields<>[("domain",show marker)],"duplicate field domain")
        ,(record $ fields<>[(marker,show marker)],"unknown field name")
        ,(record $ replace "cloudflareTunnelToken" (show marker),"cloudflareTunnelToken requires Nothing or Just")
        ,(record $ replace "payoutThresholdEcx" "0.001","payoutThresholdEcx requires a double-quoted string")
        ,(record $ replace "feeRateWrapBps" (show marker),"feeRateWrapBps requires an unquoted whole number")
        ,(record $ replace "feeRateWrapBps" (show $ toInteger(maxBound::Int)+1),"feeRateWrapBps is outside")
        ,(record fields<>marker,"no trailing text")
        ,("("<>record fields,"expected InstallConfig")
        ,(init(record fields),"missing closing delimiter")
        ,(init(record fields)<>",}","trailing comma")
        ,(record $ replace "domain" ("("<>show marker<>"]"),"mismatched delimiter in domain")
        ,("InstallConfig {\n serverIp = \""<>marker,"at line 2")
        ,("{-\n"<>marker,"unclosed {- -} comment")
        ,(record [(name,if name=="serverIp" then show marker<>" domain = \"localhost\"" else value) | (name,value)<-fields],"serverIp requires a double-quoted string")
        ,(record [(if name=="solSeedBip39" then "solKeyB58" else name,value) | (name,value)<-fields],"solKeyB58 is obsolete")]
  forM_ (zip [0::Int ..] malformed) $ \(n,(source,expected))->do
    let path=parent</>("record-invalid-"<>show n<>".conf"); destination=parent</>("record-refused-"<>show n)
    savePrivate path (B8.pack source)
    (code,out,err)<-readProcessWithExitCode executable ["check-install-config",path] ""
    require (code/=ExitSuccess && null out && expected `isInfixOf` err && not(marker `isInfixOf` err) && secretFree err)
      "record_diagnostic_missing_or_exposed_value"
    (importCode,importOut,importErr)<-invoke path destination
    created<-doesPathExist destination
    require (importCode/=ExitSuccess && not created && null importOut && expected `isInfixOf` importErr
      && not(marker `isInfixOf` importErr) && secretFree importErr) "invalid_record_published_or_exposed_values"
  forM_ [replace "serverIp" (show address) | address<-["::1","2001:DB8::1","::ffff:127.0.0.1"]] $ \values->do
    imported<-InstallConfig.validateInstallConfig (read $ record values)
    require (imported==key) "valid_ipv6_configuration_rejected"
  savePrivate conf (B8.pack $ record fields)
  -- Updating operational settings retains custody. Compare derived identities,
  -- including migration from a protected legacy record with the same keypair.
  let legacy values=map (\(name,value)->if name=="solSeedBip39" then ("solKeyB58",show $ T.unpack $ base58 key) else (name,value)) values
      quoted=replace "initialFundingOwnership" (show ("solKeyB58 and solSeedBip39 are quoted fixture text"::String))
      bothChanged=map (\(name,value)->(name,case name of
        "ecxSeedBip39"->show solPhrase
        "solSeedBip39"->show phrase
        _->value)) fields
      acceptedUpdates=
        [(fields,fields,(False,False))
        ,(fields,replace "minimumPayoutIntervalHours" "24",(False,False))
        ,(withoutGas,fields,(False,False))
        ,(fields,replace "solGasTopUp" (show ("0"::String)),(False,False))
        ,(fields,replace "solGasTopUp" (show ("0.01"::String)),(False,False))
        ,(fields,replace "solGasTopUpFeeEcx" (show ("0.01"::String)),(False,False))
        ,(fields,addressFields,(False,False))
        ,(fields,replace "ownerSolPubkey" (show $ T.unpack $ base58 $ B.drop 32 key),(False,False))
        ,(replace "ownerSolPubkey" (show $ T.unpack $ base58 $ B.drop 32 key),fields,(False,False))
        ,(addressFields,fields,(False,False))
        ,(addressFields,replace "ownerEcxXpub" (show ("1BoatSLRHtKNngkdXEeobR76b53LETtpyT"::String)),(False,False))
        ,(legacy fields,fields,(False,False))
        ,(reverse $ legacy fields,fields,(False,False))
        ,(legacy quoted,quoted,(False,False))
        ,(fields,replace "ecxSeedBip39" (show solPhrase),(True,False))
        ,(fields,replace "solSeedBip39" (show phrase),(False,True))
        ,(legacy fields,bothChanged,(True,True))]
  forM_ (zip [0::Int ..] acceptedUpdates) $ \(n,(oldValues,newValues,expected))->do
    let previous=parent</>("update-previous-"<>show n<>".conf")
        candidate=parent</>("update-candidate-"<>show n<>".conf")
        newBytes=B8.pack $ record newValues
        newConfig=read(record newValues)::InstallConfig.InstallConfig
    savePrivate previous (B8.pack $ record oldValues)
    savePrivate candidate newBytes
    (actualBytes,actualConfig,actualKey,changed)<-InstallConfig.readInstallConfigUpdate previous candidate
    expectedKey<-either (const $ fail "update fixture mnemonic") pure (walletKey $ InstallConfig.solSeedBip39 newConfig)
    require (actualBytes==newBytes && actualConfig==newConfig && actualKey==expectedKey && changed==expected)
      "configuration_update_identity_classification_failed"
    operational<-try(InstallConfig.validateOperationalUpdate previous candidate) :: IO (Either BridgeError ())
    require (either (const False) (const True) operational==(expected==(False,False)))
      "operational_update_identity_policy_failed"
  forM_ (zip [0::Int ..]
    [replace "resticExecutable" (show ("/different/restic"::String))
    ,replace "initialFundingOwnership" (show ("changed ownership statement"::String))]) $ \(n,values)->do
      let candidate=parent</>("unsupported-update-"<>show n<>".conf")
      savePrivate candidate (B8.pack $ record values)
      refused<-try(InstallConfig.validateOperationalUpdate conf candidate) :: IO (Either BridgeError ())
      require (either (const True) (const False) refused) "unsupported_operational_update_accepted"
  let oldKey value=map (\(name,contents)->(name,if name=="solKeyB58" then show value else contents)) (legacy fields)
      invalidUpdates=
        [(oldKey "invalid",fields)
        ,(oldKey (T.unpack $ base58 $ B.take 32 key),fields)
        ,(oldKey (T.unpack $ base58 $ B.take 32 key<>B.replicate 32 0),fields)
        ,(legacy (replace "ecxSeedBip39" (show $ unwords $ replicate 12 "abandon")),fields)
        ,(legacy fields<>[("solSeedBip39",show solPhrase)],fields)
        ,(filter ((/="solSeedBip39").fst) quoted,fields)
        ,(fields,legacy fields)
        ,(fields,replace "solSeedBip39" (show ("invalid"::String)))
        ,(fields,replace "assetMintAddress" (show ("different"::String)))
        ,(fields,replace "feeRateWrapBps" "101")
        ,(fields,replace "feeRateUnwrapBps" "101")]
  forM_ (zip [0::Int ..] invalidUpdates) $ \(n,(oldValues,newValues))->do
    let previous=parent</>("invalid-update-previous-"<>show n<>".conf")
        candidate=parent</>("invalid-update-candidate-"<>show n<>".conf")
    savePrivate previous (B8.pack $ record oldValues)
    savePrivate candidate (B8.pack $ record newValues)
    result<-try(InstallConfig.readInstallConfigUpdate previous candidate)
      :: IO (Either BridgeError (B.ByteString,InstallConfig.InstallConfig,B.ByteString,(Bool,Bool)))
    require (either (const True) (const False) result) "invalid_configuration_update_accepted"
  (updateCode,updateOut,updateErr)<-readProcessWithExitCode executable ["update-settings",conf] ""
  require (updateCode==ExitSuccess && secretFree(updateOut<>updateErr)
    && (eitherDecodeStrict' (B8.pack updateOut) :: Either String Value)==Right
      (object ["publicKey" .= ("/root/release-public.pem"::String),"release" .= ("/root/new-release"::String)
        ,"setup" .= ("/var/lib/hot-wallet-server/.ecx-bridge"::String)])) "update_settings_projection_failed"
  forM_ ["relative","/root/bad\npath"] $ \bad->do
    let invalid=parent</>"invalid-update.conf"
    savePrivate invalid (B8.pack $ record $ replace "updateReleaseDirectory" (show bad))
    (code,stdout,stderr)<-readProcessWithExitCode executable ["update-settings",invalid] ""
    require (code/=ExitSuccess && secretFree(stdout<>stderr)) "invalid_update_path_accepted"
    removeFile invalid
  (first,out,err)<-invoke conf output
  require (first==ExitSuccess) "import_contract_first_install_failed"
  let backupFields=map (\(name,value)->(name,case name of
        "backupRepositoryUrl"->show ("https://corrected.example.invalid/new-repository"::String)
        "backupPassword"->show ("corrected-fixture-password"::String)
        _->value)) fields
  backupSetupContract parent output (B8.pack $ record fields) (B8.pack $ record backupFields) (read $ record backupFields)
  let privateFiles=[output</>name | name<-["install.conf","sources.json","bootstrap.json","setup.json","interface.json","hosting.json","backup.repository","backup.password"]]
        <>[output<>"-keys/"<>name | name<-["solana.keypair.json","ecx-recovery.txt","native-unlock"]]
  before<-mapM B.readFile privateFiles
  modes<-mapM (fmap ((.&. 0o777).fileMode) . getFileStatus) privateFiles
  (second,reout,reerr)<-invoke conf output
  after<-mapM B.readFile privateFiles
  config<-Bootstrap.setupConfig output
  require (units (C.maxWithdrawal config)==1000000000000) "owner_withdrawal_cap_not_10000_ecx"
  require (fmap (\offer->(units $ gasLamports offer,units $ gasEcxFee offer)) (C.gasTopUpOffer config)==Just(5000000,500000))
    "gas_top_up_offer_not_retained"
  let legacyConf=parent</>"legacy-gas.conf";legacyOutput=parent</>"legacy-gas-setup"
  savePrivate legacyConf (B8.pack $ record withoutGas)
  (legacyCode,_,_)<-invoke legacyConf legacyOutput
  require (legacyCode==ExitSuccess) "legacy_gas_configuration_failed"
  legacyConfig<-Bootstrap.setupConfig legacyOutput
  require (C.gasTopUpOffer legacyConfig==Nothing) "legacy_gas_configuration_enabled_offer"
  let recipients=C.OwnerFeeRecipients (T.pack xpub) "5oNDL3swdJJF1g9DzJiZ4ynHXgszjAEpUkxVYejchzrY"
  require (C.ownerFeeRecipients config==Just recipients
    && (eitherDecodeStrict' (L.toStrict $ encode config) :: Either String C.Config)==Right config) "owner_policy_not_retained"
  let addressConf=parent</>"address.conf"; addressOutput=parent</>"address-setup"
  savePrivate addressConf (B8.pack $ record addressFields)
  (addressCode,addressOut,addressErr)<-invoke addressConf addressOutput
  require (addressCode==ExitSuccess && secretFree(addressOut<>addressErr)) "owner_address_configuration_failed"
  addressConfig<-Bootstrap.setupConfig addressOutput
  C.validateSetupConfig addressConfig
  -- Each disposable installation has its own credential paths.
  let normalized=addressConfig {C.nativeCookie=C.nativeCookie config,C.nativeUnlockFile=C.nativeUnlockFile config}
  require (normalized==config {C.ownerFeeRecipients=Just recipients {C.nativeOwnerXpub=T.pack receiveAddress}}
    && C.fingerprint addressConfig==C.fingerprint config) "owner_address_changed_custody_or_configuration"
  let selfConf=parent</>"self-owner.conf"; selfOutput=parent</>"self-owner-setup"
  savePrivate selfConf (B8.pack $ record $ replace "ownerSolPubkey" $ show $ T.unpack $ C.custodyOwner config)
  (selfCode,selfOut,selfErr)<-invoke selfConf selfOutput
  require (selfCode==ExitSuccess && secretFree(selfOut<>selfErr)) "self_owner_configuration_failed"
  selfConfig<-Bootstrap.setupConfig selfOutput
  C.validateSetupConfig selfConfig
  let selfNormalized=selfConfig {C.nativeCookie=C.nativeCookie config,C.nativeUnlockFile=C.nativeUnlockFile config}
  require (selfNormalized==config {C.ownerFeeRecipients=Just recipients {C.solanaOwner=C.custodyOwner config}}
    && C.fingerprint selfConfig==C.fingerprint config) "self_owner_changed_custody_or_configuration"
  forM_ (map (\bad->recipients {C.nativeOwnerXpub=T.pack bad}) (badXpubs<>badAddresses)
    <>[recipients {C.solanaOwner="invalid"}]) $ \bad->do
      result<-try(C.validateSetupConfig config {C.ownerFeeRecipients=Just bad}) :: IO (Either BridgeError ())
      require (either (const True) (const False) result) "invalid_runtime_owner_accepted"
  forM_ ([config {C.ownerFeeRecipients=Just recipients {C.solanaOwner=destination}}
      | destination<-[C.custodyAta config,C.mint config]]
    <>[config {C.maxWithdrawal=either (error . T.unpack) id (amount 1)}]) $ \bad->do
      result<-try(C.validateSetupConfig bad) :: IO (Either BridgeError ())
      require (either (const True) (const False) result) "unsafe_automatic_payout_policy_accepted"
  links<-C.loadInterface config (Just $ output</>"interface.json")
  require (W.publicOrigin links==Nothing) "local_setup_has_public_origin"
  noToken<-not <$> doesFileExist(output</>"tunnel.token")
  require noToken "local_setup_has_tunnel_credential"
  let tunnelOutput=parent</>"tunnel-setup"; tunnelConf=parent</>"tunnel.conf"
      tunnelToken=replicate 64 't'
  savePrivate tunnelConf (B8.pack $ record $ replace "cloudflareTunnelToken" ("Just "<>show tunnelToken))
  (tunnelCode,tunnelOut,tunnelErr)<-invoke tunnelConf tunnelOutput
  require (tunnelCode==ExitSuccess && not(tunnelToken `isInfixOf` (tunnelOut<>tunnelErr))) "tunnel_configuration_failed_or_leaked"
  tunnelLinks<-C.loadInterface config (Just $ tunnelOutput</>"interface.json")
  require (W.publicOrigin tunnelLinks==Just "https://bridge.example.invalid") "tunnel_origin_not_retained"
  token<-readPrivate(tunnelOutput</>"tunnel.token")
  hosting<-readPrivate(tunnelOutput</>"hosting.json") >>= either fail pure . eitherDecodeStrict'
  require (token==B8.pack tunnelToken && hosting==object
    ["domain" .= ("bridge.example.invalid"::String),"serverIp" .= ("127.0.0.1"::String),"tunnel" .= True]) "tunnel_material_changed"
  (tunnelReplay,_,_)<-invoke tunnelConf tunnelOutput
  require (tunnelReplay==ExitSuccess) "tunnel_replay_failed"
  importedKey<-B.readFile(output<>"-keys/solana.keypair.json")
  importedPhrase<-B.readFile(output<>"-keys/ecx-recovery.txt")
  generated<-mapM doesDirectoryExist [output<>"-solana-wallet",output<>"-ecx-wallet"]
  invalid<-forM (zip [0::Int ..]
    (map (replace "serverIp" . show) ([".","1.2.3","256.1.2.3","1.2.3.4.5","2001::db8::1","[::1]","::1%lo0"," 127.0.0.1","\f127.0.0.1","(127.0.0.1)","2130706433","0x7f000001"]::[String])
    <>map (replace "domain" . show) ([".",".example.org","example..org","example.org.","-bridge.example.org","bridge-.example.org",replicate 64 'a'<>".org"]::[String])
    <>map (replace "cloudflareTunnelToken" . ("Just "<>) . show)
      [replicate 31 't',replicate 4097 't',replicate 32 't'<>"\n",replicate 32 't'<>"\f",replicate 32 't'<>"\x100"]
    <>map (replace "ownerSolPubkey" . show . T.unpack) [C.custodyAta config,C.mint config]
    <>map (replace "ownerEcxXpub" . show) (badXpubs<>badAddresses) <>
    map (replace "solSeedBip39" . show)
      ["",unwords(replicate 12 "abandon"),unwords(take 11 $ words solPhrase),solPhrase<>" yellow"
      ,solPhrase<>" "<>solPhrase,"notaword "<>unwords(drop 1 $ words solPhrase)
      ,"Legal "<>unwords(drop 1 $ words solPhrase)," "<>solPhrase,solPhrase<>" ",solPhrase<>"\n"
      ,"legal  "<>unwords(drop 1 $ words solPhrase),T.unpack(base58 key)] <>
    [replace "ecxSeedBip39" (show (""::String))
    ,replace "solGasTopUp" (show ("0.010000001"::String))
    ,replace "ecxSeedBip39" (show $ unwords $ replicate 12 "abandon")
    ,filter ((/="solSeedBip39").fst) fields
    ,map (\(name,value)->if name=="solSeedBip39" then ("solKeyB58",show $ T.unpack $ base58 key) else (name,value)) fields
    ,replace "backupRepositoryUrl" (show ("rest:https://"::String))
    ,replace "backupRepositoryUrl" (show ("rest:http://backup.example.invalid/repository"::String))
    ,replace "backupRepositoryUrl" (show ("rest:https://backup.example.invalid/repository\nother"::String))
    ,replace "backupRepositoryUrl" (show ("rest:https://backup.example.invalid/repository#fragment"::String))
    ,replace "backupRepositoryUrl" (show ("rest:https://backup.example.invalid:invalid/repository"::String))
    ,replace "backupRepositoryUrl" (show ("rest:https://backup.example.invalid/\x100"::String))
    ,replace "externalLinkOrca" (show ("https://www.orca.so/pools/invalid"::String))
    ,replace "externalLinkOrca" (show ("https://untrusted.example.invalid/pools/nNKg814Wq3uTkoG4fM8LzvBQv4Fu2iCgKFmK2YmPQzM"::String))
    ,replace "externalLinkSolscan" (show ("https://solscan.io/token/wrong-mint"::String))
    ,replace "externalLinkSolscan" (show ("https://untrusted.example.invalid/token/"<>T.unpack Bootstrap.canonicalMint))
    ,replace "externalLinkSolscan" (show ("https://user:password@solscan.io/token/"<>T.unpack Bootstrap.canonicalMint))
    ,replace "websiteDirectory" ("Just "<>show ("relative/site"::String))
    ,replace "websiteDirectory" ("Just "<>show (parent</>"missing-site"))])) $ \(n,values)->do
      let file=parent</>("invalid-"<>show n<>".conf"); dest=parent</>("invalid-"<>show n)
      savePrivate file (B8.pack $ record values)
      (code,stdout,stderr)<-invoke file dest
      exists<-doesDirectoryExist dest
      let entered=maybe "" read (lookup "solSeedBip39" values) :: String
      pure(code/=ExitSuccess && not exists && secretFree(stdout<>stderr)
        && (null entered || not(entered `isInfixOf` (stdout<>stderr))))
  let changed=parent</>"changed.conf"
  savePrivate changed (B8.pack $ record $ replace "minimumPayoutIntervalHours" "24")
  (changedCode,_,_)<-invoke changed output
  unchanged<-mapM B.readFile privateFiles
  let mixed=parent</>"mixed-setup"
  createDirectory mixed;setFileMode mixed 0o700
  savePrivate (mixed</>"configuring") "ecx-bridge-configuration-v1\n"
  (mixedCode,_,_)<-invoke conf mixed
  savePrivate (mixed</>"install.conf") (B8.pack $ record fields)
  harness<-getExecutablePath
  (resumeCode,_,resumeError)<-readProcessWithExitCode harness ["--start-setup",mixed] ""
  mixedKeys<-mapM doesDirectoryExist [mixed<>"-keys",mixed<>"-solana-wallet",mixed<>"-ecx-wallet"]
  let site=parent</>"custom-site"; siteOutput=parent</>"custom-setup"; siteConf=parent</>"custom.conf"
      siteFiles=[("index.html","custom-html"),("style.css","custom-css"),("dist/wallet.js","custom-js")]
  createDirectory site;createDirectory(site</>"dist")
  mapM_ (\(name,body)->B.writeFile(site</>name) body) siteFiles
  savePrivate siteConf (B8.pack $ record $ replace "websiteDirectory" ("Just "<>show site))
  (siteCode,_,_)<-invoke siteConf siteOutput
  siteSetup<-B.readFile(siteOutput</>"setup.json") >>= either fail pure . eitherDecodeStrict'
  actualSite<-fieldValue "website" siteSetup :: IO Value
  (siteReplay,_,_)<-invoke siteConf siteOutput
  B.writeFile (site</>"style.css") "changed-css"
  (siteChanged,_,_)<-invoke siteConf siteOutput
  retainedSite<-B.readFile(siteOutput</>"setup.json") >>= either fail pure . eitherDecodeStrict'
  let expectedSite=object ["directory" .= site,"hashes" .= object [Key.fromString name .= digest body | (name,body)<-siteFiles]]
  pure(siteCode==ExitSuccess && siteReplay==ExitSuccess && actualSite==expectedSite
    && siteChanged/=ExitSuccess && retainedSite==siteSetup
    && second==ExitSuccess && before==after && before==unchanged && all(==0o600)modes
    && secretFree(out<>err<>reout<>reerr) && C.custodyOwner config==base58(B.drop 32 key)
    && units(W.nativePayoutThreshold $ C.payoutPolicy config)==200000
    && units(W.wrappedPayoutThreshold $ C.payoutPolicy config)==300000
    && W.payoutIntervalSeconds(C.payoutPolicy config)==25200
    && W.orcaUrl links==Just "https://www.orca.so/pools/nNKg814Wq3uTkoG4fM8LzvBQv4Fu2iCgKFmK2YmPQzM"
    && W.tokenExplorerUrl links==Just ("https://solscan.io/token/"<>Bootstrap.canonicalMint)
    && importedKey==L.toStrict(encode $ B.unpack key) && importedPhrase==B8.pack(phrase<>"\n")
    && not(or generated) && and invalid && changedCode/=ExitSuccess && mixedCode/=ExitSuccess
    && resumeCode/=ExitSuccess && "record_setup_incomplete_rerun_install" `isInfixOf` resumeError && not(or mixedKeys))

-- The static offer preserves both configured amounts at their exact precision.
gasTopUpAmountsContract :: InstallConfig.InstallConfig -> IO ()
gasTopUpAmountsContract config=do
  let offered sol charge=config {InstallConfig.solGasTopUp=sol,InstallConfig.solGasTopUpFeeEcx=charge}
      observed value=fmap (fmap (\offer->(units $ gasLamports offer,units $ gasEcxFee offer)))
        (InstallConfig.installGasTopUp value)
      accepted=
        [("0","0.005",Nothing)
        ,("0.000000000","0.005",Nothing)
        ,("0.0005","0.0005",Just(500000,50000))
        ,("0.005","0.005",Just(5000000,500000))
        ,("0.005000000","0.00500000",Just(5000000,500000))
        ,("0.000000001","0.00000001",Just(1,1))
        ,("0.01","0.005",Just(10000000,500000))
        ,("0.01","92233720368.54775807",Just(10000000,9223372036854775807))]
      refused=[offered sol "0.005" | sol<-
          ["0.010000001","1","-0.0001","0.0000000001",".0001","0.","00.0001"," 0.0001","1e-4",""]]
        <>[offered "0.005" charge | charge<-["0","-0.005","0.005000001","92233720368.54775808","1e-3",""]]
  forM_ accepted $ \(sol,charge,expected)->
    require (observed(offered sol charge)==Right expected) "gas_top_up_exact_amounts_failed"
  forM_ refused $ \value->
    require (either (const True) (const False) $ InstallConfig.installGasTopUp value) "gas_top_up_invalid_amount_accepted"

-- Fixed credential plans before/after installation, plus interrupted private
-- publication. Real restic access is checked separately; no live custody here.
backupSetupContract :: FilePath -> FilePath -> B.ByteString -> B.ByteString -> InstallConfig.InstallConfig -> IO ()
backupSetupContract parent imported previous candidate settings=do
  let state="/var/lib/hot-wallet-server"; setup=state</>".ecx-bridge"
      signer="/etc/ecx-bridge/signer"
      repository="rest:https://corrected.example.invalid/new-repository"
      password="corrected-fixture-password"
  credentials<-mapM (B.readFile . (imported</>)) ["backup.repository","backup.password"]
  let sources=object ["backup.repository" .= (setup</>"backup.repository"),"backup.password" .= (setup</>"backup.password")]
      runtime=object ["restic" .= ("/opt/ecx-bridge/current/bin/restic"::String)
        ,"repositoryFile" .= (signer</>"backup.repository"),"passwordFile" .= (signer</>"backup.password")]
      table=M.fromList $ [(state</>"server.conf",previous),(setup</>"install.conf",previous)
        ,(setup</>"sources.json",L.toStrict $ encode sources),(signer</>"backup.json",L.toStrict $ encode runtime)]
        <>concat [zip (map (directory</>) ["backup.repository","backup.password"]) credentials | directory<-[setup,signer]]
      view values path=pure $ M.lookup path values
      plan values installed=Reconfigure.backupCredentialChanges (view values) installed settings
      refuse reason action=do
        result<-try action :: IO (Either BridgeError [(FilePath,B.ByteString)])
        require (case result of Left(BridgeError actual)->actual==reason; _->False) "backup_update_refusal_contract_failed"
      expected directories=concat [[(directory</>"backup.repository",repository),(directory</>"backup.password",password)] | directory<-directories]
  fresh<-plan table False
  installed<-plan table True
  require (fresh==expected [setup] && installed==expected [setup,signer]) "backup_update_plan_contract_failed"
  let previousPath=parent</>"backup-previous.conf";candidatePath=parent</>"backup-candidate.conf"
  savePrivate previousPath previous
  savePrivate candidatePath candidate
  InstallConfig.validateOperationalUpdate previousPath candidatePath
  -- The backup branch also accepts other supported settings, rather than
  -- accidentally treating a mixed edit as an ordinary credential-free update.
  combined<-Reconfigure.backupCredentialChanges (view table) True settings {InstallConfig.solGasTopUp="0"}
  require (combined==installed) "backup_update_combined_settings_failed"
  forM_ [setup,signer] $ \directory->forM_ ["backup.repository","backup.password"] $ \name->
    refuse "backup_setup_credentials_changed" (plan (M.insert (directory</>name) "unexpected" table) True)
  refuse "backup_update_source_paths_changed" (plan (M.insert (setup</>"sources.json") "{}" table) False)
  refuse "backup_update_runtime_paths_changed" (plan (M.insert (signer</>"backup.json") "{}" table) True)
  forM_ ["/var/lib/ecx-bridge-install","/etc/ecx-bridge","/var/lib/ecx-bridge-setup/installed-directory.json"] $ \marker->do
    result<-try(Reconfigure.validateBackupPhase (pure . (==marker)) False) :: IO (Either BridgeError ())
    require (case result of Left(BridgeError "finish_partial_installation_before_changing_backup")->True; _->False)
      "backup_partial_installer_accepted"
    Reconfigure.validateBackupPhase (pure . (==marker)) True
  -- Initialized wallets and a saved ATA attempt do not require a fresh wallet.
  Reconfigure.validateBackupPhase (pure . (`elem` map (setup</>) ["node-config.before","ata-creation.json","bootstrap-complete.json"])) False
  uid<-getEffectiveUserID;gid<-getEffectiveGroupID
  let changes=[(state</>"server.conf",candidate),(setup</>"install.conf",candidate)]<>installed
      files=[RF.ConfigFile path (M.lookup path table) bytes 0o600 uid gid | (path,bytes)<-changes]
  forM_ [0..length files] $ \cut->do
    let directory=parent</>("backup-update-"<>show cut);journal=directory</>"journal"
        local=[file {RF.configPath=directory</>show n} | (n,file)<-zip [0::Int ..] files]
    createDirectory directory;setFileMode directory 0o700
    forM_ local $ \file->mapM_ (savePrivate $ RF.configPath file) (RF.configBefore file)
    RF.stageConfigFiles journal local
    forM_ (take cut local) $ \file->B.writeFile (RF.configPath file) (RF.configAfter file)
    saved<-RF.loadConfigFiles journal
    RF.publishConfigFiles journal saved
    RF.publishConfigFiles journal saved
    actual<-mapM (B.readFile . RF.configPath) local
    modes<-mapM (fmap ((.&. 0o777).fileMode) . getFileStatus . RF.configPath) local
    require (actual==map RF.configAfter local && all(==0o600)modes && saved==local) "backup_update_replay_contract_failed"
    -- Every old credential is still present in the private journal after replay.
    archived<-mapM (B.readFile . (journal</>) . (<>".old") . show) [0..length files-1]
    require (map Just archived==map RF.configBefore local) "backup_update_lost_old_credentials"
    denied<-try(RF.publishConfigFiles journal (case saved of f:fs->f {RF.configAfter="changed-input"}:fs; _->[])) :: IO (Either BridgeError ())
    require (either (const True) (const False) denied) "backup_update_changed_replay_accepted"

-- Exercise the updater's shared access preflight with real encrypted restic
-- repositories and distinct passwords. No live server or wallet is involved.
backupAccessContract :: FilePath -> IO ()
backupAccessContract parent=do
  executable<-findExecutable "restic" >>= maybe (fail "restic required for backup update contract") pure
  let root=parent</>"backup-access"
  mapM_ (\path->createDirectory path >> setFileMode path 0o700) [root,root</>"share"]
  checksum<-withBinaryFile executable ReadMode hashHandle
  savePrivate (root</>"share/toolchains.json") $ L.toStrict $ encode $ object
    ["restic-reviewed" .= Object(KM.singleton(Key.fromString arch)(String checksum))]
  let spec=object ["restic" .= executable,"sourceRoot" .= root,"method" .= ("bundle"::String)]
      repository=root</>"repository"; password=root</>"password"
      old=root</>"old"; target=root</>"target"
  savePrivate repository (B8.pack old)
  savePrivate password "old-fixture-password"
  Bootstrap.checkBackupAccess spec repository password
  before<-B.readFile(old</>"config")
  B.writeFile repository (B8.pack target)
  B.writeFile password "new-fixture-password"
  Bootstrap.checkBackupAccess spec repository password
  Bootstrap.checkBackupAccess spec repository password
  targetBefore<-B.readFile(target</>"config")
  B.writeFile password "incorrect-fixture-password"
  refused<-try(Bootstrap.checkBackupAccess spec repository password) :: IO (Either BridgeError ())
  require (case refused of Left(BridgeError "backup_initialization_failed_use_new_repository_or_advanced_setup")->True; _->False)
    "backup_update_wrong_password_accepted"
  oldAfter<-B.readFile(old</>"config")
  targetAfter<-B.readFile(target</>"config")
  require (before==oldAfter && targetBefore==targetAfter) "backup_update_preflight_replaced_repository"

-- An unavailable backup must not stall setup or leave its subprocess running.
-- This executable is a process fixture, not a simulated chain or accepted backup.
backupTimeoutContract :: FilePath -> IO Bool
backupTimeoutContract parent=do
  let root=parent</>"backup-timeout"; executable=root</>"restic"
      pidFile=root</>"pid"; phrase=root</>"recovery"
  mapM_ (\path->createDirectory path >> setFileMode path 0o700) [root,root</>"share"]
  savePrivate executable (B8.pack $ "#!/bin/sh\necho $$ > '"<>pidFile<>"'\ntrap '' TERM\nexec sleep 600\n")
  setFileMode executable 0o700
  digest<-withBinaryFile executable ReadMode hashHandle
  let record name value=savePrivate(root</>name)(L.toStrict $ encode value)
  record "bootstrap.json" (object [])
  record "setup.json" (object ["restic" .= executable,"sourceRoot" .= root,"method" .= ("bundle"::String)])
  record "sources.json" (object ["backup.repository" .= (root</>"repository"),"backup.password" .= (root</>"password")])
  record "share/toolchains.json" (object ["restic-reviewed" .= Object(KM.singleton(Key.fromString arch)(String digest))])
  savePrivate phrase "preserved-recovery-fixture"
  result<-try (Bootstrap.initializeBackup root) :: IO (Either BridgeError ())
  pid<-read . B8.unpack <$> B.readFile pidFile
  alive<-try (signalProcess nullSignal pid) :: IO (Either IOError ())
  retained<-B.readFile phrase
  pure (case (result,alive) of
    (Left(BridgeError "backup_setup_timeout"),Left _)->retained=="preserved-recovery-fixture"
    _->False)

-- Published BIP-39 entropy/phrase vectors; SLIP-0010 Solana seeds independently
-- cross-checked with Python hashlib/hmac (empty passphrase, m/44'/501'/0'/0').
walletProperty :: Property
walletProperty=forAll (vectorOf 16 arbitrary) $ \(entropy::[Word8])->
  conjoin [case mnemonic (B.pack entropy) >>= walletKey of
             Right key->property (B.length key==64)
             Left _->property False
          ,let randomBytes=B.pack (entropy<>entropy)
               mixed=mixWalletEntropy "ecx" randomBytes "user text"
           in conjoin [mixWalletEntropy "ecx" randomBytes ""===Right(B.pack entropy)
              ,property (mixed/=mixWalletEntropy "solana" randomBytes "user text")
              ,property (mixed/=mixWalletEntropy "ecx" (B.map (+1) randomBytes) "user text")
              ,property (case mixed >>= mnemonic >>= walletKey of Right key->B.length key==64; _->False)
              ,mixWalletEntropy "ecx" (B.pack entropy) "user text"===Left "invalid_wallet_entropy"
              ,mixWalletEntropy "unknown" randomBytes ""===Left "invalid_wallet_entropy"
              ,fmap (Hex.convertToBase Hex.Base16) (mixWalletEntropy "ecx" (B.pack [0..31]) "user text")===Right ("036bc3ecde7438a76a14bda8ca31c72f" :: B.ByteString)]
          ,ioProperty (nativeScalarContract entropy)
          ,conjoin [counterexample "BIP39/SLIP10 known vector mismatch" $
             mnemonic (B.replicate 16 byte)==Right phrase &&
             fmap (Hex.convertToBase Hex.Base16 . B.take 32) (walletKey phrase)==Right expected
            | (byte,phrase,expected)<-vectors]
          ,ioProperty $ do
             actual<-nativeDescriptors False (unwords $ replicate 11 "abandon"<>["about"])
             pure (actual==Right
              ["wpkh([73c5da0a/84h/0h/0h]xprv9ybY78BftS5UGANki6oSifuQEjkpyAC8ZmBvBNTshQnCBcxnefjHS7buPMkkqhcRzmoGZ5bokx7GuyDAiktd5HemohAU4wV1ZPMDRmLpBMm/0/*)","wpkh([73c5da0a/84h/0h/0h]xprv9ybY78BftS5UGANki6oSifuQEjkpyAC8ZmBvBNTshQnCBcxnefjHS7buPMkkqhcRzmoGZ5bokx7GuyDAiktd5HemohAU4wV1ZPMDRmLpBMm/1/*)"])
          ,property (case walletKey (unwords $ replicate 12 "abandon") of Left _->True; _->False)
          ,property (case mnemonic (B.replicate 15 0) of Left _->True; _->False)]
 where
  vectors :: [(Word8,String,B.ByteString)]
  vectors=
    [(0,unwords (replicate 11 "abandon"<>["about"]),"37df573b3ac4ad5b522e064e25b63ea16bcbe79d449e81a0268d1047948bb445")
    ,(127,"legal winner thank year wave sausage worth useful legal winner thank yellow","6987bdb06aa8a243a3019f41489ffa8e609c953a885a748d1849a8df760aa479")
    ,(128,"letter advice cage absurd amount doctor acoustic avoid letter advice cage above","8ab69a9cd074a86f71fea02a807dac8cc5d498f292844417640946f497117746")
    ,(255,unwords (replicate 11 "zoo"<>["wrong"]),"0b69a88e057a6ff3299f4adac3b04b0b24df114b3f3c21c5cefe0b89664b3bcf")]

-- Integer arithmetic is an independent TEST oracle, never production key math.
nativeScalarContract :: [Word8] -> IO Bool
nativeScalarContract entropy=do
  let order=0xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141 :: Integer
      bytes :: Integer -> B.ByteString
      bytes value=B.pack [fromIntegral (value `shiftR` offset) | offset<-[248,240..0]]
      randomScalar=1+B.foldl' (\n b->256*n+fromIntegral b) 0 (B.pack entropy)
      generator="0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798" :: B.ByteString
      cases=[(1,0,Just 1),(order-1,0,Just (order-1)),(0,1,Nothing),(order,0,Nothing)
            ,(1,order,Nothing),(1,order-1,Nothing),(order-1,2,Just 1)
            ,(randomScalar,order-randomScalar+1,Just 1)]
  results<-forM cases $ \(parent,tweak,expected)->do
    result<-deriveChild (bytes parent) (bytes tweak)
    pure $ fmap fst result==fmap bytes expected && case result of
      Just (_,public)->B.length public==33 && (parent/=1 || Hex.convertToBase Hex.Base16 public==generator)
      Nothing->True
  short<-deriveChild (B.replicate 31 0) (bytes 0)
  long<-deriveChild (bytes 1) (B.replicate 33 0)
  pure (and results && short==Nothing && long==Nothing)

-- Closed native setup protocol: real-node descriptor compatibility is checked
-- separately; these fixtures exercise interruption/refusal without chain effects.
nativeSeedContract :: FilePath -> IO Bool
nativeSeedContract directory=do
  let phrase=unwords (replicate 11 "abandon"<>["about"])
      seedFile=directory</>"native-seed.txt"
      settings=N.NativeSettings L2LSignetDevnet "http://127.0.0.1:29432" (directory</>"worker.auth") "seed-test"
        16000 "00000047dcc9d64b767687d6a5e610c411dd85db5460e824c0f7284f5514bc47"
      public=["public-receive#checksum","public-change#checksum"]::[T.Text]
  private<-nativeDescriptors True phrase >>= either (const $ fail "fixture native mnemonic") pure
  savePrivate seedFile (B.pack $ map (fromIntegral . fromEnum) phrase)
  exists<-newIORef False;imports<-newIORef (0::Int);creates<-newIORef (0::Int)
  broken<-newIORef False;failImport<-newIORef False;restoring<-newIORef False
  starting<-newIORef (2::Int)
  let call _ method args=do
        unless (not $ phrase `isInfixOf` show (encode args)) (fail "phrase leaked into RPC")
        case (method,args) of
          ("getblockchaininfo",[])->do
            remaining<-readIORef starting
            if remaining>0 then do
              writeIORef starting (remaining-1)
              throwIO(BridgeError $ if remaining==2 then "rpc_transport_unknown_outcome" else "rpc_error_-28")
             else pure $ object ["chain" .= ("signet"::T.Text),"initialblockdownload" .= False,"blocks" .= (17000::Int),"pruned" .= False,"signet_challenge" .= N.signetChallenge]
          ("getblockhash",_)->pure $ String $ N.nativeCheckpointHash settings
          ("getconnectioncount",[])->pure $ Number 1
          ("getdescriptorinfo",[String descriptor])->case lookup descriptor (zip private public) of
            Just pub->pure $ object ["descriptor" .= pub,"checksum" .= ("checksum"::T.Text)]
            Nothing->fail "unexpected descriptor"
          ("deriveaddresses",_)->pure $ toJSON (["fixture-funding-address"]::[T.Text])
          ("listwalletdir",[])->do
            present<-readIORef exists
            pure $ object ["wallets" .= [object ["name" .= N.nativeWallet settings] | present]]
          ("createwallet",[String name,Bool False,Bool True,String "",Bool False,Bool True,Bool True,Bool False])->do
            modifyIORef' creates (+1);writeIORef exists True
            pure $ object ["name" .= name]
          ("importdescriptors",[requests])->do
            recovering<-readIORef restoring
            let expected=toJSON [object ["desc" .= (descriptor<>"#checksum"),"active" .= True,"internal" .= internal
                    ,"range" .= ([0,999]::[Int]),"next_index" .= (0::Int),"timestamp" .= (if recovering then Number 0 else String "now")]
                    | (descriptor,internal)<-zip private [False,True]]
            unless (requests==expected) (fail "incorrect import contract")
            modifyIORef' imports (+1);bad<-readIORef failImport
            pure $ toJSON [object ["success" .= not bad],object ["success" .= not bad]]
          ("getwalletinfo",[])->pure $ object ["walletname" .= N.nativeWallet settings,"descriptors" .= True,"scanning" .= False
            ,"private_keys_enabled" .= True,"external_signer" .= False]
          ("listdescriptors",[Bool False])->do
            bad<-readIORef broken
            pure $ object ["descriptors" .= [object ["desc" .= (if bad then "changed" else descriptor),"active" .= True,"internal" .= internal]
                  | (descriptor,internal)<-zip public [False,True]]]
          ("getnewaddress",[String "bridge-initial-funding",String "bech32"])->pure $ String "fixture-funding-address"
          _->fail "unexpected native initialization RPC"
      run=N.evalNativeRecoveryWith call settings
  address<-run (N.InitializeNativeWallet seedFile Nothing False 999)
  repeated<-run (N.InitializeNativeWallet seedFile Nothing False 999)
  firstImports<-readIORef imports;firstCreates<-readIORef creates
  writeIORef broken True
  changed<-try (run $ N.InitializeNativeWallet seedFile Nothing False 999) :: IO (Either BridgeError T.Text)
  writeIORef broken False;writeIORef exists False;writeIORef failImport True;writeIORef restoring True
  let failedSeed=directory</>"failed-native-seed.txt"
  savePrivate failedSeed (B.pack $ map (fromIntegral . fromEnum) phrase)
  failed<-try (run $ N.InitializeNativeWallet failedSeed Nothing True 999) :: IO (Either BridgeError T.Text)
  checkpoint<-doesFileExist (failedSeed<>".initialized.json")
  retried<-try (run $ N.InitializeNativeWallet failedSeed Nothing True 999) :: IO (Either BridgeError T.Text)
  finalImports<-readIORef imports;finalCreates<-readIORef creates
  let refused code result=case result of Left (BridgeError actual)->actual==code; _->False
  pure (address==repeated && firstImports==1 && firstCreates==1 && finalImports==2 && finalCreates==2 && not checkpoint
    && refused "native_seed_wallet_mismatch" changed && refused "native_seed_import_or_rescan_failed" failed
    && refused "native_seed_wallet_exists_requires_review" retried)

-- Real wizard on a disposable terminal; script writes to /dev/null, never a
-- transcript. Recovery words are read only in memory and never printed by tests.
simpleContract :: FilePath -> FilePath -> IO Bool
simpleContract parent executable=do
  let directory=parent</>"simple"
      commands=directory</>"commands"
      node=directory</>"bitcoin.conf"
  createDirectory directory;setFileMode directory 0o700
  -- A killed wizard left settings and an already-displayed wallet phrase.
  -- Retrying must preserve the settings and keep the funding identity.
  let interrupted=directory</>".ecx-bridge"
      wallet=directory</>".ecx-bridge-solana-wallet"
  mapM_ (\path->createDirectory path >> setFileMode path 0o700) [interrupted,wallet]
  savePrivate (interrupted</>"configuring") "ecx-bridge-configuration-v1\n"
  savePrivate (interrupted</>"retained-credential") "interrupted-fixture\n"
  let primaryFile=directory</>"primary.url"
      preserved=["native-admin.auth","native-worker.auth","native-signer.auth","native-rpc.conf","backup.password"]
  savePrivate primaryFile "https://primary.example.invalid/"
  savePrivate (interrupted</>"answer-primary.json") (L.toStrict $ encode primaryFile)
  savePrivate (interrupted</>"answer-verifier.json") (L.toStrict $ encode ("https://verifier.example.invalid/"::String))
  _<-NodeSetup.credentials interrupted
  getRandomBytes 32 >>= savePrivate (interrupted</>"backup.password")
  before<-mapM (B.readFile . (interrupted</>)) preserved
  priorPhrase<-either (fail . T.unpack) pure (mnemonic $ B.replicate 16 1)
  savePrivate (wallet</>"solana-recovery.txt") (B8.pack $ priorPhrase<>"\n")
  savePrivate (wallet</>"solana-recovery.saved") "saved\n"
  createDirectory commands;setFileMode commands 0o700
  savePrivate node "server=1\n"
  savePrivate (commands</>"restic") "#!/bin/sh\nexit 0\n"
  savePrivate (commands</>"systemctl") "#!/bin/sh\ncase \"$1\" in cat|restart) exit 0;; *) exit 1;; esac\n"
  mapM_ (\name->setFileMode (commands</>name) 0o700) ["restic","systemctl"]
  old<-getEnv "PATH"
  harness<-getExecutablePath
  let stage starting=do
        let program=if starting then harness else executable
            arguments=if starting then ["--start-setup",interrupted] else ["configure"]
            quote value="'"<>concatMap (\c->if c=='\'' then "'\\''" else [c]) value<>"'"
            args=if os=="darwin" then ["-q","/dev/null",program]<>arguments
                 else ["-q","-c",unwords(map quote $ program:arguments),"/dev/null"]
        result<-timeout (45*1000000) $ withCreateProcess ((proc "script" args)
          {cwd=Just directory,std_in=CreatePipe,std_out=CreatePipe,std_err=NoStream,create_group=True}) $ \input output _ process->do
            let Just writer=input; Just reader=output
                await needle=go "" (0::Int)
                 where
                  go found count=do
                    unless (count<65536) (fail "wizard_output_bound")
                    char<-hGetChar reader
                    let next=drop (max 0 (length found+1-max 256 (length needle))) (found<>[char])
                    unless (not $ any (`isInfixOf` next)
                      ["Solana Mainnet RPC URL","Independent Mainnet RPC URL","Write down these 12 solana recovery words","Additional randomness for solana","private-entropy-fixture",priorPhrase])
                      (fail "wizard_repeated_completed_prompt_or_phrase")
                    if needle `isSuffixOf` next then pure () else go next (count+1)
                answer label value=await label >> await ": " >> hPutStrLn writer value >> hFlush writer
                ack=await "Type saved once you have backed up the phrase:" >> hPutStrLn writer "saved" >> hFlush writer
            if starting then do
              answer "Additional randomness for ecx (hidden; Enter skips)" "private-entropy-fixture"
              ack
              await "Saved private setup"
             else do
              answer "NEW HTTPS restic repository URL" "https://backup.example.invalid/repository"
              answer "Public HTTPS origin" "-"
              answer "Initial SOL ownership statement (fund once with your own SOL; add trading inventory after startup)" ""
              answer "Initial SOL ownership statement (fund once with your own SOL; add trading inventory after startup)" "I own the initial SOL funding — opérateur"
              await "No wallets generated; run start interactively to create custody."
            hClose writer
            remaining<-hGetContents reader
            _<-evaluate(length remaining)
            code<-waitForProcess process
            pure(code==ExitSuccess)
        pure(result==Just True)
      run=do
        setEnv "PATH" (commands<> ":"<>old)
        configured<-stage False
        -- Configuration must neither generate custody nor complete setup. A
        -- piped start must fail before either of those actions, too.
        let absent=[interrupted</>"setup.json",wallet</>"solana.keypair.json"
                   ,directory</>".ecx-bridge-ecx-wallet/ecx-recovery.txt"]
        beforeStart<-mapM doesFileExist absent
        (refused,_,failure)<-readProcessWithExitCode harness ["--start-setup",interrupted] ""
        afterRefusal<-mapM doesFileExist absent
        started<-stage True
        after<-mapM (B.readFile . (interrupted</>)) preserved
        checked<-verify directory node
        pure(configured && started && not(or beforeStart) && beforeStart==afterRefusal
          && refused/=ExitSuccess && "wallet_generation_requires_interactive_terminal" `isInfixOf` failure
          && before==after && checked)
  run `finally` setEnv "PATH" old
 where
  verify directory node=do
    let setup=directory</>".ecx-bridge"
    c<-Bootstrap.setupConfig setup
    runtimeExists<-doesFileExist(setup</>"worker.json")
    rejected<-try(C.loadConfig(setup</>"bootstrap.json")) :: IO(Either BridgeError C.Config)
    phraseA<-B8.strip <$> B.readFile(directory</>".ecx-bridge-solana-wallet/solana-recovery.txt")
    phraseB<-B8.strip <$> B.readFile(directory</>".ecx-bridge-ecx-wallet/ecx-recovery.txt")
    expectedPhrase<-either (fail . T.unpack) pure (mnemonic $ B.replicate 16 1)
    archives<-filter (".ecx-bridge-interrupted-" `isPrefixOf`) <$> listDirectory directory
    retained<-(=="interrupted-fixture\n") <$> B.readFile(setup</>"retained-credential")
    repository<-B.readFile(setup</>"backup.repository")
    acknowledgements<-mapM B.readFile
      [directory</>(".ecx-bridge-"<>asset<>"-wallet")</>(asset<>"-recovery.saved") | asset<-["solana","ecx"]]
    answerModes<-mapM (fmap ((.&. 0o777).fileMode) . getFileStatus . (setup</>))
      ["answer-primary.json","answer-verifier.json","answer-backup.json","answer-origin.json","answer-initial-funding.json"]
    solana<-either (const $ fail "generated_phrase_invalid") pure (walletKey $ B8.unpack phraseA)
    rules<-B8.lines <$> B.readFile(setup</>"native-rpc.conf")
    valid<-forM ["admin","worker","signer"] $ \role->do
      let path=setup</>"native-"<>role<>".auth"
      auth<-B8.strip <$> B.readFile path
      mode<-fileMode <$> getFileStatus path
      let (user,tailBytes)=B8.break (==':') auth
          password=B.drop 1 tailBytes
          match=[B.drop (B.length user+9) line | line<-rules,("rpcauth="<>user<>":") `B.isPrefixOf` line]
          whitelist=[B.drop (B.length user+14) line | line<-rules,("rpcwhitelist="<>user<>":") `B.isPrefixOf` line]
      pure $ mode .&. 0o777==0o600 && B.length password>=40 && case (match,whitelist) of
        ([value],[methods])->
          let (salt,hashValue)=B8.break (=='$') value
              expected=Hex.convertToBase Hex.Base16 (hmac salt password::HMAC SHA256)::B.ByteString
          in B.drop 1 hashValue==expected
                                && (role/="worker" || all (`notElem` B8.split ',' methods) ["walletprocesspsbt","dumpprivkey","listdescriptors","backupwallet"])
                                && (role/="signer" || "sendrawtransaction" `notElem` B8.split ',' methods)
        _->False
    -- Default setup selects the managed node. Exercise existing-node provisioning
    -- separately against a disposable fixture, without installing a real service.
    setupValue<-either fail pure . eitherDecodeStrict' =<< B.readFile(setup</>"setup.json")
    managedSelected<-case setupValue of
      Object fields->do
        let selected=KM.lookup "managedNode" fields==Just(Bool True)
              && KM.lookup "initialFundingOwnership" fields==Just(String "I own the initial SOL funding — opérateur")
            changed=KM.insert "managedNode" (Bool False) $ KM.insert "nodeConfig" (toJSON node) $
              KM.insert "nodeService" (String "fixture.service") fields
        B.writeFile (setup</>"setup.json") (L.toStrict $ encode $ Object changed)
        pure selected
      _->pure False
    Bootstrap.bind setup
    NodeSetup.provision setup
    first<-B.readFile node
    NodeSetup.provision setup
    second<-B.readFile node
    prior<-B.readFile(setup</>"node-config.before")
    -- Changing settings after any bootstrap begins cannot silently change identity.
    B.appendFile (setup</>"interface.json") " "
    Bootstrap.bind setup -- whitespace is not a semantic change
    B.writeFile (setup</>"interface.json") "{}"
    changed<-try(Bootstrap.bind setup) :: IO(Either BridgeError ())
    historyChecked<-originContract
    B.appendFile node "# unexpected operator edit\n"
    nodeChanged<-try(NodeSetup.provision setup) :: IO(Either BridgeError ())
    pure(retained && null archives && repository=="rest:https://backup.example.invalid/repository"
      && all (=="saved\n") acknowledgements && all (==0o600) answerModes
      && C.solanaRpc c=="https://primary.example.invalid/" && C.solanaVerifierRpc c==Just "https://verifier.example.invalid/"
      && phraseA==B8.pack expectedPhrase && managedSelected && historyChecked && either (const True) (const False) nodeChanged && all id valid && not runtimeExists && either (const True) (const False) rejected
      && C.profile c==CanonicalBeta && C.mint c==Bootstrap.canonicalMint && C.custodyOwner c==base58(B.drop 32 solana)
      && phraseA/=phraseB && first==second && prior=="server=1\n" && "rpcwhitelistdefault=0" `B.isInfixOf` first
      && either (const True) (const False) changed)

-- Read-only RPC fixtures, not claims of real Mainnet acceptance.
originContract :: IO Bool
originContract=do
  let address=base58(B.replicate 32 7)
      signature=base58(B.replicate 64 1)
      other=base58(B.replicate 64 2)
      entry sig=object ["signature" .= sig,"slot" .= (12::Int),"err" .= Null,"confirmationStatus" .= String "finalized"]
      request variant provider method args=case (method,args) of
        ("getSignaturesForAddress",[_,Object options])->
          if KM.member "before" options && variant/="repeat" then pure(toJSON ([]::[Value]))
          else pure(toJSON [entry $ if variant=="disagree" && provider=="second" then other else signature])
        ("getTransaction",_)->if variant=="missing" then pure Null else pure $ object
          ["meta" .= object [],"transaction" .= object ["signatures" .= [signature],"message" .= object
            ["accountKeys" .= [if variant=="wrong-account" then base58(B.replicate 32 8) else address]]]]
        _->fail "unexpected_bootstrap_read"
      run variant=try(Bootstrap.agreedOrigin ["first","second"] (request variant) address) :: IO(Either BridgeError T.Text)
  good<-run "ok"
  refused<-mapM run ["repeat","disagree","missing","wrong-account"]
  pure(either (const False) (==signature) good && all (either (const True) (const False)) refused)


-- Provider plan refusal and missing/misbound history must fail before setup spends.
preflightContract :: IO Bool
preflightContract=do
  let signature=base58(B.replicate 64 1)
      request variant method args=case (method,args) of
        ("getSignaturesForAddress",[String mint,_]) | mint==Bootstrap.canonicalMint->
          if variant=="forbidden" then throwIO(BridgeError "rpc_method_forbidden")
          else pure $ toJSON (if variant=="empty" then [] else [object ["signature" .= signature]])
        ("getTransaction",[String sig,options]) | sig==signature->do
          maximumVersion<-fieldValue "maxSupportedTransactionVersion" options :: IO Int
          require (maximumVersion==1) "preflight_requires_v1"
          if variant=="missing" then pure Null else pure $ object
            ["meta" .= object [],"transaction" .= object
              ["signatures" .= [if variant=="wrong-signature" then base58(B.replicate 64 2) else signature]
              ,"message" .= object ["accountKeys" .= [if variant=="wrong-account" then base58(B.replicate 32 8) else Bootstrap.canonicalMint]]]]
        _->fail "unexpected_preflight_read"
      run variant=try(Bootstrap.checkHistoryWith $ request variant) :: IO(Either BridgeError ())
  good<-run "ok"
  refused<-mapM run ["forbidden","empty","missing","wrong-signature","wrong-account"]
  pure(either (const False) (const True) good && all (either (const True) (const False)) refused)

-- Losing the caller during backupwallet must retain the directory: the node RPC
-- may still be writing after the Haskell helper has been cancelled.
backupHandoffCancellation :: FilePath -> IO Bool
backupHandoffCancellation parent=do
  let spool=parent</>"native-spool"; input=parent</>"native-request"
      settings=N.NativeSettings ECXBetanetDevnet "http://127.0.0.1:28532" (parent</>"cookie") "backup-test"
        967680 "00000000000000030101ba5cfea54b22becc79f95dc6040beb76e01dd9d04042"
      binding=digest . L.toStrict . encode $ object ["profile" .= N.profile settings,"wallet" .= N.nativeWallet settings
        ,"height" .= N.nativeCheckpointHeight settings,"checkpoint" .= N.nativeCheckpointHash settings]
      call _ method _=case method of
        "getblockchaininfo"->pure $ object ["chain" .= ("main"::T.Text),"initialblockdownload" .= False,"blocks" .= (967681::Int)]
        "getblockhash"->pure $ String $ N.nativeCheckpointHash settings
        "getconnectioncount"->pure $ Number 1
        "getwalletinfo"->pure $ object ["walletname" .= N.nativeWallet settings,"descriptors" .= True
          ,"scanning" .= False,"private_keys_enabled" .= True,"external_signer" .= False]
        "listdescriptors"->pure $ object ["wallet_name" .= N.nativeWallet settings,"descriptors" .= [object ["desc" .= ("public"::T.Text)]]]
        "backupwallet"->throwIO ThreadKilled
        _->fail "unexpected backup fixture RPC"
      run=bracket (hDuplicate stdin) hClose $ \saved->
        withBinaryFile input ReadMode $ \source->
          (hDuplicateTo source stdin >> N.evalNativeRecoveryWith call settings (N.ServeNativeWalletBackup spool))
            `finally` hDuplicateTo saved stdin
  createDirectory spool;setFileMode spool 0o700
  savePrivate input ("ECX-NATIVE-BACKUP/1 "<>TE.encodeUtf8 binding<>"\n")
  first<-try run :: IO (Either AsyncException ())
  second<-try run :: IO (Either AsyncException ())
  before<-sort <$> listDirectory spool
  third<-try run :: IO (Either BridgeError ())
  after<-sort <$> listDirectory spool
  pure (first==Left ThreadKilled && second==Left ThreadKilled && before==after
    && length (filter (isPrefixOf "export-") before)==2
    && case third of Left (BridgeError "native_backup_spool_requires_cleanup")->True; _->False)

-- Real inode-bound directory renames under a private workspace parent. No live
-- installation, database, service, credential or external directory is touched.
rotationFilesContract :: IO ()
rotationFilesContract=bracket temporary removeDirectoryRecursive $ \directory->do
  let first=directory</>"old-config";second=directory</>"old-state"
      paths=[first,second];journal=directory</>"journal";tag=replicate 32 'a'
      retired path=path<>".retired-"<>tag
      make path mode=createDirectory path >> setFileMode path mode
      refuse action=do
        result<-try(action >> pure ()) :: IO (Either SomeException ())
        require (either (const True) (const False) result) "rotation_directory_refusal_failed"
  make first 0o755;make second 0o700
  B.writeFile (first</>"retained") "old configuration";setFileMode (first</>"retained") 0o640
  B.writeFile (second</>"retained") "old state";setFileMode (second</>"retained") 0o600
  entries<-RD.stageRotationDirectories journal tag paths
  require (map RD.rotationSource entries==paths && map RD.rotationDestination entries==map retired paths)
    "rotation_directory_staging_changed_paths"
  present<-mapM doesDirectoryExist paths
  require (and present) "rotation_directory_staging_moved_source"
  refuse(RD.publishRotationDirectories journal [first])
  refuse(RD.stageRotationDirectories journal (replicate 32 'b') paths)
  -- Crash after one rename, before its permission repair and completion.
  renameDirectory first (retired first)
  make first 0o700
  refuse(RD.publishRotationDirectories journal paths)
  removeDirectory first
  RD.publishRotationDirectories journal paths
  contents<-mapM (B.readFile . (</>"retained") . retired) paths
  rootModes<-mapM (fmap ((.&. 0o7777).fileMode) . getFileStatus . retired) paths
  leafModes<-mapM (fmap ((.&. 0o7777).fileMode) . getFileStatus . (</>"retained") . retired) paths
  require (contents==["old configuration","old state"] && rootModes==[0o700,0o700]
    && leafModes==[0o640,0o600]) "rotation_directory_archive_changed_contents"
  -- After the global completion marker, replay must preserve a new generation.
  make first 0o755;B.writeFile (first</>"new") "new installation"
  replay<-RD.stageRotationDirectories journal tag paths
  RD.publishRotationDirectories journal paths
  current<-B.readFile(first</>"new")
  require (replay==entries && current=="new installation") "rotation_directory_replay_moved_new_generation"
  -- A substituted archive with identical contents is still the wrong inode.
  let moved=directory</>"original-retired"
  renameDirectory (retired second) moved
  make (retired second) 0o700
  B.writeFile (retired second</>"retained") "old state"
  refuse(RD.publishRotationDirectories journal paths)
  removeFile(retired second</>"retained");removeDirectory(retired second)
  renameDirectory moved (retired second)
  RD.publishRotationDirectories journal paths
  let alias=directory</>"alias"
  createSymbolicLink first alias
  refuse(RD.stageRotationDirectories (directory</>"alias-journal") tag [alias])
  refuse(RD.stageRotationDirectories (directory</>"overlap-journal") tag [first,first])
  setFileMode directory 0o770
  refuse(RD.publishRotationDirectories journal paths)
  setFileMode directory 0o700
  unchanged<-RD.loadRotationDirectories journal
  require (unchanged==entries) "rotation_directory_receipt_changed"
 where
  temporary=do
    parent<-getCurrentDirectory
    (path,handle)<-openTempFile parent ".rotation-directory-test"
    hClose handle;removeFile path;createDirectory path;setFileMode path 0o700
    pure path

-- Reconstruct both process-death boundaries of private journal publication.
-- An orphan before rename is not authority; after rename the record is readable
-- and replayable without unlinking any alias or weakening the single-link check.
privateRecordCrashContract :: IO ()
privateRecordCrashContract=bracket temporary removeDirectoryRecursive $ \directory->do
  let before=directory</>"before-rename"
      orphan=before<>".pending-"<>replicate 64 'a'
      after=directory</>"after-rename"
      staged=after<>".pending-"<>replicate 64 'b'
      expected="retained private lifecycle receipt"
      refuse action=do
        result<-try(action >> pure ()) :: IO (Either SomeException ())
        require (either (const True) (const False) result) "private_record_refusal_failed"
  -- A process died while writing, before it had a complete fsynced temporary.
  B.writeFile orphan "partial";setFileMode orphan 0o600
  RF.savePrivateRecord before expected
  RF.savePrivateRecord before expected
  first<-readPrivate before
  abandoned<-B.readFile orphan
  firstLinks<-linkCount <$> getFileStatus before
  require (first==expected && abandoned=="partial" && firstLinks==1)
    "private_record_pre_rename_retry_failed"
  -- A process died immediately after rename, before parent synchronization.
  B.writeFile staged expected;setFileMode staged 0o600
  renameFile staged after
  RF.savePrivateRecord after expected
  second<-readPrivate after
  secondLinks<-linkCount <$> getFileStatus after
  oldTemporary<-doesPathExist staged
  require (second==expected && secondLinks==1 && not oldTemporary)
    "private_record_post_rename_retry_failed"
  refuse(RF.savePrivateRecord after "different receipt")
  let alias=directory</>"untrusted-hardlink"
  createLink after alias
  refuse(RF.savePrivateRecord after expected)
  removeFile alias
  RF.savePrivateRecord after expected
  let symbolic=directory</>"untrusted-symlink"
  createSymbolicLink after symbolic
  refuse(RF.savePrivateRecord symbolic expected)
  setFileMode directory 0o755
  refuse(RF.savePrivateRecord before expected)
  setFileMode directory 0o700
  retained<-mapM readPrivate [before,after]
  require (retained==[expected,expected]) "private_record_refusal_changed_receipt"
 where
  temporary=do
    parent<-getCurrentDirectory
    (path,handle)<-openTempFile parent ".private-record-test"
    hClose handle;removeFile path;createDirectory path;setFileMode path 0o700
    pure path
