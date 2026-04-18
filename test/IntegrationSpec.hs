module Main (main) where

import Test.Hspec

import qualified HintIntegrationSpec
import qualified HintSessionSpec
import qualified HintE2ESpec
import qualified AuditSpec
import qualified SessionSpec
import qualified PubSubSpec
import qualified ApiSpec

main :: IO ()
main = hspec $ do
    describe "HintIntegration"     HintIntegrationSpec.spec
    describe "HintSession"         HintSessionSpec.spec
    describe "HintE2E"             HintE2ESpec.spec
    describe "Audit"               AuditSpec.spec
    describe "Session"             SessionSpec.spec
    describe "PubSub"              PubSubSpec.spec
    describe "REST API"            ApiSpec.spec
