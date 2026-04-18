module Service.Worker
    ( -- * Skill entity operations
      addSkill
    , removeSkill
    , listSkills
    , renameSkill
    , listSkillImplications
    , removeSkillImplication
      -- * Station entity operations
    , addStation
    , removeStation
    , listStations
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
    ) where

import Data.List (nub, sort)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set

import Data.Time (DayOfWeek(..))
import Domain.Types (WorkerId, StationId, SkillId, DiffTime)
import Domain.Skill (Skill, SkillContext(..))
import Domain.Worker (WorkerContext(..), OvertimeModel(..), PayPeriodTracking(..))
import Domain.Pin (PinnedAssignment(..))
import Repo.Types (Repository(..))

-- -----------------------------------------------------------------
-- Skill entity CRUD
-- -----------------------------------------------------------------

-- | Register a new skill with a name and description.
-- Returns Left with error message if the skill ID already exists.
addSkill :: Repository -> SkillId -> String -> String -> IO (Either String ())
addSkill repo sid name desc = repoCreateSkill repo sid name desc

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
renameSkill :: Repository -> SkillId -> String -> IO ()
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
-- Station entity CRUD
-- -----------------------------------------------------------------

-- | Add a station to the system.
addStation :: Repository -> StationId -> String -> IO ()
addStation repo sid name = do
    repoCreateStation repo sid name
    ctx <- repoLoadSkillCtx repo
    let ctx' = ctx
            { scAllStations = Set.insert sid (scAllStations ctx) }
    repoSaveSkillCtx repo ctx'

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
listStations :: Repository -> IO [(StationId, String)]
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
setShiftPreferences :: Repository -> WorkerId -> [String] -> IO ()
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
