module Domain.Skill
    ( -- * Types
      Skill(..)
    , SkillContext(..)
    , emptySkillContext
      -- * Skill implication (preorder)
    , effectiveSkills
      -- * Qualification checks
    , qualified
    , couldQualifyViaCrossTraining
    , tryAssign
      -- * Station staffing queries
    , stationStaffCount
      -- * Station hours
    , stationClosedSlots
      -- * Multi-station
    , isMultiStationSlot
      -- * Tests
    , spec
    ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Text (Text)
import Test.Hspec
import Test.QuickCheck

import Data.Time (DayOfWeek, TimeOfDay(..), dayOfWeek)
import Domain.Types
import Domain.Worker (WorkerContext(..))
import Domain.Schedule (assign, bySlot)

-- ---------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------

-- | A skill has a name and description. Further attributes may be
-- added later.
data Skill = Skill
    { skillName        :: !Text
    , skillDescription :: !Text
    } deriving (Eq, Ord, Show, Read)

-- | Reference data for skill-based reasoning.
--
-- The implication relation is stored as direct implications only;
-- 'effectiveSkills' computes the transitive closure.
data SkillContext = SkillContext
    { scWorkerSkills    :: !(Map WorkerId (Set SkillId))
      -- ^ Skills each worker holds directly.
    , scStationRequires :: !(Map StationId (Set SkillId))
      -- ^ Skills required to work a station. A worker must satisfy
      -- /all/ required skills (any one via direct or implied).
    , scSkillImplies    :: !(Map SkillId (Set SkillId))
      -- ^ Direct implications: if skill A is in the map with B in its
      -- set, then possessing A means also possessing B.
    , scAllStations     :: !(Set StationId)
      -- ^ The full set of stations.
    , scStationHours    :: !(Map StationId (Map DayOfWeek [Int]))
      -- ^ Per-station operating hours by day of week.
      -- If a station is not in this map, it is open during all
      -- restaurant hours. If present, each day maps to a list of
      -- open hours; an empty list means closed that day.
      -- Days not in the inner map default to all restaurant hours.
    , scMultiStationHours :: !(Map StationId (Map DayOfWeek [Int]))
      -- ^ Per-station hours where multi-station assignment is allowed.
      -- During these hours, a worker already assigned to another station
      -- at the same slot can also cover this station. The worker's time
      -- counts only once (no double-billing).
    } deriving (Eq, Ord, Show, Read)

emptySkillContext :: SkillContext
emptySkillContext = SkillContext Map.empty Map.empty Map.empty
                                Set.empty Map.empty Map.empty

-- ---------------------------------------------------------------------
-- Skill implication (preorder: reflexive + transitive)
-- ---------------------------------------------------------------------

-- | Compute the full set of skills a worker effectively holds,
-- including all transitively implied skills.
--
-- Laws (preorder):
--   Reflexivity:  s ∈ effectiveSkills ctx {s}
--   Transitivity: if A implies B and B implies C,
--                 then C ∈ effectiveSkills ctx {A}
effectiveSkills :: SkillContext -> Set SkillId -> Set SkillId
effectiveSkills ctx = close
  where
    close skills =
      let mergeSkills acc sk =
            Set.union acc (Map.findWithDefault Set.empty sk (scSkillImplies ctx))
          expanded = Set.foldl' mergeSkills skills skills
      in if expanded == skills
         then skills
         else close expanded

-- | All effective skills for a given worker.
workerEffectiveSkills :: SkillContext -> WorkerId -> Set SkillId
workerEffectiveSkills ctx w =
    effectiveSkills ctx (Map.findWithDefault Set.empty w (scWorkerSkills ctx))

-- ---------------------------------------------------------------------
-- Qualification checks
-- ---------------------------------------------------------------------

-- | Is a worker qualified to work at a station?
-- A worker is qualified if their effective skills are a superset of
-- the station's required skills.
qualified :: SkillContext -> WorkerId -> StationId -> Bool
qualified ctx w st =
    let required  = Map.findWithDefault Set.empty st (scStationRequires ctx)
        effective = workerEffectiveSkills ctx w
    in required `Set.isSubsetOf` effective

-- | Could a worker qualify for a station via cross-training?
-- Returns True if every skill the worker is missing for the station
-- is in their cross-training goals.  The caller must also check that
-- a higher-seniority worker is present at the slot.
couldQualifyViaCrossTraining :: SkillContext -> WorkerContext -> WorkerId -> StationId -> Bool
couldQualifyViaCrossTraining sctx wctx w st =
    let required  = Map.findWithDefault Set.empty st (scStationRequires sctx)
        effective = workerEffectiveSkills sctx w
        missing   = Set.difference required effective
        goals     = Map.findWithDefault Set.empty w (wcCrossTraining wctx)
    in not (Set.null missing) && missing `Set.isSubsetOf` goals

-- | Attempt an assignment, returning Nothing if the worker lacks
-- the required skills for the station.
tryAssign :: SkillContext -> Assignment -> Schedule -> Maybe Schedule
tryAssign ctx a sched
    | qualified ctx (assignWorker a) (assignStation a) = Just (assign a sched)
    | otherwise = Nothing

-- ---------------------------------------------------------------------
-- Station staffing queries
-- ---------------------------------------------------------------------

-- | How many workers are currently assigned to a station at a given slot.
stationStaffCount :: StationId -> Slot -> Schedule -> Int
stationStaffCount st t sched =
    Set.size $ Set.filter (\a -> assignStation a == st) (bySlot t sched)

-- ---------------------------------------------------------------------
-- Station hours
-- ---------------------------------------------------------------------

-- | Compute the set of (station, slot) pairs that are closed because
-- the slot falls outside the station's operating hours for that day.
-- Stations without an entry in 'scStationHours' are open for all slots.
-- Days not in the inner map default to open (no filtering).
stationClosedSlots :: SkillContext -> [Slot] -> Set (StationId, Slot)
stationClosedSlots ctx slots =
    Set.fromList
        [ (st, slot)
        | (st, dayHoursMap) <- Map.toList (scStationHours ctx)
        , slot <- slots
        , let dow = dayOfWeek (slotDate slot)
              h = case slotStart slot of TimeOfDay hour _ _ -> hour
        , case Map.lookup dow dayHoursMap of
            Nothing -> False  -- no specific hours for this day, station is open
            Just hs -> h `notElem` hs
        ]

-- ---------------------------------------------------------------------
-- Multi-station queries
-- ---------------------------------------------------------------------

-- | Is multi-station assignment allowed for a station at a given slot?
-- Returns True if the station has multi-station hours configured for
-- the slot's day-of-week and the slot's hour is in the list.
isMultiStationSlot :: SkillContext -> StationId -> Slot -> Bool
isMultiStationSlot ctx st slot =
    let dow = dayOfWeek (slotDate slot)
        h = case slotStart slot of TimeOfDay hour _ _ -> hour
    in case Map.lookup st (scMultiStationHours ctx) >>= Map.lookup dow of
        Nothing -> False
        Just hs -> h `elem` hs

-- ---------------------------------------------------------------------
-- Tests
-- ---------------------------------------------------------------------

-- Skills: cooking > prep, management > cooking > prep
sk_prep, sk_cooking, sk_management, sk_cleaning :: SkillId
sk_prep       = SkillId 1
sk_cooking    = SkillId 2
sk_management = SkillId 3
sk_cleaning   = SkillId 4

-- Workers
w_alice, w_bob, w_carol, w_dave :: WorkerId
w_alice = WorkerId 1  -- has management (implies cooking, prep)
w_bob   = WorkerId 2  -- has cooking (implies prep)
w_carol = WorkerId 3  -- has prep only
w_dave  = WorkerId 4  -- has cooking (implies prep)

-- Stations
st_grill, st_prep_table, st_dish :: StationId
st_grill      = StationId 1  -- requires cooking
st_prep_table = StationId 2  -- requires prep
st_dish       = StationId 3  -- requires cleaning

defaultContext :: SkillContext
defaultContext = SkillContext
    { scWorkerSkills = Map.fromList
        [ (w_alice, Set.fromList [sk_management])
        , (w_bob,   Set.fromList [sk_cooking])
        , (w_carol, Set.fromList [sk_prep])
        , (w_dave,  Set.fromList [sk_cooking])
        ]
    , scStationRequires = Map.fromList
        [ (st_grill,      Set.singleton sk_cooking)
        , (st_prep_table, Set.singleton sk_prep)
        , (st_dish,       Set.singleton sk_cleaning)
        ]
    , scSkillImplies = Map.fromList
        [ (sk_management, Set.singleton sk_cooking)
        , (sk_cooking,    Set.singleton sk_prep)
        ]
    , scAllStations = Set.fromList [st_grill, st_prep_table, st_dish]
    , scStationHours = Map.empty
    , scMultiStationHours = Map.empty
    }

testSlot :: Slot
testSlot = Slot (read "2026-05-04") (read "10:00:00") 3600

spec :: Spec
spec = do
    describe "effectiveSkills (preorder)" $ do
        it "reflexivity: a skill is in its own closure" $
            let eff = effectiveSkills defaultContext (Set.singleton sk_prep)
            in eff `shouldSatisfy` Set.member sk_prep

        it "single implication: cooking implies prep" $
            let eff = effectiveSkills defaultContext (Set.singleton sk_cooking)
            in do
                eff `shouldSatisfy` Set.member sk_cooking
                eff `shouldSatisfy` Set.member sk_prep

        it "transitive implication: management implies cooking and prep" $
            let eff = effectiveSkills defaultContext (Set.singleton sk_management)
            in do
                eff `shouldSatisfy` Set.member sk_management
                eff `shouldSatisfy` Set.member sk_cooking
                eff `shouldSatisfy` Set.member sk_prep

        it "no spurious implications: prep does not imply cooking" $
            let eff = effectiveSkills defaultContext (Set.singleton sk_prep)
            in eff `shouldSatisfy` (not . Set.member sk_cooking)

        it "reflexivity (general): every input skill appears in output" $ property $
            forAll arbitrary $ \sk ->
                Set.member sk (effectiveSkills defaultContext (Set.singleton sk))

    describe "qualified" $ do
        it "alice (management) is qualified for grill (requires cooking)" $
            qualified defaultContext w_alice st_grill `shouldBe` True

        it "alice is qualified for prep table (requires prep)" $
            qualified defaultContext w_alice st_prep_table `shouldBe` True

        it "bob (cooking) is qualified for grill" $
            qualified defaultContext w_bob st_grill `shouldBe` True

        it "bob is qualified for prep table" $
            qualified defaultContext w_bob st_prep_table `shouldBe` True

        it "carol (prep) is not qualified for grill" $
            qualified defaultContext w_carol st_grill `shouldBe` False

        it "carol is qualified for prep table" $
            qualified defaultContext w_carol st_prep_table `shouldBe` True

        it "nobody is qualified for dish (requires cleaning, nobody has it)" $
            do qualified defaultContext w_alice st_dish `shouldBe` False
               qualified defaultContext w_bob   st_dish `shouldBe` False
               qualified defaultContext w_carol st_dish `shouldBe` False

    describe "tryAssign" $ do
        it "succeeds when worker is qualified" $
            let a = Assignment w_bob st_grill testSlot
            in tryAssign defaultContext a emptySchedule
                `shouldBe` Just (assign a emptySchedule)

        it "fails when worker is not qualified" $
            let a = Assignment w_carol st_grill testSlot
            in tryAssign defaultContext a emptySchedule
                `shouldBe` Nothing

    describe "stationStaffCount" $ do
        it "is 0 for empty schedule" $
            stationStaffCount st_grill testSlot emptySchedule `shouldBe` 0

        it "reflects assignments" $
            let sched = assign (Assignment w_bob st_grill testSlot)
                      $ assign (Assignment w_alice st_grill testSlot) emptySchedule
            in stationStaffCount st_grill testSlot sched `shouldBe` 2
