module Service.Calendar
    ( commitToCalendar
    , loadCalendarSlice
    , listCalendarHistory
    , viewCommit
    ) where

import Data.Text (Text)
import Data.Time (Day)

import Domain.Types (Schedule(..))
import Repo.Types (Repository(..), CalendarCommit)

commitToCalendar :: Repository -> Day -> Day -> Text -> Schedule -> IO ()
commitToCalendar repo dateFrom dateTo note newSchedule = do
    -- 1. Load the existing assignments that will be replaced
    existing <- repoLoadCalendar repo dateFrom dateTo
    -- 2. Snapshot them into history
    _ <- repoSaveCommit repo dateFrom dateTo note existing
    -- 3. Overwrite the calendar with the new assignments
    repoSaveCalendar repo dateFrom dateTo newSchedule

-- | Load calendar assignments for a date range.
loadCalendarSlice :: Repository -> Day -> Day -> IO Schedule
loadCalendarSlice repo = repoLoadCalendar repo

-- | List all calendar history commits in reverse chronological order.
listCalendarHistory :: Repository -> IO [CalendarCommit]
listCalendarHistory = repoListCommits

-- | Load the snapshot of replaced assignments for a specific commit.
viewCommit :: Repository -> Int -> IO Schedule
viewCommit repo = repoLoadCommitAssignments repo
