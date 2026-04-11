module Domain.Hint
    ( -- * Types
      Hint(..)
    , Session(..)
      -- * Session operations
    , newSession
    , addHint
    , revertHint
    , revertTo
    , sessionStep
      -- * Hint application
    , applyHints
      -- * Tests
    , spec
    ) where

import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Time (Day, TimeOfDay(..), fromGregorian)
import Test.Hspec

import Domain.Types
import Domain.Schedule (assign, byWorker, byWorkerSlot)
import Domain.Skill hiding (spec)
import Domain.Worker hiding (spec)
import Domain.Absence (emptyAbsenceContext)
import Domain.SchedulerConfig (defaultConfig)
import Domain.Scheduler hiding (spec)

-- ---------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------

-- | A hint modifies the scheduler context to guide scheduling.
-- Hints are reversible: the session tracks the original context
-- and applies all active hints before each scheduling run.
data Hint
    = CloseStation !StationId !Slot
      -- ^ Do not staff this station at this slot.
    | PinAssignment !WorkerId !StationId !Slot
      -- ^ Force this worker to this station at this slot.
      -- The assignment is placed in the seed schedule before
      -- the scheduler runs.
    | AddWorker !WorkerId !(Set SkillId) !(Maybe DiffTime)
      -- ^ Bring in a temporary worker with given skills and
      -- optional weekly hour limit. Nothing = no limit.
    | WaiveOvertime !WorkerId
      -- ^ Allow overtime for this worker even if they haven't opted in.
    | GrantSkill !WorkerId !SkillId
      -- ^ Hypothetically give a worker a skill (for planning).
    | OverridePreference !WorkerId ![StationId]
      -- ^ Replace a worker's station preferences.
    deriving (Eq, Ord, Show)

-- | An interactive scheduling session.
-- The original context is preserved; hints are accumulated and
-- can be reverted. Each step recomputes the schedule from scratch.
data Session = Session
    { sessOrigCtx :: !SchedulerContext
      -- ^ The original, unmodified context.
    , sessHints   :: ![Hint]
      -- ^ Applied hints, most recent last.
    , sessResult  :: !ScheduleResult
      -- ^ The schedule result with all current hints applied.
    } deriving (Show)

-- ---------------------------------------------------------------------
-- Session operations
-- ---------------------------------------------------------------------

-- | Start a new session. Runs the scheduler with no hints.
newSession :: SchedulerContext -> Session
newSession ctx = Session ctx [] (buildSchedule ctx)

-- | Add a hint and recompute the schedule.
addHint :: Hint -> Session -> Session
addHint h sess =
    let hints' = sessHints sess ++ [h]
    in recompute (sessOrigCtx sess) hints'

-- | Remove the most recent hint and recompute.
-- Returns the session unchanged if there are no hints.
revertHint :: Session -> Session
revertHint sess =
    case sessHints sess of
        [] -> sess
        hs -> recompute (sessOrigCtx sess) (init hs)

-- | Revert to a given step number (0 = no hints, 1 = first hint, etc.).
-- Clamps to valid range.
revertTo :: Int -> Session -> Session
revertTo n sess =
    let n' = max 0 (min n (length (sessHints sess)))
    in recompute (sessOrigCtx sess) (take n' (sessHints sess))

-- | Current step number (number of applied hints).
sessionStep :: Session -> Int
sessionStep = length . sessHints

-- | Recompute a session from context and hints.
recompute :: SchedulerContext -> [Hint] -> Session
recompute ctx hints =
    let (ctx', seed) = applyHints hints ctx
        result = buildScheduleFrom seed ctx'
    in Session ctx hints result

-- ---------------------------------------------------------------------
-- Hint application
-- ---------------------------------------------------------------------

-- | Apply a list of hints to a scheduler context.
-- Returns the modified context and a seed schedule (for pinned assignments).
applyHints :: [Hint] -> SchedulerContext -> (SchedulerContext, Schedule)
applyHints hints ctx = foldl applyOne (ctx, emptySchedule) hints

applyOne :: (SchedulerContext, Schedule) -> Hint -> (SchedulerContext, Schedule)
applyOne (ctx, seed) hint = case hint of
    CloseStation st t ->
        ( ctx { schClosedSlots = Set.insert (st, t) (schClosedSlots ctx) }
        , seed
        )

    PinAssignment w st t ->
        ( ctx
        , assign (Assignment w st t) seed
        )

    AddWorker w skills maxH ->
        let sctx = schSkillCtx ctx
            wctx = schWorkerCtx ctx
            sctx' = sctx
                { scWorkerSkills = Map.insertWith Set.union w skills (scWorkerSkills sctx) }
            wctx' = case maxH of
                Nothing -> wctx
                Just h  -> wctx { wcMaxPeriodHours = Map.insert w h (wcMaxPeriodHours wctx) }
        in ( ctx { schSkillCtx  = sctx'
                 , schWorkerCtx = wctx'
                 , schWorkers   = Set.insert w (schWorkers ctx)
                 }
           , seed
           )

    WaiveOvertime w ->
        let wctx = schWorkerCtx ctx
            wctx' = wctx { wcOvertimeOptIn = Set.insert w (wcOvertimeOptIn wctx) }
        in ( ctx { schWorkerCtx = wctx' }
           , seed
           )

    GrantSkill w sk ->
        let sctx = schSkillCtx ctx
            sctx' = sctx
                { scWorkerSkills = Map.insertWith Set.union w (Set.singleton sk) (scWorkerSkills sctx) }
        in ( ctx { schSkillCtx = sctx' }
           , seed
           )

    OverridePreference w prefs ->
        let wctx = schWorkerCtx ctx
            wctx' = wctx { wcStationPrefs = Map.insert w prefs (wcStationPrefs wctx) }
        in ( ctx { schWorkerCtx = wctx' }
           , seed
           )

-- ---------------------------------------------------------------------
-- Tests
-- ---------------------------------------------------------------------

hw_alice, hw_bob, hw_carol :: WorkerId
hw_alice = WorkerId 1
hw_bob   = WorkerId 2
hw_carol = WorkerId 3

hw_temp :: WorkerId
hw_temp = WorkerId 99

hsk_prep, hsk_cooking, hsk_management :: SkillId
hsk_prep       = SkillId 1
hsk_cooking    = SkillId 2
hsk_management = SkillId 3

hst_grill, hst_prep_table :: StationId
hst_grill      = StationId 1
hst_prep_table = StationId 2

hMkSlot :: Day -> Int -> Slot
hMkSlot d h = Slot d (TimeOfDay h 0 0) 3600

hMondaySlot :: Slot
hMondaySlot = hMkSlot (fromGregorian 2026 5 4) 9

hTuesdaySlot :: Slot
hTuesdaySlot = hMkSlot (fromGregorian 2026 5 5) 9

hSkillCtx :: SkillContext
hSkillCtx = SkillContext
    { scWorkerSkills = Map.fromList
        [ (hw_alice, Set.singleton hsk_management)
        , (hw_bob,   Set.singleton hsk_cooking)
        , (hw_carol, Set.singleton hsk_prep)
        ]
    , scStationRequires = Map.fromList
        [ (hst_grill,      Set.singleton hsk_cooking)
        , (hst_prep_table, Set.singleton hsk_prep)
        ]
    , scSkillImplies = Map.fromList
        [ (hsk_management, Set.singleton hsk_cooking)
        , (hsk_cooking,    Set.singleton hsk_prep)
        ]
    , scAllStations = Set.fromList [hst_grill, hst_prep_table]
    , scStationHours = Map.empty
    , scMultiStationHours = Map.empty
    }

hWorkerCtx :: WorkerContext
hWorkerCtx = WorkerContext
    { wcMaxPeriodHours = Map.fromList
        [ (hw_alice, 40 * 3600)
        , (hw_bob,   1 * 3600)   -- bob limited to 1 hour
        , (hw_carol, 40 * 3600)
        ]
    , wcOvertimeOptIn = Set.empty
    , wcStationPrefs  = Map.empty
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

hBaseCtx :: SchedulerContext
hBaseCtx = SchedulerContext hSkillCtx hWorkerCtx emptyAbsenceContext
    [hMondaySlot, hTuesdaySlot]
    (Set.fromList [hw_alice, hw_bob, hw_carol])
    Set.empty
    []
    Set.empty
    defaultConfig
    (fromGregorian 2026 5 4, fromGregorian 2026 5 11)
    Map.empty

spec :: Spec
spec = do
    describe "newSession" $ do
        it "produces the same result as buildSchedule" $ do
            let sess = newSession hBaseCtx
            srSchedule (sessResult sess) `shouldBe` srSchedule (buildSchedule hBaseCtx)
            sessionStep sess `shouldBe` 0

    describe "addHint / revertHint" $ do
        it "adding a hint changes the result" $ do
            let sess = newSession hBaseCtx
                sess' = addHint (CloseStation hst_grill hMondaySlot) sess
            sessionStep sess' `shouldBe` 1
            -- grill should have no assignments on Monday
            let sched = srSchedule (sessResult sess')
                grillMon = Set.filter (\a -> assignStation a == hst_grill
                                          && assignSlot a == hMondaySlot)
                               (unSchedule sched)
            Set.size grillMon `shouldBe` 0

        it "reverting restores the previous result" $ do
            let sess = newSession hBaseCtx
                sess' = addHint (CloseStation hst_grill hMondaySlot) sess
                sess'' = revertHint sess'
            sessionStep sess'' `shouldBe` 0
            srSchedule (sessResult sess'') `shouldBe` srSchedule (sessResult sess)

        it "reverting with no hints is a no-op" $ do
            let sess = newSession hBaseCtx
                sess' = revertHint sess
            sessionStep sess' `shouldBe` 0

    describe "revertTo" $ do
        it "reverts to an earlier step" $ do
            let sess0 = newSession hBaseCtx
                sess1 = addHint (CloseStation hst_grill hMondaySlot) sess0
                sess2 = addHint (CloseStation hst_prep_table hMondaySlot) sess1
                reverted = revertTo 1 sess2
            sessionStep reverted `shouldBe` 1
            srSchedule (sessResult reverted) `shouldBe` srSchedule (sessResult sess1)

        it "revertTo 0 removes all hints" $ do
            let sess0 = newSession hBaseCtx
                sess1 = addHint (CloseStation hst_grill hMondaySlot) sess0
                reverted = revertTo 0 sess1
            sessionStep reverted `shouldBe` 0
            srSchedule (sessResult reverted) `shouldBe` srSchedule (sessResult sess0)

    describe "CloseStation hint" $ do
        it "prevents station from being staffed at that slot" $ do
            let sess = addHint (CloseStation hst_grill hMondaySlot) (newSession hBaseCtx)
                sched = srSchedule (sessResult sess)
                grillMon = Set.filter (\a -> assignStation a == hst_grill
                                          && assignSlot a == hMondaySlot) (unSchedule sched)
            Set.size grillMon `shouldBe` 0

        it "does not affect other slots" $ do
            let sess = addHint (CloseStation hst_grill hMondaySlot) (newSession hBaseCtx)
                sched = srSchedule (sessResult sess)
                grillTue = Set.filter (\a -> assignStation a == hst_grill
                                          && assignSlot a == hTuesdaySlot) (unSchedule sched)
            Set.size grillTue `shouldSatisfy` (>= 1)

    describe "PinAssignment hint" $ do
        it "forces a specific assignment" $ do
            let sess = addHint (PinAssignment hw_carol hst_prep_table hMondaySlot) (newSession hBaseCtx)
                sched = srSchedule (sessResult sess)
                carolMon = byWorkerSlot hw_carol hMondaySlot sched
            Set.size carolMon `shouldBe` 1
            Set.map assignStation carolMon `shouldBe` Set.singleton hst_prep_table

    describe "AddWorker hint" $ do
        it "adds a temporary worker who gets assigned" $ do
            -- Only carol (prep) available, grill can't be filled.
            let limitedCtx = hBaseCtx { schWorkers = Set.singleton hw_carol }
                sess = newSession limitedCtx
            -- grill should be unfilled
            any (\u -> unfilledStation u == hst_grill) (srUnfilled (sessResult sess))
                `shouldBe` True
            -- Add a temp worker with cooking skill
            let sess' = addHint (AddWorker hw_temp (Set.singleton hsk_cooking) (Just (40 * 3600))) sess
            srUnfilled (sessResult sess') `shouldBe` []
            let sched = srSchedule (sessResult sess')
                tempAssignments = byWorker hw_temp sched
            Set.size tempAssignments `shouldSatisfy` (>= 1)

    describe "WaiveOvertime hint" $ do
        it "allows a non-opted-in worker to do overtime" $ do
            -- bob has 1hr limit, 2 slots, not opted in
            -- only bob and carol available; grill needs cooking
            let twoSlotCtx = hBaseCtx
                    { schWorkers = Set.fromList [hw_bob, hw_carol]
                    , schSlots = [hMondaySlot, hTuesdaySlot]
                    }
                sess = newSession twoSlotCtx
            -- Should have unfilled (bob can only do 1 slot of grill)
            srUnfilled (sessResult sess) `shouldSatisfy` (not . null)
            -- Waive overtime for bob
            let sess' = addHint (WaiveOvertime hw_bob) sess
            srUnfilled (sessResult sess') `shouldBe` []

    describe "GrantSkill hint" $ do
        it "hypothetically qualifies a worker for new stations" $ do
            -- carol only has prep; grant her cooking so she can work grill
            let carolOnlyCtx = hBaseCtx
                    { schWorkers = Set.singleton hw_carol
                    , schSlots = [hMondaySlot]
                    }
                sess = newSession carolOnlyCtx
            any (\u -> unfilledStation u == hst_grill) (srUnfilled (sessResult sess))
                `shouldBe` True
            let sess' = addHint (GrantSkill hw_carol hsk_cooking) sess
            -- carol can now work grill (cooking) or prep_table (cooking→prep)
            -- with 1 slot and 2 stations, one will still be unfilled,
            -- but grill should no longer be unfilled
            any (\u -> unfilledStation u == hst_grill) (srUnfilled (sessResult sess'))
                `shouldBe` False

    describe "OverridePreference hint" $ do
        it "changes which station a worker prefers" $ do
            let prefCtx = hBaseCtx
                    { schWorkerCtx = hWorkerCtx
                        { wcStationPrefs = Map.fromList
                            [ (hw_alice, [hst_prep_table])
                            , (hw_bob,   [hst_grill])
                            ]
                        }
                    , schWorkers = Set.fromList [hw_alice, hw_bob]
                    , schSlots = [hMondaySlot]
                    }
                sess = newSession prefCtx
                -- Override alice to prefer grill
                sess' = addHint (OverridePreference hw_alice [hst_grill]) sess
                sched = srSchedule (sessResult sess')
                aliceStations = Set.map assignStation (byWorker hw_alice sched)
            aliceStations `shouldSatisfy` Set.member hst_grill

    describe "Multiple hints compose" $ do
        it "close a station and add a worker in the same session" $ do
            let sess0 = newSession hBaseCtx
                sess1 = addHint (CloseStation hst_grill hMondaySlot) sess0
                sess2 = addHint (AddWorker hw_temp (Set.singleton hsk_cooking) Nothing) sess1
            sessionStep sess2 `shouldBe` 2
            -- grill closed Monday, but temp worker can work Tuesday grill
            let sched = srSchedule (sessResult sess2)
                grillMon = Set.filter (\a -> assignStation a == hst_grill
                                          && assignSlot a == hMondaySlot) (unSchedule sched)
                grillTue = Set.filter (\a -> assignStation a == hst_grill
                                          && assignSlot a == hTuesdaySlot) (unSchedule sched)
            Set.size grillMon `shouldBe` 0
            Set.size grillTue `shouldSatisfy` (>= 1)
