module FreezeLineSpec (spec) where

import Test.Hspec
import qualified Data.Set as Set
import Data.Time (fromGregorian, addDays)
import Data.Time.Clock (getCurrentTime, utctDay)

import Service.FreezeLine

spec :: Spec
spec = do
    describe "computeFreezeLine" $ do
        it "returns yesterday" $ do
            today <- utctDay <$> getCurrentTime
            fl <- computeFreezeLine
            fl `shouldBe` addDays (-1) today

    describe "isFrozen" $ do
        let freezeLine = fromGregorian 2026 4 7  -- yesterday if today is Apr 8

        it "yesterday is frozen" $
            isFrozen freezeLine (fromGregorian 2026 4 7) `shouldBe` True

        it "today is not frozen" $
            isFrozen freezeLine (fromGregorian 2026 4 8) `shouldBe` False

        it "far past is frozen" $
            isFrozen freezeLine (fromGregorian 2026 1 1) `shouldBe` True

        it "future date is not frozen" $
            isFrozen freezeLine (fromGregorian 2026 5 1) `shouldBe` False

        it "date equal to freeze line is frozen" $
            isFrozen freezeLine freezeLine `shouldBe` True

    describe "frozenDatesInRange" $ do
        let freezeLine = fromGregorian 2026 4 7

        it "range entirely before freeze line returns all dates" $ do
            let result = frozenDatesInRange freezeLine
                            (fromGregorian 2026 4 1) (fromGregorian 2026 4 5)
            length result `shouldBe` 5

        it "range entirely after freeze line returns empty" $ do
            let result = frozenDatesInRange freezeLine
                            (fromGregorian 2026 4 8) (fromGregorian 2026 4 14)
            result `shouldBe` []

        it "range spanning freeze line returns only frozen dates" $ do
            let result = frozenDatesInRange freezeLine
                            (fromGregorian 2026 4 5) (fromGregorian 2026 4 12)
            length result `shouldBe` 3  -- Apr 5, 6, 7
            result `shouldBe` [ fromGregorian 2026 4 5
                              , fromGregorian 2026 4 6
                              , fromGregorian 2026 4 7
                              ]

        it "single-day range on freeze line returns that date" $ do
            let result = frozenDatesInRange freezeLine freezeLine freezeLine
            result `shouldBe` [freezeLine]

        it "single-day range after freeze line returns empty" $ do
            let result = frozenDatesInRange freezeLine
                            (fromGregorian 2026 4 8) (fromGregorian 2026 4 8)
            result `shouldBe` []

    describe "isDateUnfrozen" $ do
        it "date within an unfrozen range returns True" $ do
            let unfreezes = Set.fromList
                    [ (fromGregorian 2026 4 1, fromGregorian 2026 4 3) ]
            isDateUnfrozen unfreezes (fromGregorian 2026 4 2) `shouldBe` True

        it "date outside all unfrozen ranges returns False" $ do
            let unfreezes = Set.fromList
                    [ (fromGregorian 2026 4 1, fromGregorian 2026 4 3) ]
            isDateUnfrozen unfreezes (fromGregorian 2026 4 5) `shouldBe` False

        it "date at start of unfrozen range returns True" $ do
            let unfreezes = Set.fromList
                    [ (fromGregorian 2026 4 1, fromGregorian 2026 4 3) ]
            isDateUnfrozen unfreezes (fromGregorian 2026 4 1) `shouldBe` True

        it "date at end of unfrozen range returns True" $ do
            let unfreezes = Set.fromList
                    [ (fromGregorian 2026 4 1, fromGregorian 2026 4 3) ]
            isDateUnfrozen unfreezes (fromGregorian 2026 4 3) `shouldBe` True

        it "single-day unfrozen range works" $ do
            let unfreezes = Set.fromList
                    [ (fromGregorian 2026 4 5, fromGregorian 2026 4 5) ]
            isDateUnfrozen unfreezes (fromGregorian 2026 4 5) `shouldBe` True
            isDateUnfrozen unfreezes (fromGregorian 2026 4 4) `shouldBe` False

        it "empty unfreezes returns False for any date" $ do
            isDateUnfrozen Set.empty (fromGregorian 2026 4 1) `shouldBe` False

        it "multiple unfrozen ranges checked correctly" $ do
            let unfreezes = Set.fromList
                    [ (fromGregorian 2026 4 1, fromGregorian 2026 4 3)
                    , (fromGregorian 2026 3 20, fromGregorian 2026 3 25)
                    ]
            isDateUnfrozen unfreezes (fromGregorian 2026 3 22) `shouldBe` True
            isDateUnfrozen unfreezes (fromGregorian 2026 4 2) `shouldBe` True
            isDateUnfrozen unfreezes (fromGregorian 2026 3 26) `shouldBe` False

    describe "frozenRangeFor" $ do
        let freezeLine = fromGregorian 2026 4 7

        it "range entirely after the freeze line is not frozen" $
            frozenRangeFor freezeLine Set.empty
                (fromGregorian 2026 4 8) (fromGregorian 2026 4 14)
                    `shouldBe` Nothing

        it "reports the first and last still-frozen date" $
            frozenRangeFor freezeLine Set.empty
                (fromGregorian 2026 4 5) (fromGregorian 2026 4 12)
                    `shouldBe` Just (fromGregorian 2026 4 5, fromGregorian 2026 4 7)

        it "a single frozen date reports itself as both ends" $
            frozenRangeFor freezeLine Set.empty freezeLine freezeLine
                `shouldBe` Just (freezeLine, freezeLine)

        it "a fully unfrozen range is not frozen" $ do
            let unfreezes = Set.fromList
                    [ (fromGregorian 2026 4 1, fromGregorian 2026 4 7) ]
            frozenRangeFor freezeLine unfreezes
                (fromGregorian 2026 4 1) (fromGregorian 2026 4 14)
                    `shouldBe` Nothing

        -- The unfrozen prefix is dropped from the reported range, so the message
        -- names only what the caller still has to deal with.
        it "a partially unfrozen range reports only what is left" $ do
            let unfreezes = Set.fromList
                    [ (fromGregorian 2026 4 1, fromGregorian 2026 4 3) ]
            frozenRangeFor freezeLine unfreezes
                (fromGregorian 2026 4 1) (fromGregorian 2026 4 14)
                    `shouldBe` Just (fromGregorian 2026 4 4, fromGregorian 2026 4 7)

        -- An unfreeze in the middle leaves a gap, which the first/last pair
        -- cannot express. Reporting the outer bounds is the honest summary: every
        -- date named is at least plausibly frozen, and the caller is refused
        -- either way.
        it "an unfreeze in the middle still reports the outer bounds" $ do
            let unfreezes = Set.fromList
                    [ (fromGregorian 2026 4 3, fromGregorian 2026 4 4) ]
            frozenRangeFor freezeLine unfreezes
                (fromGregorian 2026 4 1) (fromGregorian 2026 4 14)
                    `shouldBe` Just (fromGregorian 2026 4 1, fromGregorian 2026 4 7)
