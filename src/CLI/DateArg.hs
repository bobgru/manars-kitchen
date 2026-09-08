-- | Date arguments as a human types them.
--
-- Every command that takes a date accepts an ISO @YYYY-MM-DD@ or a form relative
-- to today: @today@, @today+7@, @today-1@. The relative forms exist because a
-- fixture or a scripted replay that hardcodes calendar dates goes stale — the
-- problem view's horizons are derived from /today/, so a demo written against
-- April 2026 shows an empty current period forever. See ADR 0008.
--
-- The resolution point is deliberately here rather than at each call site. Two
-- reasons: 'relativeDay' stays pure, so the parsing is unit-testable without a
-- clock; and 'withDay' / 'withDayPair' own the one error message, which used to be
-- copied — with three different wordings — across twenty-two places in
-- @CLI.App@ and @CLI.RpcClient@.
module CLI.DateArg
    ( -- * Parsing
      relativeDay
    , resolveDay
      -- * Command plumbing
    , withDay
    , withDayPair
    , dateArgSyntax
      -- * Tests
    , spec
    ) where

import Data.Char (isDigit)
import Data.Time (Day, addDays, defaultTimeLocale, parseTimeM)
import Data.Time.Clock (getCurrentTime, utctDay)
import Test.Hspec

-- | One line naming every accepted form, for help text and error messages. Kept
-- next to the parser so the two cannot drift.
dateArgSyntax :: String
dateArgSyntax = "YYYY-MM-DD, today, today+N or today-N"

-- | Resolve a date argument against a given \"today\".
--
-- Pure, and takes today as an argument, so the offset arithmetic can be tested
-- without reaching for a clock. Rejects anything it does not fully understand
-- rather than guessing: @today+@ and @today+x@ are errors, not @today@.
relativeDay :: Day -> String -> Maybe Day
relativeDay today s = case s of
    "today"       -> Just today
    '+':digits    -> offsetBy id digits
    't':'o':'d':'a':'y':rest -> case rest of
        '+':digits -> offsetBy id digits
        '-':digits -> offsetBy negate digits
        _          -> Nothing
    _             -> isoDay s
  where
    -- A bare @+N@ is accepted as shorthand for @today+N@; a bare @-N@ is not,
    -- because it is indistinguishable from a flag.
    offsetBy sign digits
        | not (null digits) && all isDigit digits =
            Just (addDays (sign (read digits)) today)
        | otherwise = Nothing

-- | Parse an ISO date, and only an ISO date.
isoDay :: String -> Maybe Day
isoDay = parseTimeM True defaultTimeLocale "%Y-%m-%d"

-- | 'relativeDay' against the real clock.
resolveDay :: String -> IO (Maybe Day)
resolveDay s = do
    today <- utctDay <$> getCurrentTime
    return (relativeDay today s)

-- | Run an action with a resolved date, or report the syntax and do nothing.
withDay :: String -> (Day -> IO ()) -> IO ()
withDay s k = do
    mDay <- resolveDay s
    case mDay of
        Just d  -> k d
        Nothing -> putStrLn (badDate s)

-- | Run an action with two resolved dates, naming whichever one is wrong.
--
-- Naming it matters more than it looks: these are ranges, so \"invalid date\" on
-- @calendar view today+7 today@ sends the reader looking at the wrong argument.
withDayPair :: String -> String -> (Day -> Day -> IO ()) -> IO ()
withDayPair a b k = do
    ma <- resolveDay a
    mb <- resolveDay b
    case (ma, mb) of
        (Just x, Just y)  -> k x y
        (Nothing, _)      -> putStrLn (badDate a)
        (_, Nothing)      -> putStrLn (badDate b)

badDate :: String -> String
badDate s = "Not a date: " ++ show s ++ ". Use " ++ dateArgSyntax ++ "."

-- ---------------------------------------------------------------------
-- Tests
-- ---------------------------------------------------------------------

spec :: Spec
spec = do
    let today = read "2026-09-07" :: Day

    describe "relativeDay" $ do
        it "accepts an ISO date unchanged" $
            relativeDay today "2026-04-06" `shouldBe` Just (read "2026-04-06")

        it "resolves today" $
            relativeDay today "today" `shouldBe` Just today

        it "adds and subtracts days" $ do
            relativeDay today "today+1"  `shouldBe` Just (read "2026-09-08")
            relativeDay today "today+13" `shouldBe` Just (read "2026-09-20")
            relativeDay today "today-1"  `shouldBe` Just (read "2026-09-06")

        it "crosses month and year boundaries by arithmetic, not by string" $ do
            relativeDay (read "2026-12-31") "today+1"
                `shouldBe` Just (read "2027-01-01")
            relativeDay (read "2026-03-01") "today-1"
                `shouldBe` Just (read "2026-02-28")

        it "accepts a bare +N as shorthand" $
            relativeDay today "+7" `shouldBe` Just (read "2026-09-14")

        -- A partially understood date is the dangerous case: silently treating
        -- "today+" as "today" would schedule the wrong week and look deliberate.
        it "rejects anything it does not fully understand" $ do
            relativeDay today "today+"     `shouldBe` Nothing
            relativeDay today "today+x"    `shouldBe` Nothing
            relativeDay today "today++1"   `shouldBe` Nothing
            relativeDay today "todayish"   `shouldBe` Nothing
            relativeDay today "tomorrow"   `shouldBe` Nothing
            relativeDay today "2026-13-01" `shouldBe` Nothing
            relativeDay today "2026-4-6"   `shouldBe` Nothing
            relativeDay today ""           `shouldBe` Nothing

        -- The old hand-rolled parser in CLI.RpcClient did `read` on the pieces of
        -- anything containing a dash, so this threw rather than returning Nothing.
        it "returns Nothing on a dashed non-date instead of throwing" $
            relativeDay today "foo-bar-baz" `shouldBe` Nothing
