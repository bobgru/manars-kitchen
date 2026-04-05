module Domain.Shift
    ( -- * Types
      ShiftDef(..)
    , ShiftBlock(..)
      -- * Default shifts
    , defaultShifts
      -- * Grouping
    , shiftsForHour
    , groupSlotsByShift
      -- * Utilities
    , isWeekend
      -- * Tests
    , spec
    ) where

import Data.List (sortBy)
import Data.Ord (comparing)
import qualified Data.Map.Strict as Map
import Data.Time (Day, DayOfWeek(..), TimeOfDay(..), fromGregorian, dayOfWeek)
import Test.Hspec

import Domain.Types (Slot(..))

-- ---------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------

-- | A named block of consecutive hours.
data ShiftDef = ShiftDef
    { sdName  :: !String   -- ^ e.g., "morning", "midday", "afternoon"
    , sdStart :: !Int      -- ^ start hour (inclusive)
    , sdEnd   :: !Int      -- ^ end hour (exclusive)
    } deriving (Eq, Ord, Show, Read)

-- | A concrete shift: a day, a shift definition, and the actual slots.
data ShiftBlock = ShiftBlock
    { sbDay   :: !Day
    , sbShift :: !ShiftDef
    , sbSlots :: ![Slot]     -- ^ sorted by start time
    } deriving (Eq, Show)

instance Ord ShiftBlock where
    compare a b = compare (sbDay a, sdStart (sbShift a))
                          (sbDay b, sdStart (sbShift b))

-- ---------------------------------------------------------------------
-- Default shifts
-- ---------------------------------------------------------------------

-- | Fallback shift definitions used when no shifts are configured.
defaultShifts :: [ShiftDef]
defaultShifts =
    [ ShiftDef "morning"   6 10
    , ShiftDef "midday"   10 14
    , ShiftDef "afternoon" 14 18
    , ShiftDef "evening"   18 22
    ]

-- | Is a given day a weekend day?
isWeekend :: Day -> Bool
isWeekend d = dayOfWeek d `elem` [Saturday, Sunday]

-- ---------------------------------------------------------------------
-- Grouping
-- ---------------------------------------------------------------------

-- | Which shifts does an hour belong to? Returns all matching shifts
-- (a slot can belong to multiple overlapping shifts).
shiftsForHour :: [ShiftDef] -> Int -> [ShiftDef]
shiftsForHour shifts h = filter (\s -> h >= sdStart s && h < sdEnd s) shifts

-- | Group a list of slots into shift blocks, sorted by (day, shift start).
-- A slot may appear in multiple blocks when shifts overlap.
groupSlotsByShift :: [ShiftDef] -> [Slot] -> [ShiftBlock]
groupSlotsByShift shifts slots =
    let getHour (TimeOfDay hour _ _) = hour
        grouped = Map.fromListWith (++)
            [ ((slotDate s, sd), [s])
            | s <- slots
            , sd <- shiftsForHour shifts (getHour (slotStart s))
            ]
    in sortBy compare
       [ ShiftBlock day sd (sortBy (comparing slotStart) ss)
       | ((day, sd), ss) <- Map.toList grouped
       ]

-- ---------------------------------------------------------------------
-- Tests
-- ---------------------------------------------------------------------

spec :: Spec
spec = do
    describe "shiftsForHour" $ do
        it "6 AM matches morning" $
            map sdName (shiftsForHour defaultShifts 6)
                `shouldBe` ["morning"]
        it "9 AM matches morning" $
            map sdName (shiftsForHour defaultShifts 9)
                `shouldBe` ["morning"]
        it "10 AM matches midday" $
            map sdName (shiftsForHour defaultShifts 10)
                `shouldBe` ["midday"]
        it "18 is evening" $
            map sdName (shiftsForHour defaultShifts 18)
                `shouldBe` ["evening"]
        it "5 AM matches nothing" $
            shiftsForHour defaultShifts 5 `shouldBe` []
        it "overlapping shifts return multiple matches" $ do
            let shifts = [ ShiftDef "morning" 6 12
                         , ShiftDef "lunch"  10 14
                         ]
            map sdName (shiftsForHour shifts 11)
                `shouldBe` ["morning", "lunch"]

    describe "groupSlotsByShift" $ do
        it "groups morning slots together" $ do
            let slots = [Slot (fromGregorian 2026 5 4) (TimeOfDay h 0 0) 3600
                        | h <- [7..9]]
                blocks = groupSlotsByShift defaultShifts slots
            length blocks `shouldBe` 1
            case blocks of
                (b:_) -> do
                    length (sbSlots b) `shouldBe` 3
                    sdName (sbShift b) `shouldBe` "morning"
                [] -> expectationFailure "expected at least one block"

        it "splits morning and midday" $ do
            let slots = [Slot (fromGregorian 2026 5 4) (TimeOfDay h 0 0) 3600
                        | h <- [7..13]]
                blocks = groupSlotsByShift defaultShifts slots
            length blocks `shouldBe` 2
            case blocks of
                (b0:b1:_) -> do
                    sdName (sbShift b0) `shouldBe` "morning"
                    sdName (sbShift b1) `shouldBe` "midday"
                _ -> expectationFailure "expected at least two blocks"

        it "handles multiple days" $ do
            let mon = fromGregorian 2026 5 4
                tue = fromGregorian 2026 5 5
                slots = [Slot mon (TimeOfDay 9 0 0) 3600,
                         Slot tue (TimeOfDay 9 0 0) 3600]
                blocks = groupSlotsByShift defaultShifts slots
            length blocks `shouldBe` 2
            case blocks of
                (b0:b1:_) -> do
                    sbDay b0 `shouldBe` mon
                    sbDay b1 `shouldBe` tue
                _ -> expectationFailure "expected at least two blocks"

        it "empty slots produce no blocks" $
            groupSlotsByShift defaultShifts [] `shouldBe` []

        it "sorts blocks by day then shift" $ do
            let day = fromGregorian 2026 5 4
                slots = [Slot day (TimeOfDay 14 0 0) 3600,
                         Slot day (TimeOfDay 8 0 0) 3600]
                blocks = groupSlotsByShift defaultShifts slots
            map (sdName . sbShift) blocks `shouldBe` ["morning", "afternoon"]

        it "overlapping shifts produce multiple blocks with shared slots" $ do
            let shifts = [ ShiftDef "morning" 6 12
                         , ShiftDef "lunch"  10 14
                         ]
                day = fromGregorian 2026 5 4
                slots = [Slot day (TimeOfDay h 0 0) 3600 | h <- [8..13]]
                blocks = groupSlotsByShift shifts slots
            length blocks `shouldBe` 2
            case blocks of
                (b0:b1:_) -> do
                    sdName (sbShift b0) `shouldBe` "morning"
                    sdName (sbShift b1) `shouldBe` "lunch"
                    -- hours 10, 11 appear in both blocks
                    length (sbSlots b0) `shouldBe` 4   -- 8,9,10,11
                    length (sbSlots b1) `shouldBe` 4   -- 10,11,12,13
                _ -> expectationFailure "expected at least two blocks"

    describe "isWeekend" $ do
        it "Saturday is weekend" $
            isWeekend (fromGregorian 2026 4 11) `shouldBe` True
        it "Monday is not weekend" $
            isWeekend (fromGregorian 2026 4 6) `shouldBe` False
