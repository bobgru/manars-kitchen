{-# LANGUAGE OverloadedStrings #-}

-- | Tests for the SSE feed's role filtering.
--
-- The live-server side of the endpoint is covered in "ApiSpec"; this module
-- pins down the pure rule it applies.
module EventStreamSpec (spec) where

import Test.Hspec

import Auth.Types (Role(..))
import Audit.CommandMeta (classify, defaultMeta)
import Server.EventStream (eventVisibleTo)

spec :: Spec
spec = do
    describe "eventVisibleTo" $ do
        it "shows an admin everything" $
            mapM_ (\cmd -> eventVisibleTo Admin (classify cmd) `shouldBe` True)
                [ "user rename alice alicia"
                , "worker set-hours 3 40"
                , "absence approve 7"
                , "skill create pastry"
                , "import data.json"
                ]

        it "hides admin-only entity types from a normal user" $
            mapM_ (\cmd -> eventVisibleTo Normal (classify cmd) `shouldBe` False)
                [ "user rename alice alicia"      -- user list is requireAdmin
                , "user create bob pass admin"
                , "worker set-hours 3 40"         -- worker list/view is requireAdmin
                , "worker grant-skill 3 5"
                , "absence approve 7"             -- absences are filtered per worker
                , "absence request 1 3 2026-04-10 2026-04-10"
                , "import data.json"              -- export/import is requireAdmin
                ]

        it "shows a normal user entity types whose reads are unguarded" $
            mapM_ (\cmd -> eventVisibleTo Normal (classify cmd) `shouldBe` True)
                [ "skill create pastry"
                , "skill rename 3 pastry"
                , "station create grill"
                , "shift create morning 6 14"
                , "config set foo 1"
                , "draft create 2026-04-13 2026-04-19"
                , "calendar commit w1 2026-04-06 2026-04-12"
                , "pin 1 2 Monday morning"
                , "assign sched 1 2 2026-04-06 8"
                ]

        it "fails closed on an unclassified command" $ do
            eventVisibleTo Normal (classify "foobar baz") `shouldBe` False
            eventVisibleTo Normal defaultMeta `shouldBe` False
