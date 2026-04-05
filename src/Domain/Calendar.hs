module Domain.Calendar
    ( -- * Slot generation
      generateMonthSlots
    , generateWeekSlots
    , generateDateRangeSlots
    , defaultHours
      -- * Tests
    , spec
    ) where

import Data.Set (Set)
import qualified Data.Set as Set
import Data.Time
    ( Day, DayOfWeek(..), TimeOfDay(..)
    , fromGregorian, gregorianMonthLength, dayOfWeek, addDays
    )
import Test.Hspec

import Domain.Types (Slot(..))

-- | Default restaurant hours (list of open hours per day of week).
-- Empty list means closed that day.
--   Mon-Fri: 6:00 AM - 6:00 PM
--   Saturday: 8:00 AM - 8:00 PM
--   Sunday: 8:00 AM - 12:00 PM
defaultHours :: DayOfWeek -> [Int]
defaultHours Monday    = [6..17]
defaultHours Tuesday   = [6..17]
defaultHours Wednesday = [6..17]
defaultHours Thursday  = [6..17]
defaultHours Friday    = [6..17]
defaultHours Saturday  = [8..19]
defaultHours Sunday    = [8..11]

-- | Generate all 1-hour slots for a given month, skipping closed dates.
-- Returns one Slot per hour the restaurant is open.
generateMonthSlots :: (DayOfWeek -> [Int])
                      -- ^ Open hours per day-of-week ([] = closed)
                   -> Integer    -- ^ Year
                   -> Int        -- ^ Month (1-12)
                   -> Set Day    -- ^ Closed dates (holidays)
                   -> [Slot]
generateMonthSlots hoursFor year month closedDates =
    [ Slot day (TimeOfDay h 0 0) 3600
    | day <- daysInMonth year month
    , not (Set.member day closedDates)
    , h <- hoursFor (dayOfWeek day)
    ]

-- | Generate all 1-hour slots for a date range, skipping closed dates.
generateDateRangeSlots :: (DayOfWeek -> [Int])
                       -> Day       -- ^ Start date (inclusive)
                       -> Day       -- ^ End date (inclusive)
                       -> Set Day   -- ^ Closed dates (holidays)
                       -> [Slot]
generateDateRangeSlots hoursFor startDay endDay closedDates =
    [ Slot day (TimeOfDay h 0 0) 3600
    | day <- dateRange startDay endDay
    , not (Set.member day closedDates)
    , h <- hoursFor (dayOfWeek day)
    ]

-- | Generate slots for one week starting from the given Monday.
-- If the given day is not a Monday, starts from the preceding Monday.
generateWeekSlots :: (DayOfWeek -> [Int])
                  -> Day       -- ^ A day in the target week
                  -> Set Day   -- ^ Closed dates (holidays)
                  -> [Slot]
generateWeekSlots hoursFor day closedDates =
    let monday = toMonday day
        sunday = addDays 6 monday
    in generateDateRangeSlots hoursFor monday sunday closedDates

-- | Find the Monday of the week containing the given day.
toMonday :: Day -> Day
toMonday d = case dayOfWeek d of
    Monday    -> d
    Tuesday   -> addDays (-1) d
    Wednesday -> addDays (-2) d
    Thursday  -> addDays (-3) d
    Friday    -> addDays (-4) d
    Saturday  -> addDays (-5) d
    Sunday    -> addDays (-6) d

-- | All days in an inclusive date range.
dateRange :: Day -> Day -> [Day]
dateRange start end = [addDays n start | n <- [0 .. diffDays end start]]
  where
    diffDays e s = fromIntegral (toInteger (fromEnum e) - toInteger (fromEnum s))

-- | All days in a given month.
daysInMonth :: Integer -> Int -> [Day]
daysInMonth year month =
    let len = gregorianMonthLength year month
        first = fromGregorian year month 1
    in [addDays d first | d <- [0 .. fromIntegral len - 1]]

-- -----------------------------------------------------------------
-- Tests
-- -----------------------------------------------------------------

spec :: Spec
spec = do
    describe "generateMonthSlots" $ do
        it "generates correct number of slots for a simple week" $ do
            -- Use a week with known structure: 2026-04-06 is Monday
            let slots = generateMonthSlots defaultHours 2026 4 Set.empty
                -- April 2026: 30 days
                -- Weekdays: count them
                april2026 = daysInMonth 2026 4
                weekdayCount = length [d | d <- april2026, dayOfWeek d `elem` [Monday, Tuesday, Wednesday, Thursday, Friday]]
                satCount = length [d | d <- april2026, dayOfWeek d == Saturday]
                sunCount = length [d | d <- april2026, dayOfWeek d == Sunday]
                expected = weekdayCount * 12 + satCount * 12 + sunCount * 4
            length slots `shouldBe` expected

        it "skips closed dates" $ do
            let holiday = fromGregorian 2026 4 10  -- a Friday
                slots = generateMonthSlots defaultHours 2026 4 (Set.singleton holiday)
                slotsOnHoliday = [s | s <- slots, slotDate s == holiday]
            slotsOnHoliday `shouldBe` []

        it "respects day-of-week hours" $ do
            let slots = generateMonthSlots defaultHours 2026 4 Set.empty
                -- April 5, 2026 is a Sunday: 8 AM - 12 PM = 4 slots
                sunday = fromGregorian 2026 4 5
                sundaySlots = [s | s <- slots, slotDate s == sunday]
            length sundaySlots `shouldBe` 4
            minimum [h | Slot _ (TimeOfDay h _ _) _ <- sundaySlots] `shouldBe` 8
            maximum [h | Slot _ (TimeOfDay h _ _) _ <- sundaySlots] `shouldBe` 11

        it "handles a fully closed week" $ do
            let allClosed _ = []
                slots = generateMonthSlots allClosed 2026 4 Set.empty
            slots `shouldBe` []

        it "generates 1-hour slots" $ do
            let slots = generateMonthSlots defaultHours 2026 4 Set.empty
            all (\s -> slotDuration s == 3600) slots `shouldBe` True
