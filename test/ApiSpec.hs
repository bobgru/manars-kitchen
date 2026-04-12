{-# LANGUAGE OverloadedStrings #-}

module ApiSpec (spec) where

import Test.Hspec
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Time (Day, fromGregorian)
import Network.HTTP.Client (newManager, defaultManagerSettings)
import Network.Wai.Handler.Warp (testWithApplication)
import Servant.API ((:<|>)(..))
import Servant.Server (serve)
import Servant.Client
    ( ClientM, ClientEnv, mkClientEnv, runClientM, client, baseUrlPort
    , parseBaseUrl, ClientError(..), responseStatusCode
    )
import Network.HTTP.Types.Status (statusCode)
import System.Directory (removeFile, doesFileExist)

import Auth.Types (Role(..), User)
import Domain.Types (WorkerId(..), StationId(..), SkillId(..), AbsenceTypeId(..), Schedule(..))
import Domain.Skill (Skill)
import Domain.Shift (ShiftDef)
import Domain.Hint (Hint(..))
import Domain.Pin (PinnedAssignment)
import Domain.Absence (AbsenceType(..), AbsenceContext(..), AbsenceRequest, emptyAbsenceContext)
import Domain.Scheduler (ScheduleResult)
import Repo.SQLite (mkSQLiteRepo)
import Repo.Types (Repository(..), DraftInfo, CalendarCommit, AuditEntry(..))
import Service.Auth (register)
import qualified Service.Worker as SW
import Servant.API (NoContent)
import Server.Api (api, fullApi)
import Server.Json
import Server.Handlers (fullServer)
import Server.Rpc
import CLI.Commands (Command(..))
import CLI.RpcClient (RpcEnv(..), dispatchCommand)

-- -----------------------------------------------------------------
-- Client functions derived from the API type
-- -----------------------------------------------------------------

-- Original endpoints
listSkillsC      :: ClientM [(SkillId, Skill)]
listStationsC    :: ClientM [(Int, String)]
listShiftsC      :: ClientM [ShiftDef]
listSchedulesC   :: ClientM [String]
getScheduleC     :: String -> ClientM Schedule
_deleteScheduleC :: String -> ClientM NoContent
listDraftsC      :: ClientM [DraftInfo]
createDraftC     :: CreateDraftReq -> ClientM DraftCreatedResp
getDraftC        :: Int -> ClientM DraftInfo
generateDraftC   :: Int -> GenerateDraftReq -> ClientM ScheduleResult
commitDraftC     :: Int -> CommitDraftReq -> ClientM NoContent
discardDraftC    :: Int -> ClientM NoContent
getCalendarC     :: Maybe Day -> Maybe Day -> ClientM Schedule
listCalendarHistoryC :: ClientM [CalendarCommit]
_getCalendarCommitC  :: Int -> ClientM Schedule
listPendingAbsencesC :: ClientM [AbsenceRequest]
requestAbsenceC  :: RequestAbsenceReq -> ClientM AbsenceCreatedResp
approveAbsenceC  :: Int -> ClientM NoContent
rejectAbsenceC   :: Int -> ClientM NoContent
getConfigC       :: ClientM [(String, Double)]

-- Skill CRUD
createSkillC     :: CreateSkillReq -> ClientM NoContent
deleteSkillC     :: Int -> ClientM NoContent

-- Station CRUD
createStationC    :: CreateStationReq -> ClientM NoContent
_deleteStationC   :: Int -> ClientM NoContent
setStationHoursC  :: Int -> SetStationHoursReq -> ClientM NoContent
_setStationClosureC :: Int -> SetStationClosureReq -> ClientM NoContent

-- Shift CRUD
createShiftC     :: CreateShiftReq -> ClientM NoContent
deleteShiftC     :: String -> ClientM NoContent

-- Worker configuration
setWorkerHoursC :: Int -> SetWorkerHoursReq -> ClientM NoContent
_setWorkerOvertimeC :: Int -> SetWorkerOvertimeReq -> ClientM NoContent
_setWorkerPrefsC :: Int -> SetWorkerPrefsReq -> ClientM NoContent
_setWorkerVarietyC :: Int -> SetWorkerVarietyReq -> ClientM NoContent
_setWorkerShiftPrefsC :: Int -> SetWorkerShiftPrefsReq -> ClientM NoContent
_setWorkerWeekendOnlyC :: Int -> SetWorkerWeekendOnlyReq -> ClientM NoContent
_setWorkerSeniorityC :: Int -> SetWorkerSeniorityReq -> ClientM NoContent
_setWorkerCrossTrainingC :: Int -> SetWorkerCrossTrainingReq -> ClientM NoContent
_setWorkerEmploymentStatusC :: Int -> SetWorkerEmploymentStatusReq -> ClientM NoContent
_setWorkerOvertimeModelC :: Int -> SetWorkerOvertimeModelReq -> ClientM NoContent
_setWorkerPayTrackingC :: Int -> SetWorkerPayTrackingReq -> ClientM NoContent
_setWorkerTempC :: Int -> SetWorkerTempReq -> ClientM NoContent

-- Worker skills / pairing
grantWorkerSkillC :: Int -> Int -> ClientM NoContent
revokeWorkerSkillC :: Int -> Int -> ClientM NoContent
_avoidPairingC :: Int -> WorkerPairingReq -> ClientM NoContent
_preferPairingC :: Int -> WorkerPairingReq -> ClientM NoContent

-- Pins
_listPinsC :: ClientM [PinnedAssignment]
_addPinC :: PinnedAssignment -> ClientM NoContent
_removePinC :: PinnedAssignment -> ClientM NoContent

-- Calendar mutations
_unfreezeC :: UnfreezeReq -> ClientM NoContent
freezeStatusC :: ClientM FreezeStatusResp

-- Config writes
setConfigC :: String -> SetConfigReq -> ClientM NoContent
_applyPresetC :: String -> ClientM NoContent
_resetConfigC :: ClientM NoContent
_setPayPeriodC :: SetPayPeriodReq -> ClientM NoContent

-- Audit
getAuditLogC :: ClientM [AuditEntry]

-- Checkpoints
createCheckpointC :: CreateCheckpointReq -> ClientM NoContent
commitCheckpointC :: String -> ClientM NoContent
_rollbackCheckpointC :: String -> ClientM NoContent

-- Import/Export
_exportC :: ClientM ExportResp
_importC :: ImportReq -> ClientM ImportResp

-- Absence type management
createAbsenceTypeC :: CreateAbsenceTypeReq -> ClientM NoContent
_deleteAbsenceTypeC :: Int -> ClientM NoContent
_setAbsenceAllowanceC :: Int -> SetAbsenceAllowanceReq -> ClientM NoContent

-- User management
listUsersC :: ClientM [User]
_createUserC :: CreateUserReq -> ClientM NoContent
_deleteUserC :: String -> ClientM NoContent

-- Hint sessions
_listHintsC :: Maybe Int -> Maybe Int -> ClientM [Hint]
_addHintC :: AddHintReq -> ClientM [Hint]
_revertHintC :: HintSessionRef -> ClientM [Hint]
_applyHintsC :: HintSessionRef -> ClientM NoContent
_rebaseHintsC :: HintSessionRef -> ClientM RebaseResultResp

listSkillsC
    :<|> listStationsC
    :<|> listShiftsC
    :<|> listSchedulesC
    :<|> getScheduleC
    :<|> _deleteScheduleC
    :<|> listDraftsC
    :<|> createDraftC
    :<|> getDraftC
    :<|> generateDraftC
    :<|> commitDraftC
    :<|> discardDraftC
    :<|> getCalendarC
    :<|> listCalendarHistoryC
    :<|> _getCalendarCommitC
    :<|> listPendingAbsencesC
    :<|> requestAbsenceC
    :<|> approveAbsenceC
    :<|> rejectAbsenceC
    :<|> getConfigC
    -- New endpoints
    :<|> createSkillC
    :<|> deleteSkillC
    :<|> createStationC
    :<|> _deleteStationC
    :<|> setStationHoursC
    :<|> _setStationClosureC
    :<|> createShiftC
    :<|> deleteShiftC
    :<|> setWorkerHoursC
    :<|> _setWorkerOvertimeC
    :<|> _setWorkerPrefsC
    :<|> _setWorkerVarietyC
    :<|> _setWorkerShiftPrefsC
    :<|> _setWorkerWeekendOnlyC
    :<|> _setWorkerSeniorityC
    :<|> _setWorkerCrossTrainingC
    :<|> _setWorkerEmploymentStatusC
    :<|> _setWorkerOvertimeModelC
    :<|> _setWorkerPayTrackingC
    :<|> _setWorkerTempC
    :<|> grantWorkerSkillC
    :<|> revokeWorkerSkillC
    :<|> _avoidPairingC
    :<|> _preferPairingC
    :<|> _listPinsC
    :<|> _addPinC
    :<|> _removePinC
    :<|> _unfreezeC
    :<|> freezeStatusC
    :<|> setConfigC
    :<|> _applyPresetC
    :<|> _resetConfigC
    :<|> _setPayPeriodC
    :<|> getAuditLogC
    :<|> createCheckpointC
    :<|> commitCheckpointC
    :<|> _rollbackCheckpointC
    :<|> _exportC
    :<|> _importC
    :<|> createAbsenceTypeC
    :<|> _deleteAbsenceTypeC
    :<|> _setAbsenceAllowanceC
    :<|> listUsersC
    :<|> _createUserC
    :<|> _deleteUserC
    -- Hint sessions
    :<|> _listHintsC
    :<|> _addHintC
    :<|> _revertHintC
    :<|> _applyHintsC
    :<|> _rebaseHintsC
    = client api

-- -----------------------------------------------------------------
-- RPC client functions derived from the RPC API type
-- -----------------------------------------------------------------

rpcCreateSkillC    :: CreateSkillReq -> ClientM RpcOk
_rpcDeleteSkillC   :: RpcSkillId -> ClientM RpcOk
rpcListSkillsC     :: RpcEmpty -> ClientM [(SkillId, Skill)]
_rpcCreateStationC :: CreateStationReq -> ClientM RpcOk
_rpcDeleteStationC :: RpcStationId -> ClientM RpcOk
_rpcSetStationHoursC :: RpcStationHours -> ClientM RpcOk
_rpcCloseStationDayC :: SetStationClosureReq' -> ClientM RpcOk
_rpcListStationsC  :: RpcEmpty -> ClientM [(Int, String)]
rpcCreateShiftC    :: CreateShiftReq -> ClientM RpcOk
rpcDeleteShiftC    :: RpcShiftName -> ClientM RpcOk
rpcListShiftsC     :: RpcEmpty -> ClientM [ShiftDef]
_rpcSetWorkerHoursC :: RpcWorkerHours -> ClientM RpcOk
_rpcSetWorkerOvertimeC :: RpcWorkerOvertime -> ClientM RpcOk
_rpcSetWorkerPrefsC :: RpcWorkerPrefs -> ClientM RpcOk
_rpcSetWorkerVarietyC :: RpcWorkerVariety -> ClientM RpcOk
_rpcSetWorkerShiftPrefsC :: RpcWorkerShiftPrefs -> ClientM RpcOk
_rpcSetWorkerWeekendOnlyC :: RpcWorkerWeekendOnly -> ClientM RpcOk
_rpcSetWorkerSeniorityC :: RpcWorkerSeniority -> ClientM RpcOk
_rpcAddCrossTrainingC :: RpcWorkerCrossTraining -> ClientM RpcOk
_rpcSetEmploymentStatusC :: RpcWorkerEmploymentStatus -> ClientM RpcOk
_rpcSetOvertimeModelC :: RpcWorkerOvertimeModel -> ClientM RpcOk
_rpcSetPayTrackingC :: RpcWorkerPayTracking -> ClientM RpcOk
_rpcSetTempC :: RpcWorkerTemp -> ClientM RpcOk
_rpcGrantSkillC :: RpcWorkerSkill -> ClientM RpcOk
_rpcRevokeSkillC :: RpcWorkerSkill -> ClientM RpcOk
_rpcAvoidPairingC :: RpcWorkerPairing -> ClientM RpcOk
_rpcPreferPairingC :: RpcWorkerPairing -> ClientM RpcOk
_rpcAddPinC :: PinnedAssignment -> ClientM RpcOk
_rpcRemovePinC :: PinnedAssignment -> ClientM RpcOk
_rpcListPinsC :: RpcEmpty -> ClientM [PinnedAssignment]
_rpcCreateDraftC :: CreateDraftReq -> ClientM DraftCreatedResp
_rpcListDraftsC :: RpcEmpty -> ClientM [DraftInfo]
_rpcViewDraftC :: RpcDraftId -> ClientM DraftInfo
_rpcGenerateDraftC :: RpcDraftGenerate -> ClientM ScheduleResult
_rpcCommitDraftC :: RpcDraftCommit -> ClientM RpcOk
_rpcDiscardDraftC :: RpcDraftId -> ClientM RpcOk
_rpcListSchedulesC :: RpcEmpty -> ClientM [String]
_rpcViewScheduleC :: RpcScheduleName -> ClientM Schedule
_rpcDeleteScheduleC :: RpcScheduleName -> ClientM RpcOk
_rpcViewCalendarC :: RpcDateRange -> ClientM Schedule
_rpcCalendarHistoryC :: RpcEmpty -> ClientM [CalendarCommit]
_rpcUnfreezeC :: UnfreezeReq -> ClientM RpcOk
_rpcFreezeStatusC :: RpcEmpty -> ClientM FreezeStatusResp
rpcShowConfigC :: RpcEmpty -> ClientM [(String, Double)]
rpcSetConfigC :: RpcConfigSet -> ClientM RpcOk
_rpcApplyPresetC :: RpcPresetName -> ClientM RpcOk
_rpcResetConfigC :: RpcEmpty -> ClientM RpcOk
_rpcSetPayPeriodC :: SetPayPeriodReq -> ClientM RpcOk
_rpcListAuditC :: RpcEmpty -> ClientM [AuditEntry]
_rpcCreateCheckpointC :: CreateCheckpointReq -> ClientM RpcOk
_rpcCommitCheckpointC :: RpcCheckpointName -> ClientM RpcOk
_rpcRollbackCheckpointC :: RpcCheckpointName -> ClientM RpcOk
_rpcExportAllC :: RpcEmpty -> ClientM ExportResp
_rpcImportDataC :: ImportReq -> ClientM ImportResp
_rpcCreateAbsenceTypeC :: CreateAbsenceTypeReq -> ClientM RpcOk
_rpcDeleteAbsenceTypeC :: RpcAbsenceTypeId -> ClientM RpcOk
_rpcSetAllowanceC :: RpcSetAllowance -> ClientM RpcOk
_rpcRequestAbsenceC :: RequestAbsenceReq -> ClientM AbsenceCreatedResp
_rpcApproveAbsenceC :: RpcAbsenceId -> ClientM RpcOk
_rpcRejectAbsenceC :: RpcAbsenceId -> ClientM RpcOk
_rpcListPendingAbsencesC :: RpcEmpty -> ClientM [AbsenceRequest]
_rpcCreateUserC :: CreateUserReq -> ClientM RpcOk
_rpcListUsersC :: RpcEmpty -> ClientM [User]
_rpcDeleteUserC :: RpcUsername -> ClientM RpcOk
_rpcAddHintC :: AddHintReq -> ClientM [Hint]
_rpcRevertHintC :: HintSessionRef -> ClientM [Hint]
_rpcListHintsC :: HintSessionRef -> ClientM [Hint]
_rpcApplyHintsC :: HintSessionRef -> ClientM RpcOk
_rpcRebaseHintsC :: HintSessionRef -> ClientM RebaseResultResp
rpcCreateSessionC :: RpcSessionCreate -> ClientM RpcSessionResp
rpcResumeSessionC :: RpcSessionCreate -> ClientM RpcSessionResp

rpcCreateSkillC
    :<|> _rpcDeleteSkillC
    :<|> rpcListSkillsC
    :<|> _rpcCreateStationC
    :<|> _rpcDeleteStationC
    :<|> _rpcSetStationHoursC
    :<|> _rpcCloseStationDayC
    :<|> _rpcListStationsC
    :<|> rpcCreateShiftC
    :<|> rpcDeleteShiftC
    :<|> rpcListShiftsC
    :<|> _rpcSetWorkerHoursC
    :<|> _rpcSetWorkerOvertimeC
    :<|> _rpcSetWorkerPrefsC
    :<|> _rpcSetWorkerVarietyC
    :<|> _rpcSetWorkerShiftPrefsC
    :<|> _rpcSetWorkerWeekendOnlyC
    :<|> _rpcSetWorkerSeniorityC
    :<|> _rpcAddCrossTrainingC
    :<|> _rpcSetEmploymentStatusC
    :<|> _rpcSetOvertimeModelC
    :<|> _rpcSetPayTrackingC
    :<|> _rpcSetTempC
    :<|> _rpcGrantSkillC
    :<|> _rpcRevokeSkillC
    :<|> _rpcAvoidPairingC
    :<|> _rpcPreferPairingC
    :<|> _rpcAddPinC
    :<|> _rpcRemovePinC
    :<|> _rpcListPinsC
    :<|> _rpcCreateDraftC
    :<|> _rpcListDraftsC
    :<|> _rpcViewDraftC
    :<|> _rpcGenerateDraftC
    :<|> _rpcCommitDraftC
    :<|> _rpcDiscardDraftC
    :<|> _rpcListSchedulesC
    :<|> _rpcViewScheduleC
    :<|> _rpcDeleteScheduleC
    :<|> _rpcViewCalendarC
    :<|> _rpcCalendarHistoryC
    :<|> _rpcUnfreezeC
    :<|> _rpcFreezeStatusC
    :<|> rpcShowConfigC
    :<|> rpcSetConfigC
    :<|> _rpcApplyPresetC
    :<|> _rpcResetConfigC
    :<|> _rpcSetPayPeriodC
    :<|> _rpcListAuditC
    :<|> _rpcCreateCheckpointC
    :<|> _rpcCommitCheckpointC
    :<|> _rpcRollbackCheckpointC
    :<|> _rpcExportAllC
    :<|> _rpcImportDataC
    :<|> _rpcCreateAbsenceTypeC
    :<|> _rpcDeleteAbsenceTypeC
    :<|> _rpcSetAllowanceC
    :<|> _rpcRequestAbsenceC
    :<|> _rpcApproveAbsenceC
    :<|> _rpcRejectAbsenceC
    :<|> _rpcListPendingAbsencesC
    :<|> _rpcCreateUserC
    :<|> _rpcListUsersC
    :<|> _rpcDeleteUserC
    :<|> _rpcAddHintC
    :<|> _rpcRevertHintC
    :<|> _rpcListHintsC
    :<|> _rpcApplyHintsC
    :<|> _rpcRebaseHintsC
    :<|> rpcCreateSessionC
    :<|> rpcResumeSessionC
    = client rpcApi

-- -----------------------------------------------------------------
-- Test helper
-- -----------------------------------------------------------------

testDbPath :: String
testDbPath = "/tmp/manars-kitchen-test-api.db"

withTestApp :: (ClientEnv -> IO ()) -> IO ()
withTestApp action = do
    exists <- doesFileExist testDbPath
    if exists then removeFile testDbPath else pure ()
    (_conn, repo) <- mkSQLiteRepo testDbPath
    let app = serve fullApi (fullServer repo)
    mgr <- newManager defaultManagerSettings
    testWithApplication (pure app) $ \port -> do
        baseUrl <- parseBaseUrl "http://localhost"
        let env = mkClientEnv mgr baseUrl { baseUrlPort = port }
        action env
    removeFile testDbPath

-- | Like withTestApp but also sets up a user and basic data.
withSeededApp :: (Repository -> ClientEnv -> IO ()) -> IO ()
withSeededApp action = do
    exists <- doesFileExist testDbPath
    if exists then removeFile testDbPath else pure ()
    (_conn, repo) <- mkSQLiteRepo testDbPath
    -- Create a test user (needed for absences)
    _ <- register repo "testadmin" "password" Admin (WorkerId 1)
    -- Set up an absence type
    repoSaveAbsenceCtx repo emptyAbsenceContext
        { acTypes = Map.singleton (AbsenceTypeId 1) (AbsenceType "Vacation" True)
        , acYearlyAllowance = Map.singleton (WorkerId 1, AbsenceTypeId 1) 10
        }
    let app = serve fullApi (fullServer repo)
    mgr <- newManager defaultManagerSettings
    testWithApplication (pure app) $ \port -> do
        baseUrl <- parseBaseUrl "http://localhost"
        let env = mkClientEnv mgr baseUrl { baseUrlPort = port }
        action repo env
    removeFile testDbPath

-- | Like withSeededApp but provides both ClientEnv and RpcEnv for CLI remote mode tests.
withRemoteApp :: (Repository -> ClientEnv -> RpcEnv -> IO ()) -> IO ()
withRemoteApp action = do
    exists <- doesFileExist testDbPath
    if exists then removeFile testDbPath else pure ()
    (_conn, repo) <- mkSQLiteRepo testDbPath
    _ <- register repo "testadmin" "password" Admin (WorkerId 1)
    repoSaveAbsenceCtx repo emptyAbsenceContext
        { acTypes = Map.singleton (AbsenceTypeId 1) (AbsenceType "Vacation" True)
        , acYearlyAllowance = Map.singleton (WorkerId 1, AbsenceTypeId 1) 10
        }
    let app = serve fullApi (fullServer repo)
    mgr <- newManager defaultManagerSettings
    testWithApplication (pure app) $ \port -> do
        baseUrl <- parseBaseUrl "http://localhost"
        let clientEnv = mkClientEnv mgr baseUrl { baseUrlPort = port }
            rpcEnv = RpcEnv clientEnv 0 1 Admin
        action repo clientEnv rpcEnv
    removeFile testDbPath

-- | Assert a ClientError is a FailureResponse with the given status code.
shouldFailWith :: (Show a) => Either ClientError a -> Int -> Expectation
shouldFailWith (Left (FailureResponse _ resp)) expected =
    statusCode (responseStatusCode resp) `shouldBe` expected
shouldFailWith (Left err) expected =
    expectationFailure $ "Expected status " ++ show expected
                      ++ " but got error: " ++ show err
shouldFailWith (Right val) expected =
    expectationFailure $ "Expected status " ++ show expected
                      ++ " but got success: " ++ show val

apr :: Int -> Day
apr d = fromGregorian 2026 4 d

may :: Int -> Day
may d = fromGregorian 2026 5 d

-- -----------------------------------------------------------------
-- Specs
-- -----------------------------------------------------------------

spec :: Spec
spec = do
    describe "Read endpoints on empty DB" $ do
        it "GET /api/skills returns empty list" $ withTestApp $ \env -> do
            result <- runClientM listSkillsC env
            result `shouldBe` Right []

        it "GET /api/stations returns empty list" $ withTestApp $ \env -> do
            result <- runClientM listStationsC env
            result `shouldBe` Right []

        it "GET /api/shifts returns empty list" $ withTestApp $ \env -> do
            result <- runClientM listShiftsC env
            result `shouldBe` Right []

        it "GET /api/schedules returns empty list" $ withTestApp $ \env -> do
            result <- runClientM listSchedulesC env
            result `shouldBe` Right []

        it "GET /api/drafts returns empty list" $ withTestApp $ \env -> do
            result <- runClientM listDraftsC env
            result `shouldBe` Right []

        it "GET /api/absences/pending returns empty list" $ withTestApp $ \env -> do
            result <- runClientM listPendingAbsencesC env
            result `shouldBe` Right []

        it "GET /api/calendar/history returns empty list" $ withTestApp $ \env -> do
            Right history <- runClientM listCalendarHistoryC env
            length history `shouldBe` 0

        it "GET /api/config returns config params" $ withTestApp $ \env -> do
            result <- runClientM getConfigC env
            case result of
                Left err -> expectationFailure (show err)
                Right params -> length params `shouldSatisfy` (> 0)

    describe "Error responses" $ do
        it "GET /api/schedules/:name returns 404 for missing schedule" $
            withTestApp $ \env -> do
                result <- runClientM (getScheduleC "nonexistent") env
                result `shouldFailWith` 404

        it "GET /api/drafts/:id returns 404 for missing draft" $
            withTestApp $ \env -> do
                result <- runClientM (getDraftC 999) env
                result `shouldFailWith` 404

        it "GET /api/calendar without params returns 400" $
            withTestApp $ \env -> do
                result <- runClientM (getCalendarC Nothing Nothing) env
                result `shouldFailWith` 400

    describe "Draft lifecycle" $ do
        it "create → get → discard" $ withTestApp $ \env -> do
            -- Create
            Right resp <- runClientM (createDraftC (CreateDraftReq (apr 6) (apr 12))) env
            let did = dcrId resp
            -- Get
            Right draft <- runClientM (getDraftC did) env
            draft `shouldSatisfy` const True
            -- Discard
            Right _ <- runClientM (discardDraftC did) env
            -- Verify gone
            result <- runClientM (getDraftC did) env
            result `shouldFailWith` 404

        it "overlapping draft returns 409" $ withTestApp $ \env -> do
            Right _ <- runClientM (createDraftC (CreateDraftReq (apr 6) (apr 12))) env
            result <- runClientM (createDraftC (CreateDraftReq (apr 10) (apr 16))) env
            result `shouldFailWith` 409

        it "generate populates schedule" $ withSeededApp $ \repo env -> do
            -- Add a skill, station, and worker so the scheduler has something to do
            SW.addSkill repo (SkillId 1) "grill" ""
            SW.addStation repo (StationId 1) "grill"
            SW.grantWorkerSkill repo (WorkerId 1) (SkillId 1)
            SW.setStationRequiredSkills repo (StationId 1)
                (Set.singleton (SkillId 1))
            SW.setStationHours repo (StationId 1) 9 12
            -- Create and generate
            Right resp <- runClientM (createDraftC (CreateDraftReq (may 4) (may 10))) env
            let did = dcrId resp
            Right _ <- runClientM
                (generateDraftC did (GenerateDraftReq [1])) env
            -- Clean up
            _ <- runClientM (discardDraftC did) env
            pure ()

        it "commit moves assignments to calendar" $ withSeededApp $ \_ env -> do
            -- Create draft
            Right resp <- runClientM (createDraftC (CreateDraftReq (may 4) (may 10))) env
            let did = dcrId resp
            -- Commit
            Right _ <- runClientM
                (commitDraftC did (CommitDraftReq "test commit")) env
            -- Draft should be gone
            result <- runClientM (getDraftC did) env
            result `shouldFailWith` 404
            -- Calendar history should have an entry
            Right history <- runClientM listCalendarHistoryC env
            length history `shouldSatisfy` (> 0)

    describe "Calendar" $ do
        it "returns assignments for a date range" $ withTestApp $ \env -> do
            Right (Schedule s) <- runClientM (getCalendarC (Just (apr 6)) (Just (apr 12))) env
            -- Empty DB, so no assignments
            Set.size s `shouldBe` 0

    describe "Absence lifecycle" $ do
        it "request → list pending → approve → list pending empty" $
            withSeededApp $ \_ env -> do
                -- Request
                Right resp <- runClientM (requestAbsenceC
                    (RequestAbsenceReq 1 1 (may 1) (may 3))) env
                let aid = acrId resp
                -- List pending
                Right reqs <- runClientM listPendingAbsencesC env
                length reqs `shouldBe` 1
                -- Approve
                Right _ <- runClientM (approveAbsenceC aid) env
                -- List pending again (should be empty now)
                Right reqs' <- runClientM listPendingAbsencesC env
                length reqs' `shouldBe` 0

        it "approve nonexistent absence returns 404" $
            withTestApp $ \env -> do
                result <- runClientM (approveAbsenceC 999) env
                result `shouldFailWith` 404

        it "reject nonexistent absence returns 404" $
            withTestApp $ \env -> do
                result <- runClientM (rejectAbsenceC 999) env
                result `shouldFailWith` 404

    -- -----------------------------------------------------------------
    -- New endpoint tests
    -- -----------------------------------------------------------------

    describe "Skill CRUD" $ do
        it "create and list skill" $ withTestApp $ \env -> do
            Right _ <- runClientM (createSkillC (CreateSkillReq 1 "grill" "Grill skills")) env
            Right skills <- runClientM listSkillsC env
            length skills `shouldBe` 1

        it "create and delete skill" $ withTestApp $ \env -> do
            Right _ <- runClientM (createSkillC (CreateSkillReq 1 "grill" "Grill skills")) env
            Right _ <- runClientM (deleteSkillC 1) env
            Right skills <- runClientM listSkillsC env
            length skills `shouldBe` 0

    describe "Station CRUD" $ do
        it "create and list station" $ withTestApp $ \env -> do
            Right _ <- runClientM (createStationC (CreateStationReq 1 "grill")) env
            Right stations <- runClientM listStationsC env
            length stations `shouldBe` 1

        it "set station hours" $ withTestApp $ \env -> do
            Right _ <- runClientM (createStationC (CreateStationReq 1 "grill")) env
            Right _ <- runClientM (setStationHoursC 1 (SetStationHoursReq 9 17)) env
            pure ()  -- no error means success

    describe "Shift CRUD" $ do
        it "create and list shift" $ withTestApp $ \env -> do
            Right _ <- runClientM (createShiftC (CreateShiftReq "morning" 6 14)) env
            Right shifts <- runClientM listShiftsC env
            length shifts `shouldBe` 1

        it "create and delete shift" $ withTestApp $ \env -> do
            Right _ <- runClientM (createShiftC (CreateShiftReq "morning" 6 14)) env
            Right _ <- runClientM (deleteShiftC "morning") env
            Right shifts <- runClientM listShiftsC env
            length shifts `shouldBe` 0

    describe "Worker configuration" $ do
        it "set worker hours" $ withSeededApp $ \_ env -> do
            Right _ <- runClientM (setWorkerHoursC 1 (SetWorkerHoursReq 40)) env
            pure ()

        it "grant and revoke worker skill" $ withSeededApp $ \repo env -> do
            SW.addSkill repo (SkillId 1) "grill" ""
            Right _ <- runClientM (grantWorkerSkillC 1 1) env
            Right _ <- runClientM (revokeWorkerSkillC 1 1) env
            pure ()

    describe "Config writes" $ do
        it "set config value" $ withTestApp $ \env -> do
            Right _ <- runClientM (setConfigC "shift-pref-bonus" (SetConfigReq 5.0)) env
            Right params <- runClientM getConfigC env
            let val = lookup "shift-pref-bonus" params
            val `shouldBe` Just 5.0

    describe "Audit log" $ do
        it "returns audit entries" $ withTestApp $ \env -> do
            Right entries <- runClientM getAuditLogC env
            entries `shouldSatisfy` const True  -- just check it doesn't fail

    describe "Freeze status" $ do
        it "returns freeze line" $ withTestApp $ \env -> do
            Right resp <- runClientM freezeStatusC env
            fsFreezeLine resp `shouldSatisfy` const True

    describe "Absence type management" $ do
        it "create absence type" $ withTestApp $ \env -> do
            Right _ <- runClientM (createAbsenceTypeC
                (CreateAbsenceTypeReq 1 "vacation" True)) env
            pure ()

    describe "User management" $ do
        it "create and list users" $ withSeededApp $ \_ env -> do
            Right users <- runClientM listUsersC env
            length users `shouldSatisfy` (>= 1)  -- seeded app creates testadmin

    describe "Checkpoints" $ do
        it "create and commit checkpoint" $ withTestApp $ \env -> do
            Right _ <- runClientM (createCheckpointC (CreateCheckpointReq "test-cp")) env
            Right _ <- runClientM (commitCheckpointC "test-cp") env
            pure ()

    -- -----------------------------------------------------------------
    -- RPC endpoint tests
    -- -----------------------------------------------------------------

    describe "RPC Skill CRUD" $ do
        it "create and list skills via RPC" $ withTestApp $ \env -> do
            Right _ <- runClientM (rpcCreateSkillC (CreateSkillReq 1 "grill" "Grill skills")) env
            Right skills <- runClientM (rpcListSkillsC RpcEmpty) env
            length skills `shouldBe` 1

    describe "RPC Shift CRUD" $ do
        it "create and list shifts via RPC" $ withTestApp $ \env -> do
            Right _ <- runClientM (rpcCreateShiftC (CreateShiftReq "morning" 6 14)) env
            Right shifts <- runClientM (rpcListShiftsC RpcEmpty) env
            length shifts `shouldBe` 1

        it "create and delete shift via RPC" $ withTestApp $ \env -> do
            Right _ <- runClientM (rpcCreateShiftC (CreateShiftReq "morning" 6 14)) env
            Right _ <- runClientM (rpcDeleteShiftC (RpcShiftName "morning")) env
            Right shifts <- runClientM (rpcListShiftsC RpcEmpty) env
            length shifts `shouldBe` 0

    describe "RPC Config" $ do
        it "show and set config via RPC" $ withTestApp $ \env -> do
            Right _ <- runClientM (rpcSetConfigC (RpcConfigSet "shift-pref-bonus" 5.0)) env
            Right params <- runClientM (rpcShowConfigC RpcEmpty) env
            let val = lookup "shift-pref-bonus" params
            val `shouldBe` Just 5.0

    describe "RPC Session management" $ do
        it "create session" $ withSeededApp $ \_ env -> do
            Right resp <- runClientM (rpcCreateSessionC (RpcSessionCreate 1)) env
            rsrSessionId resp `shouldSatisfy` (> 0)

        it "resume session returns same session" $ withSeededApp $ \_ env -> do
            Right resp1 <- runClientM (rpcCreateSessionC (RpcSessionCreate 1)) env
            Right resp2 <- runClientM (rpcResumeSessionC (RpcSessionCreate 1)) env
            rsrSessionId resp2 `shouldBe` rsrSessionId resp1

        it "resume creates new session if none active" $ withSeededApp $ \_ env -> do
            Right resp <- runClientM (rpcResumeSessionC (RpcSessionCreate 1)) env
            rsrSessionId resp `shouldSatisfy` (> 0)

    -- -----------------------------------------------------------------
    -- CLI remote mode integration tests
    -- -----------------------------------------------------------------

    describe "CLI remote mode" $ do
        it "skill create via dispatchCommand creates server-side skill" $
            withRemoteApp $ \_ env rpc -> do
                dispatchCommand rpc (SkillCreate 1 "grill")
                Right skills <- runClientM (rpcListSkillsC RpcEmpty) env
                length skills `shouldBe` 1

        it "station add via dispatchCommand creates server-side station" $
            withRemoteApp $ \_ env rpc -> do
                dispatchCommand rpc (StationAdd 1 "kitchen")
                Right stations <- runClientM (_rpcListStationsC RpcEmpty) env
                length stations `shouldBe` 1

        it "shift create/delete via dispatchCommand" $
            withRemoteApp $ \_ env rpc -> do
                dispatchCommand rpc (ShiftCreate "morning" 6 14)
                Right shifts1 <- runClientM (rpcListShiftsC RpcEmpty) env
                length shifts1 `shouldBe` 1
                dispatchCommand rpc (ShiftDelete "morning")
                Right shifts2 <- runClientM (rpcListShiftsC RpcEmpty) env
                length shifts2 `shouldBe` 0

        it "config set via dispatchCommand changes config" $
            withRemoteApp $ \_ env rpc -> do
                dispatchCommand rpc (ConfigSet "shift-pref-bonus" "5.0")
                Right params <- runClientM (rpcShowConfigC RpcEmpty) env
                lookup "shift-pref-bonus" params `shouldBe` Just 5.0

        it "RPC commands produce audit entries with source=rpc" $
            withRemoteApp $ \_ env rpc -> do
                dispatchCommand rpc (SkillCreate 1 "grill")
                dispatchCommand rpc (StationAdd 1 "kitchen")
                Right entries <- runClientM (_rpcListAuditC RpcEmpty) env
                length entries `shouldSatisfy` (>= 2)
                all (\e -> aeSource e == "rpc") entries `shouldBe` True
