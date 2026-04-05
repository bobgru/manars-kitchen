module Domain.Schedule
    ( -- * Primitive operations
      assign
    , unassign
    , member
      -- * Projections (views)
    , byWorker
    , byStation
    , bySlot
    , byDay
    , byWorkerSlot
    , scheduleSize
      -- * Tests
    , spec
    ) where

import Data.Set (Set)
import qualified Data.Set as Set
import Data.Time (Day)
import Test.Hspec
import Test.QuickCheck

import Domain.Types

-- ---------------------------------------------------------------------
-- Primitive operations
-- ---------------------------------------------------------------------

-- | Add an assignment to a schedule.
--
-- Laws:
--   assign a (assign a s) = assign a s            (idempotence)
--   assign a (assign b s) = assign b (assign a s) (commutativity)
--   unassign a (assign a s) = s  when a ∉ s       (left inverse)
assign :: Assignment -> Schedule -> Schedule
assign a (Schedule s) = Schedule (Set.insert a s)

-- | Remove an assignment from a schedule.
--
-- Laws:
--   unassign a (unassign a s) = unassign a s        (idempotence)
--   assign a (unassign a s) = s  when a ∈ s         (right inverse)
unassign :: Assignment -> Schedule -> Schedule
unassign a (Schedule s) = Schedule (Set.delete a s)

-- | Test membership.
member :: Assignment -> Schedule -> Bool
member a (Schedule s) = Set.member a s

-- ---------------------------------------------------------------------
-- Projections (views into the schedule)
-- ---------------------------------------------------------------------

-- | All assignments for a given worker.
byWorker :: WorkerId -> Schedule -> Set Assignment
byWorker w (Schedule s) = Set.filter (\a -> assignWorker a == w) s

-- | All assignments at a given station.
byStation :: StationId -> Schedule -> Set Assignment
byStation st (Schedule s) = Set.filter (\a -> assignStation a == st) s

-- | All assignments at a given slot (concurrent assignments).
bySlot :: Slot -> Schedule -> Set Assignment
bySlot t (Schedule s) = Set.filter (\a -> assignSlot a == t) s

-- | All assignments on a given day.
byDay :: Day -> Schedule -> Set Assignment
byDay d (Schedule s) = Set.filter (\a -> slotDate (assignSlot a) == d) s

-- | Assignments for a specific worker at a specific slot.
byWorkerSlot :: WorkerId -> Slot -> Schedule -> Set Assignment
byWorkerSlot w t (Schedule s) =
    Set.filter (\a -> assignWorker a == w && assignSlot a == t) s

-- | Number of assignments in the schedule.
scheduleSize :: Schedule -> Int
scheduleSize (Schedule s) = Set.size s

-- ---------------------------------------------------------------------
-- Tests
-- ---------------------------------------------------------------------

spec :: Spec
spec = do
    describe "Assign/Unassign laws" $ do
        it "assign idempotence" $ property $
            \a s -> assign a (assign a s) === assign a (s :: Schedule)

        it "unassign idempotence" $ property $
            \a s -> unassign a (unassign a s) === unassign a (s :: Schedule)

        it "assign commutativity" $ property $
            \a b s -> assign a (assign b s) === assign b (assign a (s :: Schedule))

        it "left inverse: unassign (assign a s) = s when a not in s" $ property $
            \a s -> not (member a s) ==>
                unassign a (assign a s) === (s :: Schedule)

        it "right inverse: assign (unassign a s) = s when a in s" $ property $
            forAll arbitrary $ \a ->
            forAll (scheduleContaining a) $ \s ->
                assign a (unassign a s) === s

        it "assign grows or preserves size" $ property $
            \a s -> scheduleSize (assign a s) >= scheduleSize (s :: Schedule)

        it "unassign shrinks or preserves size" $ property $
            \a s -> scheduleSize (unassign a s) <= scheduleSize (s :: Schedule)

    describe "Monoid laws (Schedule under union)" $ do
        it "left identity" $ property $
            \s -> mergeSchedules emptySchedule s === (s :: Schedule)

        it "right identity" $ property $
            \s -> mergeSchedules s emptySchedule === (s :: Schedule)

        it "associativity" $ property $
            \s1 s2 s3 -> mergeSchedules (mergeSchedules s1 s2) s3
                === mergeSchedules s1 (mergeSchedules s2 (s3 :: Schedule))

        it "commutativity" $ property $
            \s1 s2 -> mergeSchedules s1 s2 === mergeSchedules s2 (s1 :: Schedule)

        it "idempotence" $ property $
            \s -> mergeSchedules s s === (s :: Schedule)

    describe "Projections" $ do
        it "byWorker returns only that worker's assignments" $ property $
            \w s -> all (\a -> assignWorker a == w) (byWorker w (s :: Schedule))

        it "byStation returns only that station's assignments" $ property $
            \st s -> all (\a -> assignStation a == st) (byStation st (s :: Schedule))

        it "bySlot returns only that slot's assignments" $ property $
            \t s -> all (\a -> assignSlot a == t) (bySlot t (s :: Schedule))

        it "member iff in byWorker" $ property $
            \a s -> member a s === Set.member a (byWorker (assignWorker a) (s :: Schedule))

mergeSchedules :: Schedule -> Schedule -> Schedule
mergeSchedules (Schedule a) (Schedule b) = Schedule (Set.union a b)
