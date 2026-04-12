module Main (main) where

import Test.Hspec

import qualified Domain.Schedule
import qualified Domain.Transaction
import qualified Domain.Skill
import qualified Domain.Worker
import qualified Domain.Scheduler
import qualified Domain.Absence
import qualified Domain.Hint
import qualified Domain.Diagnosis
import qualified Domain.Calendar
import qualified Domain.Shift
import qualified Domain.SchedulerConfig
import qualified Domain.Pin
import qualified Domain.Optimizer
import qualified Domain.PayPeriod
import qualified CalendarSpec
import qualified DraftSpec
import qualified DraftValidationSpec
import qualified FreezeLineSpec
import qualified HintIntegrationSpec
import qualified AuditSpec
import qualified SessionSpec

main :: IO ()
main = hspec $ do
    describe "Domain.Schedule"        Domain.Schedule.spec
    describe "Domain.Transaction"     Domain.Transaction.spec
    describe "Domain.Skill"           Domain.Skill.spec
    describe "Domain.Worker"          Domain.Worker.spec
    describe "Domain.Scheduler"       Domain.Scheduler.spec
    describe "Domain.Absence"         Domain.Absence.spec
    describe "Domain.Hint"            Domain.Hint.spec
    describe "Domain.Diagnosis"       Domain.Diagnosis.spec
    describe "Domain.Calendar"        Domain.Calendar.spec
    describe "Domain.Shift"           Domain.Shift.spec
    describe "Domain.SchedulerConfig" Domain.SchedulerConfig.spec
    describe "Domain.Pin"             Domain.Pin.spec
    describe "Domain.Optimizer"       Domain.Optimizer.spec
    describe "Domain.PayPeriod"      Domain.PayPeriod.spec
    describe "Calendar"              CalendarSpec.spec
    describe "Draft"                 DraftSpec.spec
    describe "DraftValidation"      DraftValidationSpec.spec
    describe "FreezeLine"           FreezeLineSpec.spec
    describe "HintIntegration"     HintIntegrationSpec.spec
    describe "Audit"               AuditSpec.spec
    describe "Session"             SessionSpec.spec
