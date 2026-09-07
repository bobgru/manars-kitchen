-- | Problems across a date range of the committed calendar.
--
-- A __problem__ is something about a set of assignments that wants an admin's
-- attention. It is always scoped to a date range — there is no "all problems" —
-- and it knows which entities it touches, so the three visualizations in ADR 0004
-- are filters over one computation rather than three computations that might
-- disagree. See ADR 0006 for why this is one endpoint.
--
-- This reads the __calendar__, never the @drafts@ table. Feeding the calendar
-- slice through the draft validator is what ADR 0004 means by the virtual default
-- draft; drafts have their own page.
--
-- __Compromise is not implemented here yet.__ It is piece 5 of the plan in
-- @docs\/STATUS.md@, and 'Problem' gains a constructor when it lands. The two
-- kinds below are the ones with a derivation that already exists.
module Service.Problems
    ( -- * Problems
      Problem(..)
    , ProblemScope(..)
    , Severity(..)
      -- * Projections
    , problemWorker
    , problemStation
    , problemScope
    , problemSeverity
    , problemEarliestDay
      -- * Computation
    , computeProblems
      -- * Horizons
    , Horizon(..)
    , horizons
    ) where

import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (Day, addDays)
import Data.Time.Clock (getCurrentTime, utctDay)

import Domain.Types
    ( WorkerId, StationId, Station(..), Slot(..), Assignment(..), Schedule(..)
    )
import Domain.Calendar (generateDateRangeSlots, defaultHours)
import Domain.PayPeriod (defaultPayPeriodConfig, payPeriodBounds)
import Domain.Skill (stationClosedSlots, stationStaffCount)
import Repo.Types (Repository(..))
import Service.DraftValidation (DraftViolation(..), validateSchedule)
import qualified Service.Calendar as Cal

-- | What a problem is scoped to.
--
-- Most problems are about one hour of one day. Some are not: a worker over their
-- pay-period hour limit is a fact about many stations across many days, which is
-- why this is a sum rather than a 'Slot'.
data ProblemScope
    = ScopeSlot !Slot
    | ScopeDay  !Day
    deriving (Eq, Ord, Show)

-- | How much a problem wants attention. The ordering is what a cell showing its
-- most-severe problem depends on.
--
-- 'SevViolation' outranks 'SevUnderstaffed' because a violation is always
-- actionable and sometimes legally material, where understaffing may be
-- survivable. The choice is deliberately low-stakes: severity decides only which
-- kind a cell /announces/, and every cell also reports its earliest affected date
-- and lists everything in it when opened. See ADR 0006.
data Severity
    = SevCompromise
    | SevUnderstaffed
    | SevViolation
    deriving (Eq, Ord, Show, Enum, Bounded)

-- | One thing wanting attention.
--
-- A sum rather than a record with a kind field, so that a reader cannot ask an
-- understaffing which worker it is about — there isn't one. 'PViolation' wraps the
-- existing 'DraftViolation' rather than re-modelling it; the slot is reachable
-- through its assignment, so it is not repeated.
data Problem
    = PViolation !DraftViolation
      -- ^ An assignment breaks a hard rule.
    | PUnderstaffed !StationId !Slot !Int !Int
      -- ^ A station has fewer assignments than its minimum for a slot:
      -- station, slot, assigned, required.
    deriving (Eq, Show)

-- | The worker a problem is about, if any. Understaffing has none: nobody is
-- there, which is the problem.
problemWorker :: Problem -> Maybe WorkerId
problemWorker (PViolation v)          = Just (assignWorker (dvAssignment v))
problemWorker (PUnderstaffed _ _ _ _) = Nothing

-- | The station a problem is about, if any.
problemStation :: Problem -> Maybe StationId
problemStation (PViolation v)           = Just (assignStation (dvAssignment v))
problemStation (PUnderstaffed st _ _ _) = Just st

problemScope :: Problem -> ProblemScope
problemScope (PViolation v)          = ScopeSlot (assignSlot (dvAssignment v))
problemScope (PUnderstaffed _ t _ _) = ScopeSlot t

problemSeverity :: Problem -> Severity
problemSeverity (PViolation _)          = SevViolation
problemSeverity (PUnderstaffed _ _ _ _) = SevUnderstaffed

-- | The first day a problem affects. This is what a cell reports alongside its
-- most-severe kind, because the question an admin is asking is "must I act
-- today", which a count of six does not answer.
problemEarliestDay :: Problem -> Day
problemEarliestDay p = case problemScope p of
    ScopeSlot t -> slotDate t
    ScopeDay d  -> d

-- | Every problem in an inclusive date range of the committed calendar.
--
-- Violations come from feeding the calendar slice through
-- 'Service.DraftValidation.validateSchedule'. Understaffing is computed against
-- the slots the range is expected to have staffed: every generated slot crossed
-- with every station, minus the station-slot pairs that fall outside a station's
-- operating hours.
--
-- A station whose 'stationMinStaff' is zero is __not__ understaffed by having
-- nobody on it. It is simply not being staffed, which is a fact about the
-- restaurant rather than a problem — see the Understaffing entry in
-- @CONTEXT.md@.
computeProblems :: Repository -> (Day, Day) -> IO [Problem]
computeProblems repo range@(from, to) = do
    calSched <- Cal.loadCalendarSlice repo from to
    violations <- validateSchedule repo range calSched
    understaffed <- computeUnderstaffing repo range calSched
    return (map PViolation violations ++ understaffed)

-- | Station-slot pairs staffed below their minimum.
computeUnderstaffing :: Repository -> (Day, Day) -> Schedule -> IO [Problem]
computeUnderstaffing repo (from, to) sched = do
    stations <- repoListStations repo
    skillCtx <- repoLoadSkillCtx repo
    let slots  = generateDateRangeSlots defaultHours from to Set.empty
        closed = stationClosedSlots skillCtx slots
    return
        [ PUnderstaffed st t assigned required
        | (st, station) <- stations
        , let required = stationMinStaff station
        , required > 0
        , t <- slots
        , not (Set.member (st, t) closed)
        , let assigned = stationStaffCount st t sched
        , assigned < required
        ]

-- | One selectable date range for the problem view, with a label a client can
-- show without doing pay-period arithmetic of its own.
data Horizon = Horizon
    { hKey   :: !Text
    , hLabel :: !Text
    , hFrom  :: !Day
    , hTo    :: !Day
    } deriving (Eq, Show)

-- | Today, the current pay period, and the next one.
--
-- These come from the server because 'payPeriodBounds' depends on a configurable
-- 'Domain.PayPeriod.PayPeriodType': a week is not an accounting unit for a
-- monthly-paid restaurant, so "current period" is a range only the server can
-- compute. Both ends are inclusive here, unlike 'payPeriodBounds', because every
-- date range a client sees in this codebase is inclusive.
--
-- The labels for the two periods are date ranges rather than words. That is the
-- cost ADR 0004 accepted for following the configured pay period.
horizons :: Repository -> IO [Horizon]
horizons repo = do
    today <- utctDay <$> getCurrentTime
    mPpc  <- repoLoadPayPeriodConfig repo
    let ppc = maybe defaultPayPeriodConfig id mPpc
        (curFrom, curEndExcl) = payPeriodBounds ppc today
        curTo = addDays (-1) curEndExcl
        (nextFrom, nextEndExcl) = payPeriodBounds ppc curEndExcl
        nextTo = addDays (-1) nextEndExcl
    return
        [ Horizon (T.pack "today") (T.pack "Today") today today
        , Horizon (T.pack "current-period") (rangeLabel curFrom curTo) curFrom curTo
        , Horizon (T.pack "next-period") (rangeLabel nextFrom nextTo) nextFrom nextTo
        ]
  where
    rangeLabel a b = T.pack (show a ++ " to " ++ show b)
