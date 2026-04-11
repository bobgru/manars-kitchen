module Domain.PayPeriod
    ( -- * Types
      PayPeriodType(..)
    , PayPeriodConfig(..)
      -- * Boundaries
    , payPeriodBounds
    , defaultPayPeriodConfig
      -- * Parsing / display
    , parsePayPeriodType
    , showPayPeriodType
      -- * Tests
    , spec
    ) where

import Data.Time (Day, addDays, fromGregorian, toGregorian, dayOfWeek, DayOfWeek(..),
                  addGregorianMonthsClip)
import Test.Hspec

-- | Supported pay period types.
data PayPeriodType
    = Weekly
    | Biweekly
    | SemiMonthly
    | Monthly
    deriving (Eq, Ord, Show, Read)

-- | Restaurant-wide pay period configuration.
data PayPeriodConfig = PayPeriodConfig
    { ppcType       :: !PayPeriodType
    , ppcAnchorDate :: !Day
    } deriving (Eq, Ord, Show, Read)

-- | Default config: weekly with a fixed Monday anchor (2026-01-05).
defaultPayPeriodConfig :: PayPeriodConfig
defaultPayPeriodConfig = PayPeriodConfig Weekly (fromGregorian 2026 1 5)

-- | Compute the pay period boundaries (inclusive start, exclusive end)
-- for the period containing the given day.
payPeriodBounds :: PayPeriodConfig -> Day -> (Day, Day)
payPeriodBounds cfg day = case ppcType cfg of
    Weekly     -> anchorRelativeBounds 7 (ppcAnchorDate cfg) day
    Biweekly   -> anchorRelativeBounds 14 (ppcAnchorDate cfg) day
    SemiMonthly -> semiMonthlyBounds day
    Monthly     -> monthlyBounds day

-- | For fixed-length periods (weekly, biweekly): compute period start
-- using anchor-relative modular arithmetic.
anchorRelativeBounds :: Integer -> Day -> Day -> (Day, Day)
anchorRelativeBounds periodLen anchor day =
    let daysSince = toInteger (fromEnum day - fromEnum anchor)
        -- Use Haskell's div which rounds towards negative infinity
        periodNum = daysSince `div` periodLen
        periodStart = addDays (periodNum * periodLen) anchor
        periodEnd   = addDays periodLen periodStart
    in (periodStart, periodEnd)

-- | Semi-monthly: 1st-15th and 16th-end.
semiMonthlyBounds :: Day -> (Day, Day)
semiMonthlyBounds day =
    let (y, m, d) = toGregorian day
    in if d <= 15
       then (fromGregorian y m 1, fromGregorian y m 16)
       else let nextMonth = addGregorianMonthsClip 1 (fromGregorian y m 1)
            in (fromGregorian y m 16, nextMonth)

-- | Monthly: 1st to 1st of next month.
monthlyBounds :: Day -> (Day, Day)
monthlyBounds day =
    let (y, m, _) = toGregorian day
        start = fromGregorian y m 1
        end   = addGregorianMonthsClip 1 start
    in (start, end)

-- | Parse a period type string from CLI/storage.
parsePayPeriodType :: String -> Maybe PayPeriodType
parsePayPeriodType "weekly"       = Just Weekly
parsePayPeriodType "biweekly"     = Just Biweekly
parsePayPeriodType "semi-monthly" = Just SemiMonthly
parsePayPeriodType "monthly"      = Just Monthly
parsePayPeriodType _              = Nothing

-- | Display a period type as a string for CLI/storage.
showPayPeriodType :: PayPeriodType -> String
showPayPeriodType Weekly      = "weekly"
showPayPeriodType Biweekly    = "biweekly"
showPayPeriodType SemiMonthly = "semi-monthly"
showPayPeriodType Monthly     = "monthly"

-- ---------------------------------------------------------------------
-- Tests
-- ---------------------------------------------------------------------

spec :: Spec
spec = do
    describe "payPeriodBounds" $ do
        describe "Weekly" $ do
            it "period containing a Wednesday with Monday anchor" $
                -- anchor 2026-01-05 (Monday), query 2026-04-08 (Wednesday)
                -- period: 2026-04-06 (Monday) to 2026-04-13
                let cfg = PayPeriodConfig Weekly (fromGregorian 2026 1 5)
                in payPeriodBounds cfg (fromGregorian 2026 4 8)
                    `shouldBe` (fromGregorian 2026 4 6, fromGregorian 2026 4 13)

            it "period start on anchor date itself" $
                let cfg = PayPeriodConfig Weekly (fromGregorian 2026 1 5)
                in payPeriodBounds cfg (fromGregorian 2026 1 5)
                    `shouldBe` (fromGregorian 2026 1 5, fromGregorian 2026 1 12)

            it "period before anchor date" $
                let cfg = PayPeriodConfig Weekly (fromGregorian 2026 1 5)
                in payPeriodBounds cfg (fromGregorian 2025 12 31)
                    `shouldBe` (fromGregorian 2025 12 29, fromGregorian 2026 1 5)

        describe "Biweekly" $ do
            it "14-day period aligned to anchor" $
                -- anchor 2026-01-05, query 2026-04-08
                -- days since = 93, 93 div 14 = 6, start = anchor + 84 = 2026-03-30
                let cfg = PayPeriodConfig Biweekly (fromGregorian 2026 1 5)
                in payPeriodBounds cfg (fromGregorian 2026 4 8)
                    `shouldBe` (fromGregorian 2026 3 30, fromGregorian 2026 4 13)

            it "period containing anchor date" $
                let cfg = PayPeriodConfig Biweekly (fromGregorian 2026 1 5)
                in payPeriodBounds cfg (fromGregorian 2026 1 10)
                    `shouldBe` (fromGregorian 2026 1 5, fromGregorian 2026 1 19)

        describe "SemiMonthly" $ do
            it "first half: 1st-15th" $
                let cfg = PayPeriodConfig SemiMonthly (fromGregorian 2026 1 1)
                in payPeriodBounds cfg (fromGregorian 2026 4 10)
                    `shouldBe` (fromGregorian 2026 4 1, fromGregorian 2026 4 16)

            it "second half: 16th-end" $
                let cfg = PayPeriodConfig SemiMonthly (fromGregorian 2026 1 1)
                in payPeriodBounds cfg (fromGregorian 2026 4 20)
                    `shouldBe` (fromGregorian 2026 4 16, fromGregorian 2026 5 1)

            it "February second half" $
                let cfg = PayPeriodConfig SemiMonthly (fromGregorian 2026 1 1)
                in payPeriodBounds cfg (fromGregorian 2026 2 20)
                    `shouldBe` (fromGregorian 2026 2 16, fromGregorian 2026 3 1)

            it "day 15 is in first half" $
                let cfg = PayPeriodConfig SemiMonthly (fromGregorian 2026 1 1)
                in payPeriodBounds cfg (fromGregorian 2026 4 15)
                    `shouldBe` (fromGregorian 2026 4 1, fromGregorian 2026 4 16)

            it "day 16 is in second half" $
                let cfg = PayPeriodConfig SemiMonthly (fromGregorian 2026 1 1)
                in payPeriodBounds cfg (fromGregorian 2026 4 16)
                    `shouldBe` (fromGregorian 2026 4 16, fromGregorian 2026 5 1)

        describe "Monthly" $ do
            it "April" $
                let cfg = PayPeriodConfig Monthly (fromGregorian 2026 1 1)
                in payPeriodBounds cfg (fromGregorian 2026 4 15)
                    `shouldBe` (fromGregorian 2026 4 1, fromGregorian 2026 5 1)

            it "February (non-leap)" $
                let cfg = PayPeriodConfig Monthly (fromGregorian 2026 1 1)
                in payPeriodBounds cfg (fromGregorian 2026 2 14)
                    `shouldBe` (fromGregorian 2026 2 1, fromGregorian 2026 3 1)

            it "February (leap year)" $
                let cfg = PayPeriodConfig Monthly (fromGregorian 2028 1 1)
                in payPeriodBounds cfg (fromGregorian 2028 2 29)
                    `shouldBe` (fromGregorian 2028 2 1, fromGregorian 2028 3 1)

            it "December wraps to next year" $
                let cfg = PayPeriodConfig Monthly (fromGregorian 2026 1 1)
                in payPeriodBounds cfg (fromGregorian 2026 12 25)
                    `shouldBe` (fromGregorian 2026 12 1, fromGregorian 2027 1 1)

    describe "parsePayPeriodType" $ do
        it "parses valid types" $ do
            parsePayPeriodType "weekly"       `shouldBe` Just Weekly
            parsePayPeriodType "biweekly"     `shouldBe` Just Biweekly
            parsePayPeriodType "semi-monthly" `shouldBe` Just SemiMonthly
            parsePayPeriodType "monthly"      `shouldBe` Just Monthly

        it "rejects invalid types" $
            parsePayPeriodType "quarterly" `shouldBe` Nothing

    describe "showPayPeriodType" $ do
        it "round-trips with parsePayPeriodType" $ do
            parsePayPeriodType (showPayPeriodType Weekly) `shouldBe` Just Weekly
            parsePayPeriodType (showPayPeriodType Biweekly) `shouldBe` Just Biweekly
            parsePayPeriodType (showPayPeriodType SemiMonthly) `shouldBe` Just SemiMonthly
            parsePayPeriodType (showPayPeriodType Monthly) `shouldBe` Just Monthly

    describe "defaultPayPeriodConfig" $ do
        it "is weekly" $
            ppcType defaultPayPeriodConfig `shouldBe` Weekly

        it "anchor is a Monday" $
            dayOfWeek (ppcAnchorDate defaultPayPeriodConfig) `shouldBe` Monday
