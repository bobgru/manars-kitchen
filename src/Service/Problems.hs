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
-- Compromises are the fourth kind: legal assignments that ignore a stated
-- preference. The three derivable ones are the ones ADR 0006 settled, and they
-- are judged over the same context and look-back as violations so the two cannot
-- disagree about a worker's hours.
module Service.Problems
    ( -- * Problems
      Problem(..)
    , ProblemScope(..)
    , Severity(..)
    , CompromiseKind(..)
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

import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (Day, DiffTime, addDays)
import Data.Time.Clock (getCurrentTime, utctDay)

import Domain.Types
    ( WorkerId, StationId, Station(..), Slot(..), Assignment(..), Schedule(..)
    )
import Domain.Calendar (generateDateRangeSlots, defaultHours)
import Domain.PayPeriod (defaultPayPeriodConfig, payPeriodBounds)
import Domain.Schedule (byWorker)
import Domain.Scheduler (SchedulerContext(..))
import Domain.Skill (stationClosedSlots, stationStaffCount)
import Domain.Worker
    ( wouldBeOvertime, exceedsPermittedHours, workerMaxHours, workerPeriodHours
    , stationPreferenceRank, workerStationPrefs, workerPrefersVariety
    )
import Repo.Types (Repository(..))
import Service.Context (payPeriodChunks)
import Service.DraftValidation
    ( DraftViolation(..), validateAssignment, judgementContext )
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
-- 'SevViolation' outranks the rest because a violation is always actionable and
-- sometimes legally material, where understaffing may be survivable.
-- 'SevUnscheduled' sits above 'SevUnderstaffed' because a day nobody has staffed
-- at all blocks more than a thin station does. The choice is deliberately
-- low-stakes: severity decides only which kind a cell /announces/, and every cell
-- also reports its earliest affected date and lists everything in it when opened.
-- See ADR 0006 and ADR 0007.
data Severity
    = SevCompromise
    | SevUnderstaffed
    | SevUnscheduled
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
    | PUnscheduled !Day
      -- ^ A day that expects staff and has no assignments at all. Not the same
      -- fact as understaffing, and reported instead of it for that day — see
      -- ADR 0007.
    | PCompromise !Assignment !CompromiseKind
      -- ^ A legal assignment that ignores a stated preference. One per
      -- assignment per kind, like a violation, so it lands in every projection
      -- with no new plumbing; never reported for an assignment that is already a
      -- violation, because a broken rule outranks a disappointed preference.
    deriving (Eq, Show)

-- | The three compromises with a derivation, from ADR 0006. Each carries what its
--   sentence needs and nothing else.
data CompromiseKind
    = AuthorisedOvertime !DiffTime !DiffTime
      -- ^ Hours past the worker's regular per-period limit that their overtime
      -- model and opt-in permit: the worker's total for the period, and the cap.
    | StationNotPreferred ![StationId]
      -- ^ The station is not in the worker's non-empty preference list, which
      -- follows. A worker with no preferences was not disappointed.
    | VarietyRepeat !Day
      -- ^ A worker who prefers variety is on a station they held on the given
      -- earlier day, inside the same three-day window the scheduler scores.
    deriving (Eq, Show)

-- | The worker a problem is about, if any. Understaffing has none: nobody is
-- there, which is the problem. Neither has an unscheduled day, for the same
-- reason at a larger scale.
problemWorker :: Problem -> Maybe WorkerId
problemWorker (PViolation v)          = Just (assignWorker (dvAssignment v))
problemWorker (PUnderstaffed _ _ _ _) = Nothing
problemWorker (PUnscheduled _)        = Nothing
problemWorker (PCompromise a _)       = Just (assignWorker a)

-- | The station a problem is about, if any. An unscheduled day is about the whole
-- restaurant, so it names no station: it would otherwise appear once per station
-- and be the very per-station report it replaces.
problemStation :: Problem -> Maybe StationId
problemStation (PViolation v)           = Just (assignStation (dvAssignment v))
problemStation (PUnderstaffed st _ _ _) = Just st
problemStation (PUnscheduled _)         = Nothing
problemStation (PCompromise a _)        = Just (assignStation a)

problemScope :: Problem -> ProblemScope
problemScope (PViolation v)          = ScopeSlot (assignSlot (dvAssignment v))
problemScope (PUnderstaffed _ t _ _) = ScopeSlot t
problemScope (PUnscheduled d)        = ScopeDay d
problemScope (PCompromise a _)       = ScopeSlot (assignSlot a)

problemSeverity :: Problem -> Severity
problemSeverity (PViolation _)          = SevViolation
problemSeverity (PUnderstaffed _ _ _ _) = SevUnderstaffed
problemSeverity (PUnscheduled _)        = SevUnscheduled
problemSeverity (PCompromise _ _)       = SevCompromise

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
-- 'Service.DraftValidation.validateSchedule'. Staffing problems are computed
-- against the slots the range is expected to have staffed: every generated slot
-- crossed with every station, minus the station-slot pairs that fall outside a
-- station's operating hours.
--
-- A station whose 'stationMinStaff' is zero is __not__ understaffed by having
-- nobody on it. It is simply not being staffed, which is a fact about the
-- restaurant rather than a problem — see the Understaffing entry in
-- @CONTEXT.md@.
computeProblems :: Repository -> (Day, Day) -> IO [Problem]
computeProblems repo range@(from, to) = do
    calSched <- Cal.loadCalendarSlice repo from to
    staffing <- computeStaffingProblems repo range calSched
    -- One context per pay period, as 'validateSchedule' does: the hour rules
    -- measure against the context's period, and this range spans two whenever
    -- the problem view asks.
    chunks <- payPeriodChunks repo range
    judged <- concat <$> mapM (judgeChunk calSched) chunks
    return (judged ++ staffing)
  where
    judgeChunk calSched chunk@(cFrom, cTo) = do
        let inChunk a = let d = slotDate (assignSlot a) in d >= cFrom && d <= cTo
            part = Schedule (Set.filter inChunk (unSchedule calSched))
            assignments = Set.toList (unSchedule part)
        if null assignments
            then return []
            else do
                -- One context and one joined look-back for violations and
                -- compromises alike, so "authorised overtime" and "period
                -- hours" are read off the same hour count.
                (ctx, combined) <- judgementContext repo chunk part
                let violations = [ v | a <- assignments
                                     , Just v <- [validateAssignment ctx a combined] ]
                    violating  = Set.fromList (map dvAssignment violations)
                    compromises = concat
                        [ map (PCompromise a) (compromisesOf ctx combined a)
                        | a <- assignments
                        , not (Set.member a violating)
                        ]
                return (map PViolation violations ++ compromises)

-- | The compromises one legal assignment embodies. The context and schedule are
--   the ones the validator judged with, look-back included.
--
--   Each test is the scheduler's own scoring read backwards, as ADR 0006 puts it:
--   permitted overtime is 'wouldBeOvertime' without 'exceedsPermittedHours'; an
--   absent preference bonus is a station missing from a non-empty list; a variety
--   penalty is a repeat inside the three-day window 'scoreSlotWorker' uses.
compromisesOf :: SchedulerContext -> Schedule -> Assignment -> [CompromiseKind]
compromisesOf ctx sched a = concat [overtime, notPreferred, repeatStation]
  where
    wctx   = schWorkerCtx ctx
    bounds@(periodStart, periodEnd) = schPeriodBounds ctx
    calHrs = schCalendarHours ctx
    w      = assignWorker a
    st     = assignStation a
    day    = slotDate (assignSlot a)

    overtime
        | wouldBeOvertime wctx bounds calHrs sched a
        , not (exceedsPermittedHours wctx bounds calHrs sched a)
        , Just cap <- workerMaxHours wctx w =
            let total = workerPeriodHours w periodStart periodEnd sched
                      + Map.findWithDefault 0 w calHrs
            in [AuthorisedOvertime total cap]
        | otherwise = []

    notPreferred =
        let prefs = workerStationPrefs wctx w
        in case stationPreferenceRank wctx w st of
            Nothing | not (null prefs) -> [StationNotPreferred prefs]
            _                          -> []

    -- The most recent earlier day in the window on which the worker held this
    -- same station. Same window as 'scoreSlotWorker': the three days before.
    repeatStation
        | workerPrefersVariety wctx w =
            let earlier =
                    [ slotDate (assignSlot b)
                    | b <- Set.toList (byWorker w sched)
                    , assignStation b == st
                    , let d = slotDate (assignSlot b)
                    , d >= addDays (-3) day, d < day
                    ]
            in [ VarietyRepeat (maximum earlier) | not (null earlier) ]
        | otherwise = []

-- | Days nobody has staffed at all, and station-slots staffed below their
-- minimum.
--
-- These are computed together because they are alternatives. A day that expects
-- staff and holds no assignments whatsoever is __unscheduled__, reported once for
-- the day, and its station-slots are /not/ also reported understaffed: the admin's
-- situation there is "I have not built this period yet", not one problem per open
-- station-slot. Understaffing presupposes an attempt to staff. ADR 0007.
--
-- A day on which the restaurant expects nobody — every station either closed or
-- at a zero minimum — is neither unscheduled nor understaffed. It is a day off,
-- which is the same reasoning the zero-minimum station already gets.
computeStaffingProblems :: Repository -> (Day, Day) -> Schedule -> IO [Problem]
computeStaffingProblems repo (from, to) sched = do
    stations <- repoListStations repo
    skillCtx <- repoLoadSkillCtx repo
    let slots  = generateDateRangeSlots defaultHours from to Set.empty
        closed = stationClosedSlots skillCtx slots
        -- The station-slots the range is expected to have staffed.
        expected =
            [ (st, t, stationMinStaff station)
            | (st, station) <- stations
            , stationMinStaff station > 0
            , t <- slots
            , not (Set.member (st, t) closed)
            ]
        -- Any assignment at all counts as an attempt, including one onto a
        -- zero-minimum station: the question is whether the day was worked on.
        attempted   = Set.map (slotDate . assignSlot) (unSchedule sched)
        expecting   = Set.fromList [slotDate t | (_, t, _) <- expected]
        unscheduled = expecting `Set.difference` attempted
    return $
        map PUnscheduled (Set.toList unscheduled)
            ++ [ PUnderstaffed st t assigned required
               | (st, t, required) <- expected
               , not (Set.member (slotDate t) unscheduled)
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
