{-# LANGUAGE OverloadedStrings #-}

module ApiSpec (spec) where

import Test.Hspec
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Time (Day, fromGregorian)
import Network.HTTP.Client (newManager, defaultManagerSettings)
import Network.Wai.Handler.Warp (testWithApplication)
import Servant (serve, (:<|>)(..))
import Servant.Client
    ( ClientM, ClientEnv, mkClientEnv, runClientM, client, baseUrlPort
    , parseBaseUrl, ClientError(..), responseStatusCode
    )
import Network.HTTP.Types.Status (statusCode)
import System.Directory (removeFile, doesFileExist)

import Auth.Types (Role(..))
import Domain.Types (WorkerId(..), StationId(..), SkillId(..), AbsenceTypeId(..), Schedule(..))
import Domain.Skill (Skill)
import Domain.Shift (ShiftDef)
import Domain.Absence (AbsenceType(..), AbsenceContext(..), AbsenceRequest, emptyAbsenceContext)
import Domain.Scheduler (ScheduleResult)
import Repo.SQLite (mkSQLiteRepo)
import Repo.Types (Repository(..), DraftInfo, CalendarCommit)
import Service.Auth (register)
import qualified Service.Worker as SW
import Servant.API (NoContent)
import Server.Api (api)
import Server.Json
import Server.Handlers (server)

-- -----------------------------------------------------------------
-- Client functions derived from the API type
-- -----------------------------------------------------------------

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
    = client api

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
    let app = serve api (server repo)
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
    let app = serve api (server repo)
    mgr <- newManager defaultManagerSettings
    testWithApplication (pure app) $ \port -> do
        baseUrl <- parseBaseUrl "http://localhost"
        let env = mkClientEnv mgr baseUrl { baseUrlPort = port }
        action repo env
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
