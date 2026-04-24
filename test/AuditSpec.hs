{-# LANGUAGE OverloadedStrings #-}

module AuditSpec (spec) where

import Test.Hspec
import System.Directory (removeFile, doesFileExist)

import Audit.CommandMeta
import Repo.SQLite (mkSQLiteRepo)
import Repo.Types (Repository(..), AuditEntry(..))
import CLI.Commands (parseCommand)
import CLI.App (isMutating)

spec :: Spec
spec = do
    describe "classify" $ do
        -- 8.1: One test per command group

        describe "schedule commands" $ do
            it "classifies schedule create as mutating" $ do
                let m = classify "schedule create week1 2026-04-06"
                cmEntityType m `shouldBe` Just "schedule"
                cmOperation m `shouldBe` Just "create"
                cmIsMutation m `shouldBe` True

            it "classifies schedule list as non-mutating" $ do
                let m = classify "schedule list"
                cmEntityType m `shouldBe` Just "schedule"
                cmOperation m `shouldBe` Just "list"
                cmIsMutation m `shouldBe` False

        describe "station commands" $ do
            it "classifies station add" $ do
                let m = classify "station add grill"
                cmEntityType m `shouldBe` Just "station"
                cmOperation m `shouldBe` Just "add"
                cmEntityId m `shouldBe` Nothing
                cmIsMutation m `shouldBe` True

            it "classifies station require-skill with two IDs" $ do
                let m = classify "station require-skill 2 5"
                cmEntityType m `shouldBe` Just "station"
                cmOperation m `shouldBe` Just "require-skill"
                cmEntityId m `shouldBe` Just 2
                cmTargetId m `shouldBe` Just 5

        describe "skill commands" $ do
            it "classifies skill create" $ do
                let m = classify "skill create pastry"
                cmEntityType m `shouldBe` Just "skill"
                cmOperation m `shouldBe` Just "create"
                cmEntityId m `shouldBe` Nothing
                cmIsMutation m `shouldBe` True

            it "classifies skill implication with two IDs" $ do
                cmEntityId (classify "skill implication 1 2") `shouldBe` Just 1
                cmTargetId (classify "skill implication 1 2") `shouldBe` Just 2

        describe "worker commands" $ do
            it "classifies worker grant-skill as two-entity mutating" $ do
                let m = classify "worker grant-skill 3 5"
                cmEntityType m `shouldBe` Just "worker"
                cmOperation m `shouldBe` Just "grant-skill"
                cmEntityId m `shouldBe` Just 3
                cmTargetId m `shouldBe` Just 5
                cmIsMutation m `shouldBe` True

            it "classifies worker set-hours with entity ID" $ do
                let m = classify "worker set-hours 3 40"
                cmEntityType m `shouldBe` Just "worker"
                cmOperation m `shouldBe` Just "set-hours"
                cmEntityId m `shouldBe` Just 3

        describe "shift commands" $ do
            it "classifies shift create as mutating" $ do
                let m = classify "shift create morning 6 14"
                cmEntityType m `shouldBe` Just "shift"
                cmOperation m `shouldBe` Just "create"
                cmIsMutation m `shouldBe` True

        describe "absence commands" $ do
            it "classifies absence request with dates" $ do
                let m = classify "absence request 1 3 2026-04-10 2026-04-10"
                cmEntityType m `shouldBe` Just "absence"
                cmOperation m `shouldBe` Just "request"
                cmEntityId m `shouldBe` Just 1
                cmTargetId m `shouldBe` Just 3
                cmDateFrom m `shouldBe` Just "2026-04-10"
                cmDateTo m `shouldBe` Just "2026-04-10"

            it "classifies absence approve with ID" $ do
                let m = classify "absence approve 7"
                cmEntityType m `shouldBe` Just "absence"
                cmOperation m `shouldBe` Just "approve"
                cmEntityId m `shouldBe` Just 7

        describe "user commands" $ do
            it "classifies user create as mutating" $ do
                let m = classify "user create alice pass admin"
                cmEntityType m `shouldBe` Just "user"
                cmOperation m `shouldBe` Just "create"
                cmIsMutation m `shouldBe` True

        describe "config commands" $ do
            it "classifies config set-pay-period" $ do
                let m = classify "config set-pay-period biweekly 2026-04-06"
                cmEntityType m `shouldBe` Just "config"
                cmOperation m `shouldBe` Just "set-pay-period"
                cmIsMutation m `shouldBe` True

            it "classifies config show as non-mutating" $ do
                cmIsMutation (classify "config show") `shouldBe` False

        describe "draft commands" $ do
            it "classifies draft create with dates" $ do
                let m = classify "draft create 2026-04-13 2026-04-19"
                cmEntityType m `shouldBe` Just "draft"
                cmOperation m `shouldBe` Just "create"
                cmDateFrom m `shouldBe` Just "2026-04-13"
                cmDateTo m `shouldBe` Just "2026-04-19"
                cmIsMutation m `shouldBe` True

        describe "calendar commands" $ do
            it "classifies calendar commit with dates" $ do
                let m = classify "calendar commit week1 2026-04-06 2026-04-12 Initial schedule"
                cmEntityType m `shouldBe` Just "calendar"
                cmOperation m `shouldBe` Just "commit"
                cmDateFrom m `shouldBe` Just "2026-04-06"
                cmDateTo m `shouldBe` Just "2026-04-12"
                cmIsMutation m `shouldBe` True

        describe "pin commands" $ do
            it "classifies pin as mutating with IDs" $ do
                let m = classify "pin 1 2 Monday morning"
                cmEntityType m `shouldBe` Just "pin"
                cmOperation m `shouldBe` Just "add"
                cmEntityId m `shouldBe` Just 1
                cmTargetId m `shouldBe` Just 2
                cmIsMutation m `shouldBe` True

            it "classifies unpin" $ do
                let m = classify "unpin 1 2 Monday morning"
                cmEntityType m `shouldBe` Just "pin"
                cmOperation m `shouldBe` Just "remove"
                cmIsMutation m `shouldBe` True

        describe "what-if commands" $ do
            it "classifies what-if grant-skill as non-mutating" $ do
                let m = classify "what-if grant-skill 3 5"
                cmEntityType m `shouldBe` Just "what-if"
                cmOperation m `shouldBe` Just "grant-skill"
                cmEntityId m `shouldBe` Just 3
                cmTargetId m `shouldBe` Just 5
                cmIsMutation m `shouldBe` False

            it "classifies what-if apply as mutating" $ do
                let m = classify "what-if apply"
                cmEntityType m `shouldBe` Just "what-if"
                cmOperation m `shouldBe` Just "apply"
                cmIsMutation m `shouldBe` True

        describe "unknown commands" $ do
            it "returns default for unknown input" $ do
                let m = classify "foobar baz"
                cmEntityType m `shouldBe` Nothing
                cmIsMutation m `shouldBe` False

        describe "variadic commands" $ do
            it "captures station IDs in set-prefs params" $ do
                let m = classify "worker set-prefs 3 1 2 4"
                cmEntityType m `shouldBe` Just "worker"
                cmOperation m `shouldBe` Just "set-prefs"
                cmEntityId m `shouldBe` Just 3
                cmParams m `shouldBe` Just "[1,2,4]"
                cmIsMutation m `shouldBe` True

            it "captures shift names in set-shift-pref params" $ do
                let m = classify "worker set-shift-pref 3 morning afternoon"
                cmEntityType m `shouldBe` Just "worker"
                cmOperation m `shouldBe` Just "set-shift-pref"
                cmEntityId m `shouldBe` Just 3
                cmParams m `shouldBe` Just "[\"morning\",\"afternoon\"]"

    -- 8.2: render round-trip tests
    describe "render" $ do
        it "round-trips station add" $ do
            let m = classify "station add grill"
            render m `shouldBe` "station add"

        it "round-trips worker grant-skill" $ do
            render (classify "worker grant-skill 3 5") `shouldBe` "worker grant-skill 3 5"

        it "round-trips draft create with dates" $ do
            render (classify "draft create 2026-04-13 2026-04-19")
                `shouldBe` "draft create 2026-04-13 2026-04-19"

        it "renders from REST-originated metadata" $ do
            let meta = defaultMeta
                    { cmEntityType = Just "worker"
                    , cmOperation = Just "grant-skill"
                    , cmEntityId = Just 3
                    , cmTargetId = Just 5
                    }
            render meta `shouldBe` "worker grant-skill 3 5"

        it "renders with date range" $ do
            let meta = defaultMeta
                    { cmEntityType = Just "draft"
                    , cmOperation = Just "create"
                    , cmDateFrom = Just "2026-04-13"
                    , cmDateTo = Just "2026-04-19"
                    }
            render meta `shouldBe` "draft create 2026-04-13 2026-04-19"

        it "returns empty for incomplete metadata" $ do
            render defaultMeta `shouldBe` ""
            render (defaultMeta { cmEntityType = Just "worker" }) `shouldBe` ""

        it "reconstructs variadic args from params" $ do
            render (classify "worker set-prefs 3 1 2 4")
                `shouldBe` "worker set-prefs 3 1 2 4"

    -- 8.3: isMutation consistency property
    describe "isMutation consistency" $ do
        let testConsistency :: String -> Spec
            testConsistency cmdStr =
                it ("agrees for: " ++ cmdStr) $ do
                    let cmd = parseCommand cmdStr
                        meta = classify cmdStr
                    cmIsMutation meta `shouldBe` isMutating cmd

        -- Mutating commands
        testConsistency "station add grill"
        testConsistency "skill create pastry"
        testConsistency "worker grant-skill 3 5"
        testConsistency "worker set-hours 3 40"
        testConsistency "worker set-prefs 3 1 2 4"
        testConsistency "shift create morning 6 14"
        testConsistency "shift delete morning"
        testConsistency "absence approve 7"
        testConsistency "absence request 1 3 2026-04-10 2026-04-10"
        testConsistency "user create alice pass admin"
        testConsistency "config set foo bar"
        testConsistency "config set-pay-period biweekly 2026-04-06"
        testConsistency "pin 1 2 Monday morning"
        testConsistency "unpin 1 2 Monday morning"
        testConsistency "draft create 2026-04-13 2026-04-19"
        testConsistency "draft generate"
        testConsistency "draft commit"
        testConsistency "draft discard"
        testConsistency "what-if apply"
        testConsistency "import data.json"
        testConsistency "calendar unfreeze 2026-04-10"

        -- Non-mutating commands
        testConsistency "schedule list"
        testConsistency "schedule view week1"
        testConsistency "station list"
        testConsistency "skill list"
        testConsistency "worker info"
        testConsistency "shift list"
        testConsistency "config show"
        testConsistency "pin list"
        testConsistency "draft list"
        testConsistency "calendar view 2026-04-06 2026-04-12"
        testConsistency "calendar history"
        testConsistency "what-if grant-skill 3 5"
        testConsistency "what-if list"
        testConsistency "export data.json"
        testConsistency "audit"
        testConsistency "replay"
        testConsistency "help"
        testConsistency "quit"

    -- 8.4: Every mutating command has non-Nothing cmEntityType
    describe "mutating commands have entity type" $ do
        let mutatingCommands =
                [ "station add grill"
                , "station remove 1"
                , "skill create pastry"
                , "skill implication 1 2"
                , "worker grant-skill 3 5"
                , "worker set-hours 3 40"
                , "worker set-prefs 3 1 2"
                , "shift create morning 6 14"
                , "shift delete morning"
                , "absence-type create 1 vacation true"
                , "absence set-allowance 1 1 10"
                , "absence approve 7"
                , "absence request 1 3 2026-04-10 2026-04-10"
                , "user create alice pass admin"
                , "user delete 1"
                , "config set foo bar"
                , "config preset standard"
                , "config reset"
                , "config set-pay-period biweekly 2026-04-06"
                , "pin 1 2 Monday morning"
                , "unpin 1 2 Monday morning"
                , "import data.json"
                , "draft create 2026-04-13 2026-04-19"
                , "draft generate"
                , "draft commit"
                , "draft discard"
                , "calendar commit w1 2026-04-06 2026-04-12"
                , "calendar unfreeze 2026-04-10"
                , "what-if apply"
                , "assign sched 1 2 2026-04-06 8"
                , "unassign sched 1 2 2026-04-06 8"
                ]
        mapM_ (\cmdStr ->
            it ("has entity type for: " ++ cmdStr) $
                cmEntityType (classify cmdStr) `shouldSatisfy` (/= Nothing)
            ) mutatingCommands

    -- 8.5: Integration test
    describe "integration: log and read structured audit entries" $ do
        it "logs a command and reads back structured fields" $ withTestRepo $ \repo -> do
            repoLogCommand repo "admin" "skill create pastry"
            entries <- repoGetAuditLog repo
            case entries of
                [ae] -> do
                    aeCommand ae `shouldBe` Just "skill create pastry"
                    aeEntityType ae `shouldBe` Just "skill"
                    aeOperation ae `shouldBe` Just "create"
                    aeEntityId ae `shouldBe` Nothing
                    aeIsMutation ae `shouldBe` True
                    aeSource ae `shouldBe` "cli"
                _ -> expectationFailure $
                    "expected 1 entry, got " ++ show (length entries)

    -- 8.6: Legacy rows test
    describe "legacy rows with NULL structured fields" $ do
        it "reads legacy entries as AuditEntry with Nothing fields" $ withTestRepo $ \repo -> do
            -- Log an unrecognized command (structured fields will be NULL)
            repoLogCommand repo "admin" "foobar baz"
            entries <- repoGetAuditLog repo
            case entries of
                [ae] -> do
                    aeCommand ae `shouldBe` Just "foobar baz"
                    aeEntityType ae `shouldBe` Nothing
                    aeOperation ae `shouldBe` Nothing
                    aeEntityId ae `shouldBe` Nothing
                    aeIsMutation ae `shouldBe` False
                _ -> expectationFailure $
                    "expected 1 entry, got " ++ show (length entries)

-- | Helper: create a temporary SQLite repo for testing.
withTestRepo :: (Repository -> IO ()) -> IO ()
withTestRepo action = do
    let path = "/tmp/manars-kitchen-test-audit.db"
    exists <- doesFileExist path
    if exists then removeFile path else return ()
    (_, repo) <- mkSQLiteRepo path
    action repo
    removeFile path
