module ShellWordsSpec (spec) where

import Test.Hspec
import CLI.Commands (shellWords, shellQuote, parseCommand, Command(..))

spec :: Spec
spec = do
    describe "shellWords" $ do
        it "splits plain words like Prelude.words" $
            shellWords "skill rename 1 broiler" `shouldBe` ["skill", "rename", "1", "broiler"]

        it "handles double-quoted strings" $
            shellWords "skill rename 1 \"pizza oven\"" `shouldBe` ["skill", "rename", "1", "pizza oven"]

        it "handles single-quoted strings" $
            shellWords "skill rename 1 'pizza oven'" `shouldBe` ["skill", "rename", "1", "pizza oven"]

        it "handles escaped double quote inside double quotes" $
            shellWords "station add 5 \"Bob\\\"s Grill\"" `shouldBe` ["station", "add", "5", "Bob\"s Grill"]

        it "handles escaped single quote inside single quotes" $
            shellWords "station add 5 'Bob\\'s Grill'" `shouldBe` ["station", "add", "5", "Bob's Grill"]

        it "is lenient with unclosed double quote" $
            shellWords "skill rename 1 \"pizza oven" `shouldBe` ["skill", "rename", "1", "pizza oven"]

        it "is lenient with unclosed single quote" $
            shellWords "skill rename 1 'pizza oven" `shouldBe` ["skill", "rename", "1", "pizza oven"]

        it "handles empty input" $
            shellWords "" `shouldBe` []

        it "handles whitespace-only input" $
            shellWords "   " `shouldBe` []

        it "handles mixed quoted and unquoted tokens" $
            shellWords "shift create \"morning rush\" 8 17" `shouldBe` ["shift", "create", "morning rush", "8", "17"]

        it "handles empty quoted string" $
            shellWords "a \"\" b" `shouldBe` ["a", "", "b"]

        it "preserves single quotes inside double quotes" $
            shellWords "\"it's good\"" `shouldBe` ["it's good"]

        it "preserves double quotes inside single quotes" $
            shellWords "'he said \"hi\"'" `shouldBe` ["he said \"hi\""]

    describe "parseCommand with quoted arguments" $ do
        it "parses skill rename with quoted multi-word name" $
            parseCommand "skill rename 1 \"pizza oven\"" `shouldBe` SkillRename 1 "pizza oven"

        it "parses skill create with quoted multi-word name" $
            parseCommand "skill create 3 \"hot grill\"" `shouldBe` SkillCreate 3 "hot grill"

        it "parses station add with quoted multi-word name" $
            parseCommand "station add 5 \"prep area\"" `shouldBe` StationAdd 5 "prep area"

        it "parses shift create with quoted multi-word name" $
            parseCommand "shift create \"morning rush\" 8 17" `shouldBe` ShiftCreate "morning rush" 8 17

        it "still parses unquoted single-word names" $
            parseCommand "skill rename 1 broiler" `shouldBe` SkillRename 1 "broiler"

    describe "shellQuote" $ do
        it "passes through simple names" $
            shellQuote "broiler" `shouldBe` "broiler"

        it "quotes names with spaces" $
            shellQuote "pizza oven" `shouldBe` "\"pizza oven\""

        it "escapes double quotes" $
            shellQuote "Bob\"s Grill" `shouldBe` "\"Bob\\\"s Grill\""

        it "quotes names with single quotes" $
            shellQuote "Bob's Grill" `shouldBe` "\"Bob's Grill\""

        it "escapes backslashes" $
            shellQuote "a\\b" `shouldBe` "\"a\\\\b\""

        it "quotes empty string" $
            shellQuote "" `shouldBe` "\"\""

        it "roundtrips through shellWords" $
            let names = ["broiler", "pizza oven", "Bob\"s Grill", "Bob's Grill", "a\\b", ""]
            in mapM_ (\n -> shellWords (shellQuote n) `shouldBe` [n]) names
