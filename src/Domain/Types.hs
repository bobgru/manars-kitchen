{-# LANGUAGE OverloadedStrings #-}
module Domain.Types
    ( WorkerId(..)
    , StationId(..)
    , Station(..)
    , SkillId(..)
    , AbsenceId(..)
    , AbsenceTypeId(..)
    , WorkerStatus(..)
    , workerStatusToText
    , textToWorkerStatus
    , Slot(..)
    , Assignment(..)
    , Schedule(..)
    , emptySchedule
    , slotEnd
    , slotOverlaps
    , slotAbuts
    , slotGap
    , DiffTime
    , scheduleContaining
    , scheduleWithSwappable
    ) where

import Data.Text (Text)
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Time (Day, TimeOfDay(..), DiffTime,
                  timeOfDayToTime, timeToTimeOfDay, fromGregorian)
import Test.QuickCheck (Arbitrary(..), Gen, choose, listOf, suchThat)
import Web.HttpApiData (FromHttpApiData(..), ToHttpApiData(..))

-- | Terminal unit: a worker, identified by an opaque ID.
-- Attributes (skills, status, preferences) live in a separate Context,
-- not in the algebraic core.
newtype WorkerId = WorkerId Int
    deriving (Eq, Ord, Show, Read)

-- | Terminal unit: a station, identified by an opaque ID.
newtype StationId = StationId Int
    deriving (Eq, Ord, Show, Read)

data Station = Station
    { stationName     :: !Text
    , stationMinStaff :: !Int
    , stationMaxStaff :: !Int
    } deriving (Eq, Ord, Show, Read)

-- | Terminal unit: a skill, identified by an opaque ID.
-- Skills form a preorder under implication: if skill A implies skill B,
-- then possessing A means also possessing B.
newtype SkillId = SkillId Int
    deriving (Eq, Ord, Show, Read)

instance FromHttpApiData SkillId where
    parseUrlPiece t = SkillId <$> parseUrlPiece t

instance ToHttpApiData SkillId where
    toUrlPiece (SkillId i) = toUrlPiece i

-- | Terminal unit: an absence request, identified by an opaque ID.
newtype AbsenceId = AbsenceId Int
    deriving (Eq, Ord, Show, Read)

-- | Terminal unit: a type of absence (e.g., vacation, training,
-- maternity leave). Modeled as an opaque ID so new absence types
-- can be added as data without code changes.
newtype AbsenceTypeId = AbsenceTypeId Int
    deriving (Eq, Ord, Show, Read)

-- | The worker-status of a user. 'WSNone' means the user is not a worker
-- (e.g., admin-only account). 'WSActive' means a worker who participates
-- in scheduling. 'WSInactive' means a worker whose configuration is
-- preserved but who is not currently being scheduled.
data WorkerStatus = WSNone | WSActive | WSInactive
    deriving (Eq, Ord, Show, Read, Enum, Bounded)

workerStatusToText :: WorkerStatus -> Text
workerStatusToText WSNone     = "none"
workerStatusToText WSActive   = "active"
workerStatusToText WSInactive = "inactive"

textToWorkerStatus :: Text -> Maybe WorkerStatus
textToWorkerStatus "none"     = Just WSNone
textToWorkerStatus "active"   = Just WSActive
textToWorkerStatus "inactive" = Just WSInactive
textToWorkerStatus _          = Nothing

-- | Terminal unit: a specific time interval on a specific date.
-- Starts as 1-hour granularity but the algebra does not assume that.
data Slot = Slot
    { slotDate     :: !Day
    , slotStart    :: !TimeOfDay
    , slotDuration :: !DiffTime
    } deriving (Eq, Ord, Show, Read)

-- | The end time of a slot.
slotEnd :: Slot -> TimeOfDay
slotEnd s = timeToTimeOfDay (timeOfDayToTime (slotStart s) + slotDuration s)

-- | Do two slots on the same day overlap?
slotOverlaps :: Slot -> Slot -> Bool
slotOverlaps a b
    | slotDate a /= slotDate b = False
    | otherwise =
        let startA = timeOfDayToTime (slotStart a)
            endA   = startA + slotDuration a
            startB = timeOfDayToTime (slotStart b)
            endB   = startB + slotDuration b
        in startA < endB && startB < endA

-- | Do two slots on the same day abut (one ends exactly when the other starts)?
slotAbuts :: Slot -> Slot -> Bool
slotAbuts a b
    | slotDate a /= slotDate b = False
    | otherwise =
        let startA = timeOfDayToTime (slotStart a)
            endA   = startA + slotDuration a
            startB = timeOfDayToTime (slotStart b)
            endB   = startB + slotDuration b
        in endA == startB || endB == startA

-- | The gap in seconds between two slots on the same day.
-- Returns Nothing if they overlap or are on different days.
slotGap :: Slot -> Slot -> Maybe DiffTime
slotGap a b
    | slotDate a /= slotDate b = Nothing
    | slotOverlaps a b         = Nothing
    | otherwise =
        let endA   = timeOfDayToTime (slotStart a) + slotDuration a
            endB   = timeOfDayToTime (slotStart b) + slotDuration b
            startA = timeOfDayToTime (slotStart a)
            startB = timeOfDayToTime (slotStart b)
        in Just $ if endA <= startB
                  then startB - endA
                  else startA - endB

-- | The fundamental composite: a worker is at a station during a slot.
data Assignment = Assignment
    { assignWorker  :: !WorkerId
    , assignStation :: !StationId
    , assignSlot    :: !Slot
    } deriving (Eq, Ord, Show, Read)

-- | A schedule is a set of assignments.
-- This forms a commutative idempotent monoid under union.
newtype Schedule = Schedule { unSchedule :: Set Assignment }
    deriving (Eq, Ord, Show, Read)

-- | The identity element: the empty schedule.
emptySchedule :: Schedule
emptySchedule = Schedule Set.empty

-- -----------------------------------------------------------------
-- QuickCheck instances
-- -----------------------------------------------------------------

instance Arbitrary WorkerId where
    arbitrary = WorkerId <$> choose (1, 10)

instance Arbitrary StationId where
    arbitrary = StationId <$> choose (1, 5)

instance Arbitrary SkillId where
    arbitrary = SkillId <$> choose (1, 8)

instance Arbitrary AbsenceId where
    arbitrary = AbsenceId <$> choose (1, 100)

instance Arbitrary AbsenceTypeId where
    arbitrary = AbsenceTypeId <$> choose (1, 5)

instance Arbitrary Slot where
    arbitrary = do
        d <- arbitraryDay
        h <- choose (8, 20)  -- restaurant hours: 8am-9pm
        return $ Slot d (TimeOfDay h 0 0) 3600  -- 1-hour slots
      where
        arbitraryDay :: Gen Day
        arbitraryDay = do
            m <- choose (1, 12)
            d <- choose (1, 28)
            return $ fromGregorian 2026 m d

instance Arbitrary Assignment where
    arbitrary = Assignment <$> arbitrary <*> arbitrary <*> arbitrary

instance Arbitrary Schedule where
    arbitrary = Schedule . Set.fromList <$> listOf arbitrary

-- -----------------------------------------------------------------
-- Test generators
-- -----------------------------------------------------------------

-- | Generate a schedule guaranteed to contain a specific assignment.
scheduleContaining :: Assignment -> Gen Schedule
scheduleContaining a = do
    Schedule s <- arbitrary
    return $ Schedule (Set.insert a s)

-- | Generate a schedule with two distinct workers each having exactly one
-- assignment at a given slot (needed for swap tests).
scheduleWithSwappable :: Gen (WorkerId, WorkerId, StationId, StationId, Slot, Schedule)
scheduleWithSwappable = do
    w1 <- arbitrary
    w2 <- arbitrary `suchThat` (/= w1)
    s1 <- arbitrary
    s2 <- arbitrary
    t  <- arbitrary
    base <- arbitrary
    let cleaned = Schedule $ Set.filter
            (\a -> not (assignWorker a `elem` [w1, w2] && assignSlot a == t))
            (unSchedule base)
        Schedule cs = cleaned
        sched = Schedule (Set.insert (Assignment w1 s1 t) (Set.insert (Assignment w2 s2 t) cs))
    return (w1, w2, s1, s2, t, sched)
