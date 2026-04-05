module Domain.Pin
    ( -- * Types
      PinnedAssignment(..)
    , PinSpec(..)
      -- * Expansion
    , expandPins
      -- * Tests
    , spec
    ) where

import Data.Time (Day, DayOfWeek(..), TimeOfDay(..), addDays, dayOfWeek)
import qualified Data.Set as Set
import Test.Hspec

import Domain.Types
import Domain.Schedule (assign)
import Domain.Shift (ShiftDef(..), defaultShifts)

-- ---------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------

-- | What hours a pin covers.
data PinSpec
    = PinSlot !Int
      -- ^ A single hour (e.g., 9 means 9:00-10:00).
    | PinShift !String
      -- ^ A named shift (e.g., "morning"). Expands to all hours in
      -- the shift definition.
    deriving (Eq, Ord, Show, Read)

-- | A recurring pinned assignment: every week, this worker is assigned
-- to this station on this day-of-week for the given hours/shift.
data PinnedAssignment = PinnedAssignment
    { pinWorker  :: !WorkerId
    , pinStation :: !StationId
    , pinDay     :: !DayOfWeek
    , pinSpec    :: !PinSpec
    } deriving (Eq, Ord, Show, Read)

-- ---------------------------------------------------------------------
-- Expansion
-- ---------------------------------------------------------------------

-- | Expand pinned assignments into concrete assignments for the given
-- slot list.  Shift-level pins are resolved using the provided shift
-- definitions.  Hours that don't appear in the slot list are silently
-- dropped.
expandPins :: [ShiftDef] -> [Slot] -> [PinnedAssignment] -> Schedule
expandPins shifts slots pins =
    foldl (\sched a -> assign a sched) emptySchedule
        (concatMap expand pins)
  where
    expand p =
        [ Assignment (pinWorker p) (pinStation p) slot
        | slot <- matchingSlots shifts slots p
        ]

-- | Find all slots matching a pin's day-of-week and hours.
matchingSlots :: [ShiftDef] -> [Slot] -> PinnedAssignment -> [Slot]
matchingSlots shifts slots p =
    let targetDow = pinDay p
        hours = case pinSpec p of
            PinSlot h   -> Set.singleton h
            PinShift sn -> case filter (\sd -> sdName sd == sn) shifts of
                []    -> Set.empty
                (s:_) -> Set.fromList [sdStart s .. sdEnd s - 1]
    in [ slot
       | slot <- slots
       , dayOfWeek (slotDate slot) == targetDow
       , let TimeOfDay h _ _ = slotStart slot
       , Set.member h hours
       ]

-- ---------------------------------------------------------------------
-- Tests
-- ---------------------------------------------------------------------

spec :: Spec
spec = do
    let monday = read "2026-05-04" :: Day  -- Monday
        mkSlot d h = Slot d (TimeOfDay h 0 0) 3600
        weekSlots = [ mkSlot (addDays i monday) h
                    | i <- [0..6]
                    , h <- [6..21]
                    ]
        shifts = defaultShifts

    describe "expandPins" $ do
        it "slot-level pin produces one assignment per matching slot" $ do
            let pin = PinnedAssignment (WorkerId 1) (StationId 1) Monday (PinSlot 9)
                sched = expandPins shifts weekSlots [pin]
            Set.size (unSchedule sched) `shouldBe` 1
            case Set.toList (unSchedule sched) of
                (a:_) -> do
                    assignWorker a `shouldBe` WorkerId 1
                    assignStation a `shouldBe` StationId 1
                    slotDate (assignSlot a) `shouldBe` monday
                    slotStart (assignSlot a) `shouldBe` TimeOfDay 9 0 0
                [] -> expectationFailure "expected at least one assignment"

        it "shift-level pin expands to all hours in the shift" $ do
            let pin = PinnedAssignment (WorkerId 2) (StationId 1) Monday (PinShift "morning")
                sched = expandPins shifts weekSlots [pin]
            -- morning = 6..9 = 4 hours
            Set.size (unSchedule sched) `shouldBe` 4

        it "pin on Tuesday only matches Tuesday slots" $ do
            let pin = PinnedAssignment (WorkerId 1) (StationId 1) Tuesday (PinSlot 10)
                sched = expandPins shifts weekSlots [pin]
            Set.size (unSchedule sched) `shouldBe` 1
            case Set.toList (unSchedule sched) of
                (a:_) -> slotDate (assignSlot a) `shouldBe` addDays 1 monday
                [] -> expectationFailure "expected at least one assignment"

        it "unknown shift name produces no assignments" $ do
            let pin = PinnedAssignment (WorkerId 1) (StationId 1) Monday (PinShift "nonexistent")
                sched = expandPins shifts weekSlots [pin]
            Set.size (unSchedule sched) `shouldBe` 0

        it "multiple pins compose" $ do
            let pin1 = PinnedAssignment (WorkerId 1) (StationId 1) Monday (PinSlot 9)
                pin2 = PinnedAssignment (WorkerId 2) (StationId 2) Monday (PinSlot 9)
                sched = expandPins shifts weekSlots [pin1, pin2]
            Set.size (unSchedule sched) `shouldBe` 2

        it "slot outside available slots is dropped" $ do
            let limitedSlots = [mkSlot monday h | h <- [9..11]]
                pin = PinnedAssignment (WorkerId 1) (StationId 1) Monday (PinSlot 6)
                sched = expandPins shifts limitedSlots [pin]
            Set.size (unSchedule sched) `shouldBe` 0
