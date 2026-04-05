module Service.Absence
    ( AbsenceError(..)
    , requestAbsenceService
    , approveAbsenceService
    , approveAbsenceOverrideService
    , rejectAbsenceService
    , listPendingAbsences
    , listWorkerAbsences
    , vacationRemaining
    , loadAbsenceCtx
    ) where

import qualified Data.Map.Strict as Map
import Data.Time (Day)

import Domain.Types (WorkerId, AbsenceId, AbsenceTypeId)
import Domain.Absence
    ( AbsenceContext(..), AbsenceRequest(..), AbsenceStatus(..)
    , requestAbsence, approveAbsence, approveAbsenceOverride, rejectAbsence
    , vacationDaysRemaining, workerAbsencesInRange
    )
import Repo.Types (Repository(..))

data AbsenceError
    = AbsenceNotFound
    | AbsenceAllowanceExceeded
    | UnknownAbsenceType
    deriving (Eq, Show)

-- | Request an absence for a worker.
requestAbsenceService :: Repository -> WorkerId -> AbsenceTypeId -> Day -> Day
                      -> IO (Either AbsenceError AbsenceId)
requestAbsenceService repo wid tid startDay endDay = do
    ctx <- repoLoadAbsenceCtx repo
    if not (Map.member tid (acTypes ctx))
        then return (Left UnknownAbsenceType)
        else do
            let (ctx', aid) = requestAbsence wid tid startDay endDay ctx
            repoSaveAbsenceCtx repo ctx'
            return (Right aid)

-- | Approve an absence request (respects allowance limits).
approveAbsenceService :: Repository -> AbsenceId -> IO (Either AbsenceError ())
approveAbsenceService repo aid = do
    ctx <- repoLoadAbsenceCtx repo
    case Map.lookup aid (acRequests ctx) of
        Nothing -> return (Left AbsenceNotFound)
        Just _  ->
            case approveAbsence aid ctx of
                Nothing   -> return (Left AbsenceAllowanceExceeded)
                Just ctx' -> do
                    repoSaveAbsenceCtx repo ctx'
                    return (Right ())

-- | Approve an absence request (override allowance check).
approveAbsenceOverrideService :: Repository -> AbsenceId -> IO (Either AbsenceError ())
approveAbsenceOverrideService repo aid = do
    ctx <- repoLoadAbsenceCtx repo
    case Map.lookup aid (acRequests ctx) of
        Nothing -> return (Left AbsenceNotFound)
        Just _  ->
            case approveAbsenceOverride aid ctx of
                Nothing   -> return (Left AbsenceNotFound)
                Just ctx' -> do
                    repoSaveAbsenceCtx repo ctx'
                    return (Right ())

-- | Reject an absence request.
rejectAbsenceService :: Repository -> AbsenceId -> IO (Either AbsenceError ())
rejectAbsenceService repo aid = do
    ctx <- repoLoadAbsenceCtx repo
    case Map.lookup aid (acRequests ctx) of
        Nothing -> return (Left AbsenceNotFound)
        Just _  ->
            case rejectAbsence aid ctx of
                Nothing   -> return (Left AbsenceNotFound)
                Just ctx' -> do
                    repoSaveAbsenceCtx repo ctx'
                    return (Right ())

-- | List all pending absence requests.
listPendingAbsences :: Repository -> IO [AbsenceRequest]
listPendingAbsences repo = do
    ctx <- repoLoadAbsenceCtx repo
    return [ar | ar <- Map.elems (acRequests ctx), arStatus ar == Pending]

-- | List a worker's absences in a date range.
listWorkerAbsences :: Repository -> WorkerId -> Day -> Day -> IO [AbsenceRequest]
listWorkerAbsences repo wid startDay endDay = do
    ctx <- repoLoadAbsenceCtx repo
    return (workerAbsencesInRange wid startDay endDay ctx)

-- | Check how many vacation days a worker has remaining.
-- Returns Nothing if the absence type has no yearly limit.
vacationRemaining :: Repository -> WorkerId -> AbsenceTypeId -> Integer -> IO (Maybe Int)
vacationRemaining repo wid tid year = do
    ctx <- repoLoadAbsenceCtx repo
    return (vacationDaysRemaining wid tid year ctx)

loadAbsenceCtx :: Repository -> IO AbsenceContext
loadAbsenceCtx = repoLoadAbsenceCtx
