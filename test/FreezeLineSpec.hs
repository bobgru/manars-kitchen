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

    describe "freeze check integration" $ do
        it "unfrozen dates bypass freeze warning" $ do
            let freezeLine = fromGregorian 2026 4 7
                unfreezes = Set.fromList
                    [ (fromGregorian 2026 4 1, fromGregorian 2026 4 7) ]
                frozen = frozenDatesInRange freezeLine
                            (fromGregorian 2026 4 1) (fromGregorian 2026 4 14)
                stillFrozen = filter (not . isDateUnfrozen unfreezes) frozen
            stillFrozen `shouldBe` []

        it "partially unfrozen range leaves some dates frozen" $ do
            let freezeLine = fromGregorian 2026 4 7
                unfreezes = Set.fromList
                    [ (fromGregorian 2026 4 1, fromGregorian 2026 4 3) ]
                frozen = frozenDatesInRange freezeLine
                            (fromGregorian 2026 4 1) (fromGregorian 2026 4 14)
                stillFrozen = filter (not . isDateUnfrozen unfreezes) frozen
            length stillFrozen `shouldBe` 4  -- Apr 4, 5, 6, 7
