module HintIntegrationSpec (spec) where

import Test.Hspec
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Time (TimeOfDay(..), fromGregorian)

import Domain.Types
import Domain.Hint (Hint(..), Session(..), newSession, addHint, revertHint, sessionStep)
import Domain.Scheduler (SchedulerContext(..), ScheduleResult(..))
import Domain.Skill (SkillContext(..))
import Domain.Worker (WorkerContext(..))
import Domain.Absence (emptyAbsenceContext)
import Domain.SchedulerConfig (defaultConfig)
import CLI.Commands (Command(..), parseCommand)
import CLI.Display (displayHintDiff, displayHintList)

-- -----------------------------------------------------------------
-- Test fixtures
-- -----------------------------------------------------------------

w1, w2 :: WorkerId
w1 = WorkerId 1
w2 = WorkerId 2

sk1, sk2 :: SkillId
sk1 = SkillId 1
sk2 = SkillId 2

st1, st2 :: StationId
st1 = StationId 1
st2 = StationId 2

testSlot :: Slot
testSlot = Slot (fromGregorian 2026 5 4) (TimeOfDay 9 0 0) 3600

testSlot2 :: Slot
testSlot2 = Slot (fromGregorian 2026 5 5) (TimeOfDay 9 0 0) 3600

testSkillCtx :: SkillContext
testSkillCtx = SkillContext
    { scWorkerSkills = Map.fromList
        [ (w1, Set.fromList [sk1, sk2])
        , (w2, Set.singleton sk2)
        ]
    , scStationRequires = Map.fromList
        [ (st1, Set.singleton sk1)
        , (st2, Set.singleton sk2)
        ]
    , scSkillImplies = Map.empty
    , scAllStations = Set.fromList [st1, st2]
    , scStationHours = Map.empty
    , scMultiStationHours = Map.empty
    }

testWorkerCtx :: WorkerContext
testWorkerCtx = WorkerContext
    { wcMaxPeriodHours = Map.fromList [(w1, 40*3600), (w2, 40*3600)]
    , wcOvertimeOptIn = Set.empty
    , wcStationPrefs = Map.empty
    , wcPrefersVariety = Set.empty
    , wcShiftPrefs = Map.empty
    , wcWeekendOnly = Set.empty
    , wcSeniority = Map.empty
    , wcCrossTraining = Map.empty
    , wcAvoidPairing = Map.empty
    , wcPreferPairing = Map.empty
    , wcOvertimeModel = Map.empty
    , wcPayPeriodTracking = Map.empty
    , wcIsTemp = Set.empty
    }

testCtx :: SchedulerContext
testCtx = SchedulerContext
    { schSkillCtx = testSkillCtx
    , schWorkerCtx = testWorkerCtx
    , schAbsenceCtx = emptyAbsenceContext
    , schSlots = [testSlot, testSlot2]
    , schWorkers = Set.fromList [w1, w2]
    , schClosedSlots = Set.empty
    , schShifts = []
    , schPrevWeekendWorkers = Set.empty
    , schConfig = defaultConfig
    , schPeriodBounds = (fromGregorian 2026 5 4, fromGregorian 2026 5 11)
    , schCalendarHours = Map.empty
    }

wNames :: Map.Map WorkerId String
wNames = Map.fromList [(w1, "alice"), (w2, "bob")]

sNames :: Map.Map StationId String
sNames = Map.fromList [(st1, "grill"), (st2, "prep")]

skNames :: Map.Map SkillId String
skNames = Map.fromList [(sk1, "cooking"), (sk2, "prep-work")]

-- -----------------------------------------------------------------
-- Tests
-- -----------------------------------------------------------------

spec :: Spec
spec = do
    describe "what-if command parsing" $ do
        it "parses close-station" $
            parseCommand "what-if close-station 1 2026-05-04 9"
                `shouldBe` WhatIfCloseStation 1 "2026-05-04" 9

        it "parses pin" $
            parseCommand "what-if pin 1 2 2026-05-04 9"
                `shouldBe` WhatIfPin 1 2 "2026-05-04" 9

        it "parses add-worker with hours" $
            parseCommand "what-if add-worker TempJoe 1 2 40"
                `shouldBe` WhatIfAddWorker "TempJoe" ["1", "2"] (Just 40)

        it "parses add-worker without hours" $
            parseCommand "what-if add-worker TempJoe 1"
                `shouldBe` WhatIfAddWorker "TempJoe" ["1"] Nothing

        it "parses waive-overtime" $
            parseCommand "what-if waive-overtime 3"
                `shouldBe` WhatIfWaiveOvertime 3

        it "parses grant-skill" $
            parseCommand "what-if grant-skill 2 1"
                `shouldBe` WhatIfGrantSkill 2 1

        it "parses override-prefs" $
            parseCommand "what-if override-prefs 1 2 3"
                `shouldBe` WhatIfOverridePrefs 1 [2, 3]

        it "parses revert" $
            parseCommand "what-if revert"
                `shouldBe` WhatIfRevert

        it "parses revert-all" $
            parseCommand "what-if revert-all"
                `shouldBe` WhatIfRevertAll

        it "parses list" $
            parseCommand "what-if list"
                `shouldBe` WhatIfList

        it "parses apply" $
            parseCommand "what-if apply"
                `shouldBe` WhatIfApply

    describe "diffScheduleResults / displayHintDiff" $ do
        it "reports no changes when results are identical" $ do
            let sess = newSession testCtx
                diff = displayHintDiff wNames sNames (sessResult sess) (sessResult sess)
            diff `shouldBe` "No schedule changes.\n"

        it "reports removed assignments when station is closed" $ do
            let sess = newSession testCtx
                sess' = addHint (CloseStation st1 testSlot) sess
                diff = displayHintDiff wNames sNames (sessResult sess) (sessResult sess')
            diff `shouldContain` "  -"  -- removed assignment marker

        it "reports added assignments when skill is granted" $ do
            -- Use a context where st1 can't be filled (w2 lacks sk1), then grant it
            let limitedCtx = testCtx { schWorkers = Set.singleton w2 }
                sess = newSession limitedCtx
                sess' = addHint (GrantSkill w2 sk1) sess
                diff = displayHintDiff wNames sNames (sessResult sess) (sessResult sess')
            -- Should show added assignments or resolved unfilled
            diff `shouldNotBe` "No schedule changes.\n"

    describe "displayHintList" $ do
        it "shows empty message for no hints" $ do
            let sess = newSession testCtx
                output = displayHintList wNames sNames skNames sess
            output `shouldBe` "No active hints.\n"

        it "shows numbered hints" $ do
            let sess = newSession testCtx
                sess' = addHint (GrantSkill w2 sk1) sess
                output = displayHintList wNames sNames skNames sess'
            output `shouldContain` "1. Grant skill: bob -> cooking"

    describe "hint session workflow" $ do
        it "add hint increases step" $ do
            let sess = newSession testCtx
                sess' = addHint (CloseStation st1 testSlot) sess
            sessionStep sess' `shouldBe` 1

        it "revert restores previous state" $ do
            let sess = newSession testCtx
                sess' = addHint (CloseStation st1 testSlot) sess
                sess'' = revertHint sess'
            sessionStep sess'' `shouldBe` 0
            srSchedule (sessResult sess'') `shouldBe` srSchedule (sessResult sess)

        it "multiple hints compose and revert correctly" $ do
            let sess0 = newSession testCtx
                sess1 = addHint (CloseStation st1 testSlot) sess0
                sess2 = addHint (WaiveOvertime w2) sess1
            sessionStep sess2 `shouldBe` 2
            let sess1' = revertHint sess2
            sessionStep sess1' `shouldBe` 1
            srSchedule (sessResult sess1') `shouldBe` srSchedule (sessResult sess1)
