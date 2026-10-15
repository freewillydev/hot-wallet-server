{-# LANGUAGE ScopedTypeVariables #-}
-- The critical runtime calls this cycle. Chain reads never share a DB transaction.
module Bridge.Observer (ObserverSettings(..),observationOrigins,observeOnce) where
import Bridge.Native
import Bridge.NativeObservation
import Bridge.Solana
import Bridge.SolanaObservation
import Bridge.RPC (rpc,parseValue)
import qualified Bridge.Sidechain as Side
import qualified Bridge.Wire as W
import Bridge.Domain
import Bridge.Lifecycle (sourcePolicy)
import Data.Aeson
import qualified Data.Set as Set
import qualified Data.Text as T
import Bridge.Error (reject,require)
import Bridge.Store
import Control.Exception (IOException,catch,try)
import Control.Monad (forM_)
import Data.Text (Text)
import Data.Time.Clock.POSIX (getPOSIXTime)
import Network.HTTP.Client (Manager)

data ObserverSettings = ObserverSettings
  { nativeSettings :: NativeSettings, solanaSettings :: SolanaSettings
  , defaultNativeDepth :: Int, tokenOrigin :: Text, operatingOrigin :: Text
  , sidechainSettings :: [Side.SidechainSettings] }

observationOrigins :: ObserverSettings -> [(Text,Text)]
observationOrigins settings=[("Native",nativeCheckpointHash $ nativeSettings settings),
  ("Solana",tokenOrigin settings),("SolanaOperating",operatingOrigin settings)]<>
  [(T.pack(show $ W.sidechainAsset policy),W.sidechainCheckpoint policy) |
    chain<-sidechainSettings settings,let policy=Side.sidechainPolicy chain]

observeOnce :: Manager -> ObserverSettings -> Reader -> Writer -> IO ()
observeOnce manager settings reader writer = do
  let native=nativeSettings settings; solana=solanaSettings settings
      call=solanaCall manager solana
      verifier=fmap (\url->rpc manager url Nothing) (solanaVerifierRpc solana)
      lookupInstruction address=evalRead reader (LookupInstruction address)
      lookupReferences keys=evalRead reader (LookupReferences keys)
      nativeScan = do
        previous<-evalRead reader (ReadCheckpoint "Native")
        depth<-evalRead reader (MaximumNativeDepth $ defaultNativeDepth settings)
        now<-epoch
        scanNativeWith (nativeCall manager native) (withNativeHistory native) (readNativeTransaction native) native (defaultNativeDepth settings) depth previous now
          (evalRead reader . NativeSourcePage) lookupInstruction (evalWrite writer . CommitNativePage)
      commit chain result=do
        saved<-try ((either (\(BridgeError code)->reject code) (evalWrite writer . CommitScan) result)
          `catch` (\(_::IOException)->reject "observer_io_unavailable"))
        case saved of
          Right ()->pure ()
          Left (BridgeError code)->do now<-epoch; evalWrite writer (ScanFailed chain now code)
  nativeResult<-try (nativeScan `catch` (\(_::IOException)->reject "observer_io_unavailable"))
  commit "Native" nativeResult
  scanned<-try $ (do
    tokenPrevious<-evalRead reader (ReadCheckpoint "Solana")
    operatingPrevious<-evalRead reader (ReadCheckpoint "SolanaOperating")
    tokenProgress<-evalRead reader (ReadHistoryProgress "Solana")
    operatingProgress<-evalRead reader (ReadHistoryProgress "SolanaOperating")
    pending<-evalRead reader PendingVerification
    now<-epoch
    results<-scanSolanaPairProgressWith call verifier solana (tokenOrigin settings,tokenPrevious,tokenProgress)
      (operatingOrigin settings,operatingPrevious,operatingProgress) now pending lookupInstruction lookupReferences
    pure [(chain,if chain=="Solana" then tokenProgress else operatingProgress,result) | (chain,result)<-results])
    `catch` (\(_::IOException)->reject "observer_io_unavailable")
  let scans=case scanned of
        Right results->results
        Left problem->[("Solana",Nothing,Left problem),("SolanaOperating",Nothing,Left problem)]
  forM_ scans $ \(chain,expected,result)->do
    saved<-try $ (case result of
      Left(BridgeError code)->reject code
      Right(ObservationMore next)->evalWrite writer (RecordHistoryProgress chain expected next)
      Right(ObservationReady batch complete)->evalWrite writer (CommitHistoryScan expected batch complete))
      `catch` (\(_::IOException)->reject "observer_io_unavailable")
    case saved of
      Right ()->pure ()
      Left(BridgeError code)->do now<-epoch; evalWrite writer (ScanFailed chain now code)
  forM_ (sidechainSettings settings) $ \chain->do
    let name=T.pack(show $ W.sidechainAsset $ Side.sidechainPolicy chain)
    result<-try (observeSidechain manager settings chain reader writer
      `catch` (\(_::IOException)->reject "observer_io_unavailable"))
    commit name result
  candidates<-evalRead reader PromotionCandidates
  now<-epoch
  forM_ candidates $ \identifier->evalWrite writer (PromoteDeposit now identifier) >> pure ()
 where epoch=floor <$> getPOSIXTime

-- Scan all issued and unissued allocations. An earlier receipt disappearing is
-- unavailability evidence, never permission to erase its customer liability.
-- Partial pages may retain observations but cannot certify complete coverage.
observeSidechain :: Manager -> ObserverSettings -> Side.SidechainSettings -> Reader -> Writer -> IO W.ScanBatch
observeSidechain manager settings chain reader writer=do
  let policy=Side.sidechainPolicy chain; asset=W.sidechainAsset policy; name=T.pack(show asset)
      call=Side.sidechainCall manager chain; validator=Side.validatorCall manager chain
      native=nativeCall manager (nativeSettings settings)
      position=Side.sidechainHeadWith native validator call asset
  previous<-evalRead reader (ReadCheckpoint name)
  now<-floor <$> getPOSIXTime
  start@(_,head)<-position
  let batch deposits=W.ScanBatch name (W.sidechainCheckpoint policy) previous head now deposits []
      scan after seen=do
        instructions<-evalRead reader (SidechainInstructions asset after)
        outputs<-Side.readOutputsWith call asset [address | (_,address,_)<-instructions]
        observed<-mapM (\output->do
          (identifier,saved)<-case [(oid,saved) | (oid,address,saved)<-instructions,address==Side.outputAddress output] of
            [one]->pure one
            _->reject "sidechain_source_binding_mismatch"
          terms<-either reject pure (sourcePolicy saved asset)
          (anchor,depth)<-if Side.outputKind output=="Regular"
            then Side.verifyOutputWith native validator call asset output else pure(head,0)
          pure $ W.Deposit (Side.outputId asset output) (Just identifier) asset (Side.outputAmount output)
            anchor depth (depth>=W.sidechainDepth terms) now) outputs
        evalWrite writer (CommitSidechainPage $ batch observed)
        let allSeen=Set.union seen (Set.fromList $ map W.depositId observed)
        require (Set.size allSeen<=100000) "sidechain_scan_too_large"
        case reverse instructions of
          (identifier,_,_):_ | length instructions==256->scan (Just identifier) allSeen
          _->pure allSeen
      missing after seen=do
        page<-evalRead reader (SidechainSourcePage asset after)
        let absent=[saved {W.depositAnchor=head,W.depositConfirmations=0,W.depositEligible=False}
              | saved<-page,W.depositId saved `Set.notMember` seen]
        evalWrite writer (CommitSidechainPage $ batch absent)
        case reverse page of
          saved:_ | length page==256->missing (Just $ W.depositId saved) seen
          _->pure ()
  seen<-scan Nothing Set.empty
  missing Nothing seen
  end<-position
  require (end==start) "sidechain_scan_changed"
  pure (batch [])
