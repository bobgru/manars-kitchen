module Service.Schedule
    ( createSchedule
    , getSchedule
    , listSchedules
    , deleteSchedule
    ) where

import qualified Data.Map.Strict as Map
import qualified Data.Set as Set

import Data.Text (Text)
import Data.Time (addDays)

import Domain.Types (WorkerId, Slot(..), Schedule)
import Domain.Scheduler
    ( SchedulerContext(..), ScheduleResult(..)
    , buildScheduleFrom
    )
import Domain.Shift (defaultShifts)
import Domain.Pin (expandPins)
import Repo.Types (Repository(..))

-- | Load all contexts, run the scheduler, save the result.
-- Returns the ScheduleResult for display.
createSchedule :: Repository -> Text -> [Slot] -> Set.Set WorkerId
               -> IO ScheduleResult
createSchedule repo name slots workers = do
    skillCtx   <- repoLoadSkillCtx repo
    workerCtx  <- repoLoadWorkerCtx repo
    absenceCtx <- repoLoadAbsenceCtx repo
    cfg        <- repoLoadSchedulerConfig repo
    shifts     <- repoLoadShifts repo
    pins       <- repoLoadPins repo
    let activeShifts = case shifts of
            [] -> defaultShifts
            ss -> ss
        seed = expandPins activeShifts slots pins
        slotDates = map slotDate slots
        periodBounds = case slotDates of
            [] -> (toEnum 0, toEnum 0)
            ds -> (minimum ds, addDays 1 (maximum ds))
        ctx = SchedulerContext
            { schSkillCtx    = skillCtx
            , schWorkerCtx   = workerCtx
            , schAbsenceCtx  = absenceCtx
            , schSlots       = slots
            , schWorkers     = workers
            , schClosedSlots = Set.empty
            , schShifts      = shifts
            , schPrevWeekendWorkers = Set.empty
            , schConfig      = cfg
            , schPeriodBounds = periodBounds
            , schCalendarHours = Map.empty
            }
        result = buildScheduleFrom seed ctx
    repoSaveSchedule repo name (srSchedule result)
    return result

getSchedule :: Repository -> Text -> IO (Maybe Schedule)
getSchedule = repoLoadSchedule

listSchedules :: Repository -> IO [Text]
listSchedules = repoListSchedules

deleteSchedule :: Repository -> Text -> IO ()
deleteSchedule = repoDeleteSchedule
