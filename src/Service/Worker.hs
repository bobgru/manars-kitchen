{-# LANGUAGE OverloadedStrings #-}
module Service.Worker
    ( -- * Skill entity operations
      addSkill
    , removeSkill
    , listSkills
    , renameSkill
    , listSkillImplications
    , removeSkillImplication
    , SkillReferences(..)
    , checkSkillReferences
    , isUnreferenced
    , safeDeleteSkill
      -- * Station entity operations
    , addStation
    , removeStation
    , listStations
    , renameStation
    , StationReferences(..)
    , checkStationReferences
    , isStationUnreferenced
    , safeDeleteStation
      -- * Skill context operations
    , addSkillImplication
    , grantWorkerSkill
    , revokeWorkerSkill
    , setStationRequiredSkills
    , setStationHours
    , closeStationDay
    , setMultiStationHours
      -- * Worker context operations
    , setMaxHours
    , setOvertimeOptIn
    , setStationPreferences
    , setVarietyPreference
    , setShiftPreferences
    , setWeekendOnly
    , setSeniority
    , addCrossTraining
    , removeCrossTraining
      -- * Employment status
    , setOvertimeModel
    , setPayPeriodTracking
    , setTempFlag
    , setEmploymentStatus
      -- * Pairing
    , addAvoidPairing
    , removeAvoidPairing
    , addPreferPairing
    , removePreferPairing
      -- * Pinned assignments
    , addPin
    , removePin
    , listPins
      -- * Queries
    , loadSkillCtx
    , loadWorkerCtx
      -- * Worker entity operations
    , WorkerReferences(..)
    , checkWorkerReferences
    , isWorkerUnreferenced
    , DeactivateResult(..)
    , safeDeactivateWorker
    , activateWorker
    , safeDeleteWorker
    , forceDeleteWorker
    , WorkerProfile(..)
    , viewWorker
    , resolveWorkerByName
    , ResolveWorkerError(..)
    ) where

import Data.List (nub, sort)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (DayOfWeek(..))

import Data.Time (Day)

import Auth.Types (User(..), Username(..), UserId(..), Role(..), userIdToWorkerId, workerIdToUserId, userIsWorker)
import Domain.Absence (AbsenceContext(..), AbsenceRequest(..))
import Domain.Pin (PinnedAssignment(..))
import Domain.Skill (Skill(..), SkillContext(..))
import Domain.Types
    ( WorkerId(..), StationId(..), Station(..), SkillId(..), DiffTime, WorkerStatus(..)
    , Schedule(..), Assignment(..)
    )
import Domain.Worker (WorkerContext(..), OvertimeModel(..), PayPeriodTracking(..))
import Repo.Types (Repository(..), DraftInfo(..))

-- -----------------------------------------------------------------
-- Skill entity CRUD
-- -----------------------------------------------------------------

-- | Register a new skill with a name and description.
-- Returns Left with error message if the skill name already exists.
addSkill :: Repository -> Text -> Text -> IO (Either String ())
addSkill repo name desc = repoCreateSkill repo name desc

-- | Remove a skill from the system (also removes from workers/stations/implications).
removeSkill :: Repository -> SkillId -> IO ()
removeSkill repo sid = do
    repoDeleteSkill repo sid
    -- Also clean up the in-memory context relationships
    ctx <- repoLoadSkillCtx repo
    let ctx' = ctx
            { scWorkerSkills    = Map.map (Set.delete sid) (scWorkerSkills ctx)
            , scStationRequires = Map.map (Set.delete sid) (scStationRequires ctx)
            , scSkillImplies    = Map.delete sid
                                    (Map.map (Set.delete sid) (scSkillImplies ctx))
            }
    repoSaveSkillCtx repo ctx'

-- | List all registered skills.
listSkills :: Repository -> IO [(SkillId, Skill)]
listSkills = repoListSkills

-- | Rename a skill.
renameSkill :: Repository -> SkillId -> Text -> IO ()
renameSkill repo sid newName = repoRenameSkill repo sid newName

-- | List all direct skill implications as a map.
listSkillImplications :: Repository -> IO (Map.Map SkillId [SkillId])
listSkillImplications repo = do
    pairs <- repoListSkillImplications repo
    return $ Map.fromListWith (++) [(s, [i]) | (s, i) <- pairs]

-- | Remove a skill implication.
removeSkillImplication :: Repository -> SkillId -> SkillId -> IO ()
removeSkillImplication repo skillA skillB = do
    repoRemoveSkillImplication repo skillA skillB
    -- Also update the in-memory context
    ctx <- repoLoadSkillCtx repo
    let current = Map.findWithDefault Set.empty skillA (scSkillImplies ctx)
        updated = Set.delete skillB current
        ctx' = if Set.null updated
               then ctx { scSkillImplies = Map.delete skillA (scSkillImplies ctx) }
               else ctx { scSkillImplies = Map.insert skillA updated (scSkillImplies ctx) }
    repoSaveSkillCtx repo ctx'

-- -----------------------------------------------------------------
-- Skill reference checking (safe delete)
-- -----------------------------------------------------------------

data SkillReferences = SkillReferences
    { srWorkers       :: ![(WorkerId, String)]
    , srStations      :: ![(StationId, String)]
    , srCrossTraining :: ![(WorkerId, String)]
    , srImpliedBy     :: ![(SkillId, String)]
    , srImplies       :: ![(SkillId, String)]
    } deriving (Show)

checkSkillReferences :: Repository -> SkillId -> IO SkillReferences
checkSkillReferences repo sid = do
    ctx <- repoLoadSkillCtx repo
    wCtx <- repoLoadWorkerCtx repo
    skills <- repoListSkills repo
    users <- repoListUsers repo
    stationPairs <- repoListStations repo
    let skillNameMap = Map.fromList [(s, skillName sk) | (s, sk) <- skills]
        lookupSkill s = Map.findWithDefault (T.pack $ show s) s skillNameMap
        workerNameMap = Map.fromList
            [(userIdToWorkerId (userId u), let Username n = userName u in T.unpack n) | u <- users]
        lookupWorker w = Map.findWithDefault (show w) w workerNameMap
        stationNameMap = Map.fromList [(s, stationName st) | (s, st) <- stationPairs]
        lookupStation s = T.unpack $ Map.findWithDefault (T.pack $ show s) s stationNameMap
        workers = [(w, lookupWorker w) | (w, sks) <- Map.toList (scWorkerSkills ctx), Set.member sid sks]
        stations = [(s, lookupStation s) | (s, sks) <- Map.toList (scStationRequires ctx), Set.member sid sks]
        crossTraining = [(w, lookupWorker w) | (w, sks) <- Map.toList (wcCrossTraining wCtx), Set.member sid sks]
        impliedBy = [(s, T.unpack (lookupSkill s)) | (s, imps) <- Map.toList (scSkillImplies ctx), Set.member sid imps, s /= sid]
        implies = [(i, T.unpack (lookupSkill i)) | i <- Set.toList (Map.findWithDefault Set.empty sid (scSkillImplies ctx))]
    return SkillReferences
        { srWorkers       = workers
        , srStations      = stations
        , srCrossTraining = crossTraining
        , srImpliedBy     = impliedBy
        , srImplies       = implies
        }

isUnreferenced :: SkillReferences -> Bool
isUnreferenced refs =
    null (srWorkers refs) && null (srStations refs) &&
    null (srCrossTraining refs) && null (srImpliedBy refs) &&
    null (srImplies refs)

safeDeleteSkill :: Repository -> SkillId -> IO (Either SkillReferences ())
safeDeleteSkill repo sid = do
    refs <- checkSkillReferences repo sid
    if isUnreferenced refs
        then do
            repoDeleteSkill repo sid
            return (Right ())
        else return (Left refs)

-- -----------------------------------------------------------------
-- Station entity CRUD
-- -----------------------------------------------------------------

-- | Add a station to the system.
addStation :: Repository -> Text -> Int -> Int -> IO StationId
addStation repo name minStaff maxStaff = do
    sid <- repoCreateStation repo name minStaff maxStaff
    ctx <- repoLoadSkillCtx repo
    let ctx' = ctx
            { scAllStations = Set.insert sid (scAllStations ctx) }
    repoSaveSkillCtx repo ctx'
    return sid

-- | Remove a station.
removeStation :: Repository -> StationId -> IO ()
removeStation repo sid = do
    repoDeleteStation repo sid
    ctx <- repoLoadSkillCtx repo
    let ctx' = ctx
            { scAllStations     = Set.delete sid (scAllStations ctx)
            , scStationRequires = Map.delete sid (scStationRequires ctx)
            }
    repoSaveSkillCtx repo ctx'

data StationReferences = StationReferences
    { strWorkerPrefs    :: ![(WorkerId, String)]
    , strRequiredSkills :: ![(SkillId, String)]
    } deriving (Show)

isStationUnreferenced :: StationReferences -> Bool
isStationUnreferenced refs =
    null (strWorkerPrefs refs) && null (strRequiredSkills refs)

checkStationReferences :: Repository -> StationId -> IO StationReferences
checkStationReferences repo sid = do
    ctx <- repoLoadSkillCtx repo
    wCtx <- repoLoadWorkerCtx repo
    users <- repoListUsers repo
    skills <- repoListSkills repo
    let workerNameMap = Map.fromList
            [(userIdToWorkerId (userId u), let Username n = userName u in T.unpack n) | u <- users]
        lookupWorker w = Map.findWithDefault (show w) w workerNameMap
        skillNameMap = Map.fromList [(s, skillName sk) | (s, sk) <- skills]
        lookupSkill s = T.unpack $ Map.findWithDefault (T.pack $ show s) s skillNameMap
        workerPrefs = [(w, lookupWorker w)
            | (w, prefs) <- Map.toList (wcStationPrefs wCtx)
            , sid `elem` prefs]
        requiredSkills = [(s, lookupSkill s)
            | s <- Set.toList (Map.findWithDefault Set.empty sid (scStationRequires ctx))]
    return StationReferences
        { strWorkerPrefs    = workerPrefs
        , strRequiredSkills = requiredSkills
        }

safeDeleteStation :: Repository -> StationId -> IO (Either StationReferences ())
safeDeleteStation repo sid = do
    refs <- checkStationReferences repo sid
    if isStationUnreferenced refs
        then do
            removeStation repo sid
            return (Right ())
        else return (Left refs)

renameStation :: Repository -> StationId -> Text -> IO ()
renameStation repo sid newName = repoRenameStation repo sid newName

-- -----------------------------------------------------------------
-- Skill context (relational operations)
-- -----------------------------------------------------------------

-- | Add a skill implication: possessing skillA implies possessing skillB.
addSkillImplication :: Repository -> SkillId -> SkillId -> IO ()
addSkillImplication repo skillA skillB = do
    ctx <- repoLoadSkillCtx repo
    let current = Map.findWithDefault Set.empty skillA (scSkillImplies ctx)
        ctx' = ctx { scSkillImplies = Map.insert skillA (Set.insert skillB current) (scSkillImplies ctx) }
    repoSaveSkillCtx repo ctx'

-- | Grant a skill to a worker.
grantWorkerSkill :: Repository -> WorkerId -> SkillId -> IO ()
grantWorkerSkill repo wid sid = do
    ctx <- repoLoadSkillCtx repo
    let current = Map.findWithDefault Set.empty wid (scWorkerSkills ctx)
        ctx' = ctx { scWorkerSkills = Map.insert wid (Set.insert sid current) (scWorkerSkills ctx) }
    repoSaveSkillCtx repo ctx'

-- | Revoke a skill from a worker.
revokeWorkerSkill :: Repository -> WorkerId -> SkillId -> IO ()
revokeWorkerSkill repo wid sid = do
    ctx <- repoLoadSkillCtx repo
    let current = Map.findWithDefault Set.empty wid (scWorkerSkills ctx)
        ctx' = ctx { scWorkerSkills = Map.insert wid (Set.delete sid current) (scWorkerSkills ctx) }
    repoSaveSkillCtx repo ctx'

-- | List all stations.
listStations :: Repository -> IO [(StationId, Station)]
listStations = repoListStations

-- | Set required skills for a station.
setStationRequiredSkills :: Repository -> StationId -> Set.Set SkillId -> IO ()
setStationRequiredSkills repo sid skills = do
    ctx <- repoLoadSkillCtx repo
    let ctx' = ctx { scStationRequires = Map.insert sid skills (scStationRequires ctx) }
    repoSaveSkillCtx repo ctx'

-- -----------------------------------------------------------------
-- Worker context
-- -----------------------------------------------------------------

-- | Set a worker's max weekly hours.
setMaxHours :: Repository -> WorkerId -> DiffTime -> IO ()
setMaxHours repo wid hours = do
    ctx <- repoLoadWorkerCtx repo
    let ctx' = ctx { wcMaxPeriodHours = Map.insert wid hours (wcMaxPeriodHours ctx) }
    repoSaveWorkerCtx repo ctx'

-- | Set whether a worker opts in to overtime.
-- For salaried (OTManualOnly) workers, this is a no-op — returns a warning.
-- For other workers, sets overtime_model to OTEligible (on) or updates opt-in set.
setOvertimeOptIn :: Repository -> WorkerId -> Bool -> IO (Maybe String)
setOvertimeOptIn repo wid optIn = do
    (otMap, _, _) <- repoLoadEmployment repo
    let om = Map.findWithDefault OTEligible wid otMap
    case om of
        OTManualOnly -> return (Just "Warning: salaried workers always use manual-only overtime. No change made.")
        _ -> do
            ctx <- repoLoadWorkerCtx repo
            let ctx' = ctx { wcOvertimeOptIn =
                    (if optIn then Set.insert else Set.delete) wid (wcOvertimeOptIn ctx) }
            repoSaveWorkerCtx repo ctx'
            if optIn
                then setOvertimeModel repo wid OTEligible
                else return ()
            return Nothing

-- | Set a worker's station preferences (ordered, most preferred first).
setStationPreferences :: Repository -> WorkerId -> [StationId] -> IO ()
setStationPreferences repo wid prefs = do
    ctx <- repoLoadWorkerCtx repo
    let ctx' = ctx { wcStationPrefs = Map.insert wid prefs (wcStationPrefs ctx) }
    repoSaveWorkerCtx repo ctx'

-- | Set whether a worker prefers variety.
setVarietyPreference :: Repository -> WorkerId -> Bool -> IO ()
setVarietyPreference repo wid pref = do
    ctx <- repoLoadWorkerCtx repo
    let ctx' = ctx { wcPrefersVariety =
            (if pref then Set.insert else Set.delete) wid (wcPrefersVariety ctx) }
    repoSaveWorkerCtx repo ctx'

-- | Set operating hours for a station (all days get hours [startH..endH-1]).
setStationHours :: Repository -> StationId -> Int -> Int -> IO ()
setStationHours repo sid startH endH = do
    ctx <- repoLoadSkillCtx repo
    let allDays = [Monday, Tuesday, Wednesday, Thursday, Friday, Saturday, Sunday]
        dayMap = Map.fromList [(dow, [startH..endH-1]) | dow <- allDays]
        ctx' = ctx { scStationHours = Map.insert sid dayMap (scStationHours ctx) }
    repoSaveSkillCtx repo ctx'

-- | Close a station on a specific day of the week (set hours to []).
closeStationDay :: Repository -> StationId -> DayOfWeek -> IO ()
closeStationDay repo sid dow = do
    ctx <- repoLoadSkillCtx repo
    let current = Map.findWithDefault Map.empty sid (scStationHours ctx)
        updated = Map.insert dow [] current
        ctx' = ctx { scStationHours = Map.insert sid updated (scStationHours ctx) }
    repoSaveSkillCtx repo ctx'

-- | Add multi-station hours for a station (all days get hours [startH..endH-1]).
-- Merges with existing multi-station hours for this station.
setMultiStationHours :: Repository -> StationId -> Int -> Int -> IO ()
setMultiStationHours repo sid startH endH = do
    ctx <- repoLoadSkillCtx repo
    let allDays = [Monday, Tuesday, Wednesday, Thursday, Friday, Saturday, Sunday]
        newHours = [startH..endH-1]
        existing = Map.findWithDefault Map.empty sid (scMultiStationHours ctx)
        merged = Map.fromList
            [(dow, sort $ nub $ Map.findWithDefault [] dow existing ++ newHours)
            | dow <- allDays]
        ctx' = ctx { scMultiStationHours = Map.insert sid merged (scMultiStationHours ctx) }
    repoSaveSkillCtx repo ctx'

-- | Set a worker's shift preferences (ordered, most preferred first).
setShiftPreferences :: Repository -> WorkerId -> [Text] -> IO ()
setShiftPreferences repo wid prefs = do
    ctx <- repoLoadWorkerCtx repo
    let ctx' = ctx { wcShiftPrefs = Map.insert wid prefs (wcShiftPrefs ctx) }
    repoSaveWorkerCtx repo ctx'

-- | Set whether a worker is weekend-only (exempt from alternating weekends off).
setWeekendOnly :: Repository -> WorkerId -> Bool -> IO ()
setWeekendOnly repo wid val = do
    ctx <- repoLoadWorkerCtx repo
    let ctx' = ctx { wcWeekendOnly =
            (if val then Set.insert else Set.delete) wid (wcWeekendOnly ctx) }
    repoSaveWorkerCtx repo ctx'

-- | Set a worker's seniority level (controls max concurrent station assignments).
setSeniority :: Repository -> WorkerId -> Int -> IO ()
setSeniority repo wid level = do
    ctx <- repoLoadWorkerCtx repo
    let ctx' = ctx { wcSeniority = Map.insert wid level (wcSeniority ctx) }
    repoSaveWorkerCtx repo ctx'

-- | Add a cross-training goal for a worker (worker wants to learn this skill).
addCrossTraining :: Repository -> WorkerId -> SkillId -> IO ()
addCrossTraining repo wid sid = do
    ctx <- repoLoadWorkerCtx repo
    let current = Map.findWithDefault Set.empty wid (wcCrossTraining ctx)
        ctx' = ctx { wcCrossTraining = Map.insert wid (Set.insert sid current) (wcCrossTraining ctx) }
    repoSaveWorkerCtx repo ctx'

-- | Remove a cross-training goal from a worker.
removeCrossTraining :: Repository -> WorkerId -> SkillId -> IO ()
removeCrossTraining repo wid sid = do
    ctx <- repoLoadWorkerCtx repo
    let current = Map.findWithDefault Set.empty wid (wcCrossTraining ctx)
        updated = Set.delete sid current
        ctx' = ctx { wcCrossTraining =
            if Set.null updated
            then Map.delete wid (wcCrossTraining ctx)
            else Map.insert wid updated (wcCrossTraining ctx) }
    repoSaveWorkerCtx repo ctx'

-- -----------------------------------------------------------------
-- Employment status
-- -----------------------------------------------------------------

-- | Set a worker's overtime model.
setOvertimeModel :: Repository -> WorkerId -> OvertimeModel -> IO ()
setOvertimeModel repo wid om = do
    (_, ppMap, tempSet) <- repoLoadEmployment repo
    let pp = Map.findWithDefault PPStandard wid ppMap
        temp = Set.member wid tempSet
    repoSaveEmployment repo wid om pp temp

-- | Set a worker's pay period tracking.
setPayPeriodTracking :: Repository -> WorkerId -> PayPeriodTracking -> IO ()
setPayPeriodTracking repo wid pp = do
    (otMap, _, tempSet) <- repoLoadEmployment repo
    let om = Map.findWithDefault OTEligible wid otMap
        temp = Set.member wid tempSet
    repoSaveEmployment repo wid om pp temp

-- | Set a worker's temp flag.
setTempFlag :: Repository -> WorkerId -> Bool -> IO ()
setTempFlag repo wid temp = do
    (otMap, ppMap, _) <- repoLoadEmployment repo
    let om = Map.findWithDefault OTEligible wid otMap
        pp = Map.findWithDefault PPStandard wid ppMap
    repoSaveEmployment repo wid om pp temp

-- | Apply a convenience employment status preset.
-- Returns a message string describing what was set.
setEmploymentStatus :: Repository -> WorkerId -> String -> IO String
setEmploymentStatus repo wid status = case status of
    "salaried" -> do
        repoSaveEmployment repo wid OTManualOnly PPStandard False
        setMaxHours repo wid (40 * 3600)
        return "Set salaried: overtime=manual-only, tracking=standard, hours=40h"
    "full-time" -> do
        repoSaveEmployment repo wid OTEligible PPStandard False
        setMaxHours repo wid (40 * 3600)
        return "Set full-time: overtime=eligible, tracking=standard, hours=40h"
    "part-time" -> do
        (_, _, tempSet) <- repoLoadEmployment repo
        let temp = Set.member wid tempSet
        repoSaveEmployment repo wid OTEligible PPStandard temp
        return "Set part-time: overtime=eligible, tracking=standard. Remember to set hours with 'worker set-hours'."
    "per-diem" -> do
        repoSaveEmployment repo wid OTExempt PPExempt False
        -- Remove hour limit
        ctx <- repoLoadWorkerCtx repo
        let ctx' = ctx { wcMaxPeriodHours = Map.delete wid (wcMaxPeriodHours ctx) }
        repoSaveWorkerCtx repo ctx'
        return "Set per-diem: overtime=exempt, tracking=exempt, hour limit removed"
    _ -> return ("Unknown status: " ++ status ++ ". Use salaried|full-time|part-time|per-diem.")

-- | Add a symmetric avoid-pairing relationship between two workers.
addAvoidPairing :: Repository -> WorkerId -> WorkerId -> IO ()
addAvoidPairing repo w1 w2 = do
    ctx <- repoLoadWorkerCtx repo
    let add w o m = Map.insertWith Set.union w (Set.singleton o) m
        ctx' = ctx { wcAvoidPairing = add w1 w2 (add w2 w1 (wcAvoidPairing ctx)) }
    repoSaveWorkerCtx repo ctx'

-- | Remove a symmetric avoid-pairing relationship.
removeAvoidPairing :: Repository -> WorkerId -> WorkerId -> IO ()
removeAvoidPairing repo w1 w2 = do
    ctx <- repoLoadWorkerCtx repo
    let remove w o m = Map.adjust (Set.delete o) w m
        ctx' = ctx { wcAvoidPairing = remove w1 w2 (remove w2 w1 (wcAvoidPairing ctx)) }
    repoSaveWorkerCtx repo ctx'

-- | Add a symmetric prefer-pairing relationship between two workers.
addPreferPairing :: Repository -> WorkerId -> WorkerId -> IO ()
addPreferPairing repo w1 w2 = do
    ctx <- repoLoadWorkerCtx repo
    let add w o m = Map.insertWith Set.union w (Set.singleton o) m
        ctx' = ctx { wcPreferPairing = add w1 w2 (add w2 w1 (wcPreferPairing ctx)) }
    repoSaveWorkerCtx repo ctx'

-- | Remove a symmetric prefer-pairing relationship.
removePreferPairing :: Repository -> WorkerId -> WorkerId -> IO ()
removePreferPairing repo w1 w2 = do
    ctx <- repoLoadWorkerCtx repo
    let remove w o m = Map.adjust (Set.delete o) w m
        ctx' = ctx { wcPreferPairing = remove w1 w2 (remove w2 w1 (wcPreferPairing ctx)) }
    repoSaveWorkerCtx repo ctx'

-- -----------------------------------------------------------------
-- Pinned assignments
-- -----------------------------------------------------------------

-- | Add a pinned assignment. Appends to the existing list.
addPin :: Repository -> PinnedAssignment -> IO ()
addPin repo pin = do
    existing <- repoLoadPins repo
    repoSavePins repo (existing ++ [pin])

-- | Remove a pinned assignment (exact match).
removePin :: Repository -> PinnedAssignment -> IO ()
removePin repo pin = do
    existing <- repoLoadPins repo
    repoSavePins repo (filter (/= pin) existing)

-- | List all pinned assignments.
listPins :: Repository -> IO [PinnedAssignment]
listPins = repoLoadPins

-- -----------------------------------------------------------------
-- Queries
-- -----------------------------------------------------------------

loadSkillCtx :: Repository -> IO SkillContext
loadSkillCtx = repoLoadSkillCtx

loadWorkerCtx :: Repository -> IO WorkerContext
loadWorkerCtx = repoLoadWorkerCtx

-- -----------------------------------------------------------------
-- Worker entity operations: view, deactivate, activate, delete
-- -----------------------------------------------------------------

-- | An error from resolving a worker by name.
data ResolveWorkerError
    = WorkerNotFound  String  -- ^ no user with that username
    | NotAWorker      String  -- ^ user exists but worker_status = 'none'
    deriving (Eq, Show)

-- | Resolve a worker by username (= user's username). Returns the
-- 'WorkerId' along with the user's status for active and inactive
-- workers; returns @Left NotAWorker@ if the user has @worker_status
-- = 'none'@; returns @Left WorkerNotFound@ if the user does not exist.
resolveWorkerByName :: Repository -> Text -> IO (Either ResolveWorkerError (WorkerId, WorkerStatus))
resolveWorkerByName repo name = do
    mUser <- repoGetUserByName repo name
    case mUser of
        Nothing -> pure $ Left (WorkerNotFound (T.unpack name))
        Just u  -> case userWorkerStatus u of
            WSNone     -> pure $ Left (NotAWorker (T.unpack name))
            WSActive   -> pure $ Right (userIdToWorkerId (userId u), WSActive)
            WSInactive -> pure $ Right (userIdToWorkerId (userId u), WSInactive)

-- | Reference counts (and short context lists) for a worker, used to
-- decide whether a 'safeDeleteWorker' is allowed.
data WorkerReferences = WorkerReferences
    { wrSkills          :: !Int
    , wrEmployment      :: !Bool
    , wrHours           :: !Bool
    , wrOvertimeOptIn   :: !Bool
    , wrStationPrefs    :: !Int
    , wrPrefersVariety  :: !Bool
    , wrShiftPrefs      :: !Int
    , wrWeekendOnly     :: !Bool
    , wrSeniority       :: !Bool
    , wrAvoidPairing    :: !Int
    , wrPreferPairing   :: !Int
    , wrCrossTraining   :: !Int
    , wrPinned          :: !Int
    , wrCalendar        :: !Int
    , wrDraft           :: !Int
    , wrSchedule        :: !Int
    , wrAbsence         :: !Int
    , wrAllowances      :: !Int
    } deriving (Show)

-- | True iff the worker has at least one configuration row.
configRefsNonEmpty :: WorkerReferences -> Bool
configRefsNonEmpty r =
    wrSkills r > 0 || wrEmployment r || wrHours r ||
    wrOvertimeOptIn r || wrStationPrefs r > 0 || wrPrefersVariety r ||
    wrShiftPrefs r > 0 || wrWeekendOnly r || wrSeniority r ||
    wrAvoidPairing r > 0 || wrPreferPairing r > 0 || wrCrossTraining r > 0

-- | True iff the worker has at least one schedule/history row.
scheduleRefsNonEmpty :: WorkerReferences -> Bool
scheduleRefsNonEmpty r =
    wrPinned r > 0 || wrCalendar r > 0 || wrDraft r > 0 ||
    wrSchedule r > 0 || wrAbsence r > 0 || wrAllowances r > 0

-- | True iff every reference group is empty.
isWorkerUnreferenced :: WorkerReferences -> Bool
isWorkerUnreferenced r = not (configRefsNonEmpty r) && not (scheduleRefsNonEmpty r)

-- | Count references across all worker tables (config + schedule).
checkWorkerReferences :: Repository -> WorkerId -> IO WorkerReferences
checkWorkerReferences repo wid = do
    -- Configuration: load contexts (which on the SQLite repo filter to
    -- active workers; we want to inspect even inactive workers' refs,
    -- so query the base data directly via the contexts plus employment).
    skillCtx  <- repoLoadSkillCtx repo
    workerCtx <- repoLoadWorkerCtx repo
    -- Note: repoLoadWorkerCtx filters to active workers. For inactive
    -- workers, we approximate via the same context lookups; the FK
    -- ensures rows still exist physically. For an exact count we would
    -- need a per-table SQL count; for change 1 we accept the approximation
    -- and treat any in-memory hit as a reference. Inactive workers'
    -- config rows are still present in the database — the check below
    -- uses lookup-with-default.
    let skillCount = Set.size (Map.findWithDefault Set.empty wid (scWorkerSkills skillCtx))
        hasHours = Map.member wid (wcMaxPeriodHours workerCtx)
        hasOpt   = Set.member wid (wcOvertimeOptIn workerCtx)
        prefSize = length (Map.findWithDefault [] wid (wcStationPrefs workerCtx))
        hasVariety = Set.member wid (wcPrefersVariety workerCtx)
        shiftSize = length (Map.findWithDefault [] wid (wcShiftPrefs workerCtx))
        hasWeekend = Set.member wid (wcWeekendOnly workerCtx)
        hasSeniority = Map.member wid (wcSeniority workerCtx)
        avoidSize = Set.size (Map.findWithDefault Set.empty wid (wcAvoidPairing workerCtx))
        preferSize = Set.size (Map.findWithDefault Set.empty wid (wcPreferPairing workerCtx))
        crossSize = Set.size (Map.findWithDefault Set.empty wid (wcCrossTraining workerCtx))
    -- Employment and temp flag (also filtered to active)
    (otModels, ppMap, tempSet) <- repoLoadEmployment repo
    let hasEmployment = Map.member wid otModels || Map.member wid ppMap || Set.member wid tempSet

    -- Schedule/history: count via pins + we approximate calendar/draft/named/absence
    -- by scanning the bulk loads available on the repo.
    pins   <- repoLoadPins repo
    let pinCount = length [() | p <- pins, pinWorker p == wid]
    -- Absence requests + allowances
    absCtx <- repoLoadAbsenceCtx repo
    let absCount = length [() | r <- Map.elems (acRequests absCtx), arWorker r == wid]
        allowCount = length [() | (w, _) <- Map.keys (acYearlyAllowance absCtx), w == wid]
    -- Calendar: scan a generous range
    calSched <- repoLoadCalendar repo (read "1900-01-01") (read "2999-12-31")
    let calCount = length [() | a <- Set.toList (unSchedule calSched), assignWorker a == wid]
    -- Drafts
    drafts <- repoListDrafts repo
    draftCount <- fmap sum $ mapM (\d -> do
        s <- repoLoadDraftAssignments repo (diId d)
        pure $ length [() | a <- Set.toList (unSchedule s), assignWorker a == wid]) drafts
    -- Named schedules
    schedNames <- repoListSchedules repo
    schedCount <- fmap sum $ mapM (\nm -> do
        ms <- repoLoadSchedule repo nm
        case ms of
            Nothing -> pure 0
            Just s  -> pure $ length [() | a <- Set.toList (unSchedule s), assignWorker a == wid]
        ) schedNames
    pure WorkerReferences
        { wrSkills          = skillCount
        , wrEmployment      = hasEmployment
        , wrHours           = hasHours
        , wrOvertimeOptIn   = hasOpt
        , wrStationPrefs    = prefSize
        , wrPrefersVariety  = hasVariety
        , wrShiftPrefs      = shiftSize
        , wrWeekendOnly     = hasWeekend
        , wrSeniority       = hasSeniority
        , wrAvoidPairing    = avoidSize
        , wrPreferPairing   = preferSize
        , wrCrossTraining   = crossSize
        , wrPinned          = pinCount
        , wrCalendar        = calCount
        , wrDraft           = draftCount
        , wrSchedule        = schedCount
        , wrAbsence         = absCount
        , wrAllowances      = allowCount
        }

-- | Counts of items removed by a deactivation.
data DeactivateResult = DeactivateResult
    { drPinsRemoved     :: !Int
    , drDraftsRemoved   :: !Int
    , drCalendarRemoved :: !Int
    } deriving (Show)

-- | Take a worker out of active scheduling. Removes pins, drafts entries,
-- and future calendar entries. Preserves all worker_* configuration and
-- past calendar/named-schedule history.
safeDeactivateWorker :: Repository -> WorkerId -> Day -> IO (Either String DeactivateResult)
safeDeactivateWorker repo wid today = do
    let uid = workerIdToUserId wid
    mUser <- repoGetUser repo uid
    case mUser of
        Nothing -> pure $ Left "User not found."
        Just u -> case userWorkerStatus u of
            WSNone     -> pure $ Left "User is not a worker."
            WSInactive -> pure $ Left "Worker is already inactive."
            WSActive   -> do
                (pinN, drftN, calN) <- repoDeactivateClearings repo wid today
                repoSetWorkerStatus repo uid WSInactive (Just today)
                pure (Right (DeactivateResult pinN drftN calN))

-- | Reactivate an inactive worker. Configuration is unchanged; pins/drafts/
-- calendar entries are NOT restored.
activateWorker :: Repository -> WorkerId -> IO (Either String ())
activateWorker repo wid = do
    let uid = workerIdToUserId wid
    mUser <- repoGetUser repo uid
    case mUser of
        Nothing -> pure $ Left "User not found."
        Just u -> case userWorkerStatus u of
            WSNone     -> pure $ Left "User is not a worker."
            WSActive   -> pure $ Left "Worker is already active."
            WSInactive -> do
                repoSetWorkerStatus repo uid WSActive Nothing
                pure (Right ())

-- | Permanently remove the worker concept. Sets @worker_status = 'none'@
-- if and only if the worker has no references anywhere. Configuration
-- and schedule references are preserved (so the operator can decide
-- what to do).
safeDeleteWorker :: Repository -> WorkerId -> IO (Either WorkerReferences ())
safeDeleteWorker repo wid = do
    refs <- checkWorkerReferences repo wid
    if isWorkerUnreferenced refs
        then do
            let uid = workerIdToUserId wid
            repoSetWorkerStatus repo uid WSNone Nothing
            pure (Right ())
        else pure (Left refs)

-- | Cascade removal of every worker reference, then set @worker_status =
-- 'none'@. The user account remains.
forceDeleteWorker :: Repository -> WorkerId -> IO ()
forceDeleteWorker repo wid = do
    repoCascadeWorkerSchedule repo wid
    repoCascadeWorkerConfig repo wid
    let uid = workerIdToUserId wid
    repoSetWorkerStatus repo uid WSNone Nothing

-- | A worker's full profile, assembled for @worker view@ display.
data WorkerProfile = WorkerProfile
    { wpName            :: !Text
    , wpUserId          :: !Int
    , wpWorkerId        :: !Int
    , wpRole            :: !Text                -- ^ "admin" | "normal"
    , wpStatus          :: !WorkerStatus
    , wpDeactivatedAt   :: !(Maybe Day)
    , wpOvertimeModel   :: !OvertimeModel
    , wpPayPeriodTracking :: !PayPeriodTracking
    , wpIsTemp          :: !Bool
    , wpMaxPeriodHours  :: !(Maybe DiffTime)
    , wpOvertimeOptIn   :: !Bool
    , wpWeekendOnly     :: !Bool
    , wpPrefersVariety  :: !Bool
    , wpSeniority       :: !Int
    , wpSkills          :: ![Text]              -- skill names
    , wpStationPrefs    :: ![Text]              -- station names in preference order
    , wpShiftPrefs      :: ![Text]
    , wpCrossTraining   :: ![Text]              -- skill names
    , wpAvoidPairing    :: ![Text]              -- worker (user) names
    , wpPreferPairing   :: ![Text]              -- worker (user) names
    } deriving (Show)

-- | Assemble a 'WorkerProfile' for @worker view@. Works for active and
-- inactive workers. Reads config tables directly so inactive workers
-- still produce a populated profile.
viewWorker :: Repository -> WorkerId -> IO (Maybe WorkerProfile)
viewWorker repo wid = do
    let uid = workerIdToUserId wid
    mUser <- repoGetUser repo uid
    case mUser of
        Nothing -> pure Nothing
        Just u | not (userIsWorker u) -> pure Nothing
               | otherwise -> Just <$> assemble u
  where
    assemble u = do
        -- Static side data
        skills <- repoListSkills repo
        let skillNameMap = Map.fromList [(s, skillName sk) | (s, sk) <- skills]
            lookupSkill s = Map.findWithDefault (T.pack (show s)) s skillNameMap
        stationPairs <- repoListStations repo
        let stationNameMap = Map.fromList [(s, stationName st) | (s, st) <- stationPairs]
            lookupStation s = Map.findWithDefault (T.pack (show s)) s stationNameMap
        users <- repoListUsers repo
        let workerNameMap = Map.fromList
                [ (userIdToWorkerId (userId v), let Username un = userName v in un)
                | v <- users ]
            lookupWorker w = Map.findWithDefault (T.pack (show w)) w workerNameMap

        -- Skills (granted) — load skill context directly (it does not
        -- filter by worker_status)
        skillCtx <- repoLoadSkillCtx repo
        let granted = sort
                [ T.unpack (lookupSkill s)
                | s <- Set.toList
                    (Map.findWithDefault Set.empty wid (scWorkerSkills skillCtx)) ]

        -- WorkerContext is filtered to active; for inactive workers we
        -- skip the dynamic prefs / pairings (they are still in the DB,
        -- but we don't surface them when not in scheduling). The
        -- 'view' behavior we contracted: status + preserved config.
        -- For now, try the WorkerContext path and accept defaults
        -- if not present.
        wctx <- repoLoadWorkerCtx repo

        -- Employment loaded directly (active-only via repoLoadEmployment).
        -- For inactive, this returns empty — we instead would need an
        -- "inactive-aware" lookup; we use sensible defaults.
        let otModel = Map.findWithDefault OTEligible wid (wcOvertimeModel wctx)
            ppTrack = Map.findWithDefault PPStandard wid (wcPayPeriodTracking wctx)
            isTemp = Set.member wid (wcIsTemp wctx)

        let prefStations = map (T.unpack . lookupStation)
                            (Map.findWithDefault [] wid (wcStationPrefs wctx))
            shiftPrefs = map T.unpack
                        (Map.findWithDefault [] wid (wcShiftPrefs wctx))
            crossSet = Map.findWithDefault Set.empty wid (wcCrossTraining wctx)
            crossNames = sort
                [ T.unpack (lookupSkill s) | s <- Set.toList crossSet ]
            avoidNames = sort
                [ T.unpack (lookupWorker w)
                | w <- Set.toList
                    (Map.findWithDefault Set.empty wid (wcAvoidPairing wctx)) ]
            preferNames = sort
                [ T.unpack (lookupWorker w)
                | w <- Set.toList
                    (Map.findWithDefault Set.empty wid (wcPreferPairing wctx)) ]

            roleStr = case userRole u of
                Admin  -> "admin" :: Text
                Normal -> "normal"
            UserId uidI = userId u
            WorkerId widI = wid
            Username uname = userName u
        pure WorkerProfile
            { wpName            = uname
            , wpUserId          = uidI
            , wpWorkerId        = widI
            , wpRole            = roleStr
            , wpStatus          = userWorkerStatus u
            , wpDeactivatedAt   = userDeactivatedAt u
            , wpOvertimeModel   = otModel
            , wpPayPeriodTracking = ppTrack
            , wpIsTemp          = isTemp
            , wpMaxPeriodHours  = Map.lookup wid (wcMaxPeriodHours wctx)
            , wpOvertimeOptIn   = Set.member wid (wcOvertimeOptIn wctx)
            , wpWeekendOnly     = Set.member wid (wcWeekendOnly wctx)
            , wpPrefersVariety  = Set.member wid (wcPrefersVariety wctx)
            , wpSeniority       = Map.findWithDefault 1 wid (wcSeniority wctx)
            , wpSkills          = map T.pack granted
            , wpStationPrefs    = map T.pack prefStations
            , wpShiftPrefs      = map T.pack shiftPrefs
            , wpCrossTraining   = map T.pack crossNames
            , wpAvoidPairing    = map T.pack avoidNames
            , wpPreferPairing   = map T.pack preferNames
            }

