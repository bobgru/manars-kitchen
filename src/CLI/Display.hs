module CLI.Display
    ( displayScheduleTable
    , displayScheduleCompact
    , displaySchedule
    , displayScheduleByWorker
    , displayScheduleByStation
    , displayScheduleByDay
    , displayWorkerHours
    , displayUnfilledTable
    , displayDiagnosis
    , displayUsers
    , displayAbsences
    , displaySkillCtx
    , displaySkillView
    , displayWorkerCtx
    , displayAbsenceTypes
    , displayConfig
    , displayHintDiff
    , displayHintList
    , lookupWorker
    , lookupStation
    , padRight
    ) where

import Data.List (sortBy, intercalate, nub, sort)
import Data.Ord (comparing)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Time
    ( Day, DayOfWeek(..), TimeOfDay(..)
    , formatTime, defaultTimeLocale, dayOfWeek
    )


import Domain.Types
import Domain.Schedule (byWorker, byStation, byDay)
import Domain.Skill (Skill(..), SkillContext(..), effectiveSkills)
import Domain.Worker (WorkerContext(..), OvertimeModel(..), PayPeriodTracking(..))
import Domain.Absence
    ( AbsenceType(..), AbsenceRequest(..), AbsenceStatus(..), AbsenceContext(..)
    )
import Domain.Diagnosis (Diagnosis(..))
import Domain.Scheduler (Unfilled(..), UnfilledKind(..), ScheduleResult(..))
import Domain.Hint (Hint(..), Session(..))
import Auth.Types (User(..), UserId(..), Username(..), Role(..))

-- -----------------------------------------------------------------
-- Tabular schedule view
-- -----------------------------------------------------------------

-- | Display a schedule as a table.
-- Rows = days, sub-rows = stations. Columns = hours.
-- Cells show worker name (from lookup).
displayScheduleTable :: Map.Map WorkerId String   -- ^ worker id -> name
                     -> Map.Map StationId String  -- ^ station id -> name
                     -> (DayOfWeek -> [Int])      -- ^ restaurant hours per day
                     -> Map.Map StationId (Map.Map DayOfWeek [Int]) -- ^ per-station hours
                     -> Schedule -> String
displayScheduleTable workerNames stationNames restaurantHours stationHoursMap (Schedule as)
    | Set.null as = "  (empty schedule)"
    | otherwise   =
        let asList = Set.toList as
            days = sort $ nub [slotDate (assignSlot a) | a <- asList]
            stations = sort $ nub [assignStation a | a <- asList]
            -- Determine hour range across all days
            hours = sort $ nub [getHour (slotStart (assignSlot a)) | a <- asList]
            -- Compute cell contents for each (station, day, hour) to measure widths
            cellWidth sid day h =
                let workers = [assignWorker a
                              | a <- asList
                              , assignStation a == sid
                              , slotDate (assignSlot a) == day
                              , getHour (slotStart (assignSlot a)) == h]
                in case workers of
                    []  -> 1  -- "."
                    [w] -> length (lookupWorker workerNames w)
                    ws  -> length (intercalate "," (map (lookupWorker workerNames) ws))
            maxCellW = maximum (0 : [cellWidth sid day h
                                    | sid <- stations, day <- days, h <- hours])
            maxStationW = maximum (0 : [length (lookupStation stationNames sid)
                                       | sid <- stations])
            -- Column width: at least 6 (for header), fits all content + 1 space
            colW = max 6 (maximum [maxStationW, maxCellW] + 1)
            -- Header
            stLabel = padRight (colW + 2) ""
            header = stLabel ++ concatMap (\h -> padRight colW (formatHour h)) hours
        in unlines $ header : concatMap (\day ->
            let dayLabel = formatDay day
                dayAssignments = [a | a <- asList, slotDate (assignSlot a) == day]
            in dayLabel
               : [ "  " ++ padRight colW (lookupStation stationNames sid)
                   ++ concatMap (\h ->
                       let workers = [assignWorker a
                                     | a <- dayAssignments
                                     , assignStation a == sid
                                     , getHour (slotStart (assignSlot a)) == h]
                           restaurantClosed = h `notElem` restaurantHours (dayOfWeek day)
                           stationClosed = case Map.lookup sid stationHoursMap
                                                >>= Map.lookup (dayOfWeek day) of
                               Nothing -> False
                               Just hs -> h `notElem` hs
                           closed = restaurantClosed || stationClosed
                           cell = if closed
                                  then ""
                                  else case workers of
                                      []    -> "."
                                      [w]   -> lookupWorker workerNames w
                                      ws    -> intercalate "," (map (lookupWorker workerNames) ws)
                       in padRight colW cell
                       ) hours
                 | sid <- stations
                 , any (\a -> assignStation a == sid
                            && slotDate (assignSlot a) == day) asList
                 ]
            ) days

-- -----------------------------------------------------------------
-- Compact tabular schedule view (fits within 100 columns)
-- -----------------------------------------------------------------

-- | Display a schedule as a compact table fitting within 100 columns.
-- Same structure as displayScheduleTable but with abbreviated names and narrower columns.
displayScheduleCompact :: Map.Map WorkerId String   -- ^ worker id -> name
                       -> Map.Map StationId String  -- ^ station id -> name
                       -> (DayOfWeek -> [Int])      -- ^ restaurant hours per day
                       -> Map.Map StationId (Map.Map DayOfWeek [Int]) -- ^ per-station hours
                       -> Schedule -> String
displayScheduleCompact workerNames stationNames restaurantHours stationHoursMap (Schedule as)
    | Set.null as = "  (empty schedule)"
    | otherwise   =
        let asList = Set.toList as
            days = sort $ nub [slotDate (assignSlot a) | a <- asList]
            stations = sort $ nub [assignStation a | a <- asList]
            hours = sort $ nub [getHour (slotStart (assignSlot a)) | a <- asList]
            -- Build abbreviation maps
            allWorkerIds = nub [assignWorker a | a <- asList]
            workerAbbrevs = uniqueAbbrevs
                [ (wid, Map.findWithDefault ("W" ++ show w) wid workerNames)
                | wid@(WorkerId w) <- allWorkerIds ]
            stationAbbrevs = uniqueAbbrevs
                [ (sid, Map.findWithDefault ("S" ++ show s) sid stationNames)
                | sid@(StationId s) <- stations ]
            lookupAbbrev m key = Map.findWithDefault "?" key m
            -- Column widths: target 100 chars total
            -- Layout: "  " + station label + hour columns
            stW = max 4 (maximum (0 : [length (lookupAbbrev stationAbbrevs sid) | sid <- stations])) + 1
            maxCellW = maximum (1 : [length (cellContent workerAbbrevs asList sid day h)
                                    | sid <- stations, day <- days, h <- hours])
            colW = max 4 (min 6 (maxCellW + 1))
            -- Header: abbreviated hours (just the number)
            stLabel = padRight (stW + 2) ""
            header = stLabel ++ concatMap (\h -> padRight colW (show h)) hours
        in unlines $ header : concatMap (\day ->
            let dayLabel = formatDay day
            in dayLabel
               : [ "  " ++ padRight stW (lookupAbbrev stationAbbrevs sid)
                   ++ concatMap (\h ->
                       let restaurantClosed = h `notElem` restaurantHours (dayOfWeek day)
                           stationClosed = case Map.lookup sid stationHoursMap
                                                >>= Map.lookup (dayOfWeek day) of
                               Nothing -> False
                               Just hs -> h `notElem` hs
                           closed = restaurantClosed || stationClosed
                           cell = if closed
                                  then ""
                                  else cellContent workerAbbrevs asList sid day h
                       in padRight colW cell
                       ) hours
                 | sid <- stations
                 , any (\a -> assignStation a == sid
                            && slotDate (assignSlot a) == day) asList]
            ) days
  where
    cellContent abbrevs asList sid day h =
        let workers = [assignWorker a
                      | a <- asList
                      , assignStation a == sid
                      , slotDate (assignSlot a) == day
                      , getHour (slotStart (assignSlot a)) == h]
        in case workers of
            []    -> "."
            [w]   -> Map.findWithDefault "?" w abbrevs
            ws    -> intercalate "," (map (\w -> Map.findWithDefault "?" w abbrevs) ws)

-- | Generate unique abbreviations for a list of (key, name) pairs.
-- Starts with 3-char prefixes and extends where needed to disambiguate.
uniqueAbbrevs :: (Ord k) => [(k, String)] -> Map.Map k String
uniqueAbbrevs pairs =
    let minLen = 3
        initial = [(k, take minLen name, name) | (k, name) <- pairs]
    in Map.fromList (resolve initial)
  where
    resolve :: (Ord k) => [(k, String, String)] -> [(k, String)]
    resolve items =
        let grouped = Map.fromListWith (++) [(abbr, [(k, full)]) | (k, abbr, full) <- items]
        in concatMap (\(abbr, ks) ->
            if length ks <= 1
            then [(k, abbr) | (k, _) <- ks]
            else
                let extended = [(k, if length full > length abbr
                                    then take (length abbr + 1) full
                                    else full, full)
                               | (k, full) <- ks]
                    extAbbrs = [a | (_, a, _) <- extended]
                in if nub extAbbrs == extAbbrs
                   then [(k, a) | (k, a, _) <- extended]
                   else
                        let maxLen = maximum [length f | (_, f) <- ks]
                        in if length abbr >= maxLen
                           then [(k, full) | (k, full) <- ks]
                           else resolve extended
            ) (Map.toList grouped)

getHour :: TimeOfDay -> Int
getHour (TimeOfDay h _ _) = h

formatHour :: Int -> String
formatHour h
    | h < 10    = " " ++ show h ++ ":00"
    | otherwise = show h ++ ":00"

formatDay :: Day -> String
formatDay d = padRight 3 (showDow (dayOfWeek d))
    ++ " " ++ formatTime defaultTimeLocale "%m-%d" d

showDow :: DayOfWeek -> String
showDow Monday    = "Mon"
showDow Tuesday   = "Tue"
showDow Wednesday = "Wed"
showDow Thursday  = "Thu"
showDow Friday    = "Fri"
showDow Saturday  = "Sat"
showDow Sunday    = "Sun"

padRight :: Int -> String -> String
padRight n s = s ++ replicate (max 0 (n - length s)) ' '

lookupWorker :: Map.Map WorkerId String -> WorkerId -> String
lookupWorker m wid@(WorkerId w) = Map.findWithDefault ("W" ++ show w) wid m

lookupStation :: Map.Map StationId String -> StationId -> String
lookupStation m sid@(StationId s) = Map.findWithDefault ("S" ++ show s) sid m

-- -----------------------------------------------------------------
-- Diagnosis display
-- -----------------------------------------------------------------

displayDiagnosis :: Map.Map WorkerId String
                 -> Map.Map StationId String
                 -> Map.Map SkillId String
                 -> ScheduleResult -> [Diagnosis] -> String
displayDiagnosis wNames sNames skNames result diags =
    let allUnfilled = srUnfilled result
    in displayUnfilledTable sNames allUnfilled
       ++ if null diags
          then "  No suggestions available.\n"
          else unlines
              $ "Suggestions (ranked by impact):"
              : zipWith (\i d -> "  " ++ show i ++ ". " ++ showDiag wNames sNames skNames d)
                        [1::Int ..] diags

showDiag :: Map.Map WorkerId String
         -> Map.Map StationId String
         -> Map.Map SkillId String
         -> Diagnosis -> String
showDiag _ _ skNames (SuggestHire skills n) =
    "Hire a worker with " ++ showSkillNames skNames skills
    ++ " (resolves " ++ show n ++ " position" ++ plural n ++ ")"
showDiag wNames _ skNames (SuggestTraining wid skill n) =
    "Train " ++ lookupWorker wNames wid
    ++ " in " ++ lookupSkill skNames skill
    ++ " (resolves " ++ show n ++ " position" ++ plural n ++ ")"
showDiag wNames _ _ (SuggestOvertime wids n) =
    "Allow overtime for " ++ intercalate ", " (map (lookupWorker wNames) wids)
    ++ " (resolves " ++ show n ++ " position" ++ plural n ++ ")"
showDiag _ sNames _ (SuggestClose st slots n) =
    "Close " ++ lookupStation sNames st
    ++ " at " ++ intercalate ", " [showSlot s | s <- slots]
    ++ " (frees " ++ show n ++ " worker" ++ plural n ++ ")"
showDiag _ _ skNames (SuggestAddWorker skills) =
    "Bring in a temp worker with " ++ showSkillNames skNames skills

showSkillNames :: Map.Map SkillId String -> Set.Set SkillId -> String
showSkillNames skNames skills =
    intercalate ", " [lookupSkill skNames sk | sk <- Set.toList skills]

lookupSkill :: Map.Map SkillId String -> SkillId -> String
lookupSkill m sid@(SkillId s) = Map.findWithDefault ("Skill " ++ show s) sid m

plural :: Int -> String
plural 1 = ""
plural _ = "s"

-- -----------------------------------------------------------------
-- Worker hours table
-- -----------------------------------------------------------------

-- | Display a table of scheduled hours per worker, with overtime.
displayWorkerHours :: Map.Map WorkerId String      -- ^ worker names
                   -> Map.Map WorkerId DiffTime     -- ^ max weekly hours
                   -> Schedule -> String
displayWorkerHours wNames maxHours (Schedule as)
    | Set.null as = "  (empty schedule)"
    | otherwise =
        let asList = Set.toList as
            workers = sort $ nub [assignWorker a | a <- asList]
            -- Compute total scheduled hours per worker
            workerHrs w = sum [slotDuration (assignSlot a)
                              | a <- asList, assignWorker a == w]
            -- Column widths
            nameW = maximum (6 : [length (lookupWorker wNames w) | w <- workers]) + 1
            colW = 12
            header = padRight nameW "Worker"
                  ++ padRight colW "Scheduled"
                  ++ padRight colW "Max"
                  ++ "Overtime"
            sep = replicate (nameW + colW * 2 + colW) '-'
            row w =
                let sched = workerHrs w
                    maxH  = Map.lookup w maxHours
                    ot    = case maxH of
                        Nothing -> 0
                        Just 0  -> sched  -- 0 max means all hours are overtime
                        Just m  -> max 0 (sched - m)
                in padRight nameW (lookupWorker wNames w)
                   ++ padRight colW (fmtHours sched)
                   ++ padRight colW (maybe "-" fmtHours maxH)
                   ++ if ot > 0 then fmtHours ot else ""
        in unlines $ header : sep : map row workers

fmtHours :: DiffTime -> String
fmtHours dt =
    let totalMins = round (toRational dt / 60) :: Int
        h = totalMins `div` 60
        m = totalMins `mod` 60
    in if m == 0 then show h ++ "h" else show h ++ "h " ++ show m ++ "m"

-- -----------------------------------------------------------------
-- Unfilled/understaffed table
-- -----------------------------------------------------------------

-- | Display unfilled and understaffed positions as tables.
displayUnfilledTable :: Map.Map StationId String -> [Unfilled] -> String
displayUnfilledTable sNames allUnfilled
    | null allUnfilled = "  No unfilled positions — schedule is fully staffed."
    | otherwise =
        let truly = [u | u@(Unfilled _ _ TrulyUnfilled) <- allUnfilled]
            under = [u | u@(Unfilled _ _ Understaffed)  <- allUnfilled]
            -- Group by station, count positions per station
            groupByStation us =
                let pairs = [(unfilledStation u, u) | u <- us]
                    stns = sort $ nub (map fst pairs)
                in [(s, length (filter ((== s) . fst) pairs)) | s <- stns]
            nameW = maximum (8 :
                [length (lookupStation sNames (unfilledStation u)) | u <- allUnfilled]) + 1
            colW = 10
            tableHeader = padRight nameW "Station" ++ "Count"
            tableSep = replicate (nameW + colW) '-'
            tableRow (s, n) = padRight nameW (lookupStation sNames s) ++ show n
            trulySection = if null truly then []
                else [ "Unfilled (no coverage): " ++ show (length truly) ++ " position(s)"
                     , tableHeader, tableSep ]
                  ++ map tableRow (groupByStation truly)
                  ++ [""]
            underSection = if null under then []
                else [ "Understaffed (has coverage, overlap shift not filled): "
                       ++ show (length under) ++ " position(s)"
                     , tableHeader, tableSep ]
                  ++ map tableRow (groupByStation under)
                  ++ [""]
        in unlines (trulySection ++ underSection)

-- -----------------------------------------------------------------
-- Legacy views (kept for view-by-worker, view-by-station)
-- -----------------------------------------------------------------

displaySchedule :: Schedule -> String
displaySchedule (Schedule as)
    | Set.null as = "  (empty schedule)"
    | otherwise   = unlines
        [ showAssignment a | a <- sortBy (comparing assignSlot) (Set.toList as) ]

showAssignment :: Assignment -> String
showAssignment a =
    "  " ++ showWorker (assignWorker a)
    ++ " @ " ++ showStation (assignStation a)
    ++ " on " ++ showSlot (assignSlot a)

showWorker :: WorkerId -> String
showWorker (WorkerId w) = "Worker " ++ show w

showStation :: StationId -> String
showStation (StationId s) = "Station " ++ show s

showSlot :: Slot -> String
showSlot s = formatTime defaultTimeLocale "%Y-%m-%d" (slotDate s)
    ++ " " ++ formatTime defaultTimeLocale "%H:%M" (slotStart s)

displayScheduleByWorker :: Schedule -> String
displayScheduleByWorker sched@(Schedule as) =
    let wids = nub [assignWorker a | a <- Set.toList as]
    in unlines $ concatMap (\wid ->
        let ws = byWorker wid sched
        in (showWorker wid ++ ":")
           : [ "  " ++ showStation (assignStation a) ++ " on " ++ showSlot (assignSlot a)
             | a <- sortBy (comparing assignSlot) (Set.toList ws) ]
        ) (sortBy compare wids)

displayScheduleByStation :: Schedule -> String
displayScheduleByStation sched@(Schedule as) =
    let sids = nub [assignStation a | a <- Set.toList as]
    in unlines $ concatMap (\sid ->
        let ws = byStation sid sched
        in (showStation sid ++ ":")
           : [ "  " ++ showWorker (assignWorker a) ++ " on " ++ showSlot (assignSlot a)
             | a <- sortBy (comparing assignSlot) (Set.toList ws) ]
        ) (sortBy compare sids)

displayScheduleByDay :: Schedule -> Day -> String
displayScheduleByDay sched day =
    let ds = byDay day sched
    in if Set.null ds
       then "  No assignments on " ++ formatTime defaultTimeLocale "%Y-%m-%d" day
       else unlines [ showAssignment a
                    | a <- sortBy (comparing assignSlot) (Set.toList ds) ]

-- -----------------------------------------------------------------
-- Other entities
-- -----------------------------------------------------------------

displayUsers :: [User] -> String
displayUsers [] = "  (no users)"
displayUsers users = unlines
    [ "  " ++ show uid ++ ". " ++ uname ++ " [" ++ showRole role ++ "] -> " ++ showWorker wid
    | User { userId = UserId uid, userName = Username uname
           , userRole = role, userWorkerId = wid } <- users ]
  where
    showRole Admin  = "admin"
    showRole Normal = "normal"

displayAbsences :: [AbsenceRequest] -> String
displayAbsences [] = "  (no absences)"
displayAbsences reqs = unlines
    [ "  #" ++ show aid ++ " " ++ showWorker wid
      ++ " type " ++ show tid
      ++ " " ++ formatTime defaultTimeLocale "%Y-%m-%d" (arStartDay r)
      ++ " to " ++ formatTime defaultTimeLocale "%Y-%m-%d" (arEndDay r)
      ++ " [" ++ showStatus (arStatus r) ++ "]"
    | r <- reqs
    , let AbsenceId aid = arId r
          wid = arWorker r
          AbsenceTypeId tid = arType r
    ]
  where
    showStatus Pending  = "pending"
    showStatus Approved = "approved"
    showStatus Rejected = "rejected"

displaySkillCtx :: SkillContext -> String
displaySkillCtx ctx = unlines $ concat
    [ ["Stations:"]
    , [ "  " ++ showStation sid
        ++ " (requires: " ++ showSkillSet (Map.findWithDefault Set.empty sid (scStationRequires ctx))
        ++ showStationHoursNote sid ctx
        ++ ")"
      | sid <- Set.toList (scAllStations ctx) ]
    , ["Worker skills:"]
    , [ "  " ++ showWorker wid ++ ": " ++ showSkillSet skills
      | (wid, skills) <- Map.toList (scWorkerSkills ctx) ]
    , if Map.null (scSkillImplies ctx) then [] else
      ["Skill implications:"]
      ++ [ "  " ++ showSkill sid ++ " implies " ++ showSkillSet imps
         | (sid, imps) <- Map.toList (scSkillImplies ctx) ]
    ]

showStationHoursNote :: StationId -> SkillContext -> String
showStationHoursNote sid ctx =
    case Map.lookup sid (scStationHours ctx) of
        Nothing -> ""
        Just dayMap ->
            let closedDays = [d | (d, []) <- Map.toList dayMap]
                openDays = [(d, hs) | (d, hs@(_:_)) <- Map.toList dayMap]
            in case (openDays, closedDays) of
                ([], []) -> ""
                (_, _) ->
                    let hoursNote = case openDays of
                            [] -> ""
                            ((_, hs):_) -> ", hours: " ++ show (minimum hs) ++ ":00-"
                                           ++ show (maximum hs + 1) ++ ":00"
                        closedNote = if null closedDays then ""
                            else ", closed: " ++ intercalate ", " (map showDow closedDays)
                        multiNote = case Map.lookup sid (scMultiStationHours ctx) of
                            Nothing -> ""
                            Just mDayMap ->
                                let mHours = concatMap snd (Map.toList mDayMap)
                                in if null mHours then ""
                                   else ", multi-station: " ++ show (minimum mHours) ++ ":00-"
                                        ++ show (maximum mHours + 1) ++ ":00"
                    in hoursNote ++ closedNote ++ multiNote

showSkill :: SkillId -> String
showSkill (SkillId s) = "Skill " ++ show s

showWorkerSet :: Set.Set WorkerId -> String
showWorkerSet s
    | Set.null s = "(none)"
    | otherwise  = intercalate ", " [showWorker w | w <- Set.toList s]

showSkillSet :: Set.Set SkillId -> String
showSkillSet s
    | Set.null s = "(none)"
    | otherwise  = intercalate ", " [showSkill sk | sk <- Set.toList s]

displaySkillView :: SkillId -> Skill -> SkillContext -> WorkerContext
                 -> Map.Map WorkerId String -> Map.Map StationId String
                 -> Map.Map SkillId String -> String
displaySkillView sid sk sctx wctx workerNames stationNames skillNames =
    let namedSkill skid = Map.findWithDefault (showSkill skid) skid skillNames
        namedWorker wid = Map.findWithDefault (showWorker wid) wid workerNames
        namedStation stid = Map.findWithDefault (showStation stid) stid stationNames
        workers = [ (wid, namedWorker wid)
                  | (wid, skills) <- Map.toList (scWorkerSkills sctx)
                  , Set.member sid skills ]
        stations = [ (stid, namedStation stid)
                   | (stid, skills) <- Map.toList (scStationRequires sctx)
                   , Set.member sid skills ]
        impliedBy = [ (skid, namedSkill skid)
                    | (skid, imps) <- Map.toList (scSkillImplies sctx)
                    , Set.member sid imps ]
        implies = case Map.lookup sid (scSkillImplies sctx) of
            Nothing -> []
            Just imps -> [(skid, namedSkill skid) | skid <- Set.toList imps]
        eff = Set.delete sid $ effectiveSkills sctx (Set.singleton sid)
        crossTraining = [ (wid, namedWorker wid)
                        | (wid, skills) <- Map.toList (wcCrossTraining wctx)
                        , Set.member sid skills ]
    in unlines $ concat
        [ [namedSkill sid ++ " (" ++ show sid ++ ")"]
        , if null (skillDescription sk) then []
          else ["  Description: " ++ skillDescription sk]
        , ["  Workers: " ++ if null workers then "(none)"
           else intercalate ", " [name | (_, name) <- workers]]
        , ["  Stations: " ++ if null stations then "(none)"
           else intercalate ", " [name | (_, name) <- stations]]
        , if null implies then []
          else ["  Implies: " ++ intercalate ", " [name | (_, name) <- implies]]
        , if null impliedBy then []
          else ["  Implied by: " ++ intercalate ", " [name | (_, name) <- impliedBy]]
        , if Set.null eff then []
          else ["  Effective skills: " ++ intercalate ", " [namedSkill s' | s' <- Set.toList eff]]
        , if null crossTraining then []
          else ["  Cross-training: " ++ intercalate ", " [name | (_, name) <- crossTraining]]
        ]

displayWorkerCtx :: WorkerContext -> String
displayWorkerCtx ctx = unlines $ concat
    [ ["Max per-period hours:"]
    , [ "  " ++ showWorker wid ++ ": " ++ show (round (toRational dt / 3600) :: Int) ++ "h"
      | (wid, dt) <- Map.toList (wcMaxPeriodHours ctx) ]
    , ["Overtime opt-in:"]
    , [ "  " ++ showWorker wid | wid <- Set.toList (wcOvertimeOptIn ctx) ]
    , if Map.null (wcStationPrefs ctx) then [] else
      ["Station preferences:"]
      ++ [ "  " ++ showWorker wid ++ ": " ++ intercalate ", " (map showStation prefs)
         | (wid, prefs) <- Map.toList (wcStationPrefs ctx) ]
    , if Set.null (wcPrefersVariety ctx) then [] else
      ["Prefers variety:"]
      ++ [ "  " ++ showWorker wid | wid <- Set.toList (wcPrefersVariety ctx) ]
    , if Map.null (wcShiftPrefs ctx) then [] else
      ["Shift preferences:"]
      ++ [ "  " ++ showWorker wid ++ ": " ++ intercalate ", " prefs
         | (wid, prefs) <- Map.toList (wcShiftPrefs ctx) ]
    , if Set.null (wcWeekendOnly ctx) then [] else
      ["Weekend-only:"]
      ++ [ "  " ++ showWorker wid | wid <- Set.toList (wcWeekendOnly ctx) ]
    , if Map.null (wcSeniority ctx) then [] else
      ["Seniority:"]
      ++ [ "  " ++ showWorker wid ++ ": level " ++ show lvl
         | (wid, lvl) <- Map.toList (wcSeniority ctx) ]
    , if Map.null (wcCrossTraining ctx) then [] else
      ["Cross-training goals:"]
      ++ [ "  " ++ showWorker wid ++ ": " ++ showSkillSet skills
         | (wid, skills) <- Map.toList (wcCrossTraining ctx) ]
    , if Map.null (wcAvoidPairing ctx) then [] else
      ["Avoid pairing:"]
      ++ [ "  " ++ showWorker wid ++ " avoids " ++ showWorkerSet others
         | (wid, others) <- Map.toList (wcAvoidPairing ctx) ]
    , if Map.null (wcPreferPairing ctx) then [] else
      ["Prefer pairing:"]
      ++ [ "  " ++ showWorker wid ++ " prefers " ++ showWorkerSet others
         | (wid, others) <- Map.toList (wcPreferPairing ctx) ]
    , if Map.null (wcOvertimeModel ctx) then [] else
      ["Overtime model:"]
      ++ [ "  " ++ showWorker wid ++ ": " ++ showOvertimeModel om
         | (wid, om) <- Map.toList (wcOvertimeModel ctx) ]
    , if Map.null (wcPayPeriodTracking ctx) then [] else
      ["Pay period tracking:"]
      ++ [ "  " ++ showWorker wid ++ ": " ++ showPayPeriodTracking pp
         | (wid, pp) <- Map.toList (wcPayPeriodTracking ctx) ]
    , if Set.null (wcIsTemp ctx) then [] else
      ["Temp workers:"]
      ++ [ "  " ++ showWorker wid | wid <- Set.toList (wcIsTemp ctx) ]
    ]

showOvertimeModel :: OvertimeModel -> String
showOvertimeModel OTEligible   = "eligible"
showOvertimeModel OTManualOnly = "manual-only"
showOvertimeModel OTExempt     = "exempt"

showPayPeriodTracking :: PayPeriodTracking -> String
showPayPeriodTracking PPStandard = "standard"
showPayPeriodTracking PPExempt   = "exempt"

displayAbsenceTypes :: AbsenceContext -> String
displayAbsenceTypes ctx
    | Map.null (acTypes ctx) = "  (no absence types)"
    | otherwise = unlines
        [ "  " ++ show tid ++ ". " ++ atName at
          ++ if atYearlyLimit at then " (yearly limit)" else " (no limit)"
        | (AbsenceTypeId tid, at) <- Map.toList (acTypes ctx) ]

-- -----------------------------------------------------------------
-- Hint diff and list display
-- -----------------------------------------------------------------

-- | Display the difference between two schedule results after a hint operation.
displayHintDiff :: Map.Map WorkerId String
                -> Map.Map StationId String
                -> ScheduleResult -> ScheduleResult -> String
displayHintDiff wNames sNames oldResult newResult =
    let oldAssigns = unSchedule (srSchedule oldResult)
        newAssigns = unSchedule (srSchedule newResult)
        added   = Set.difference newAssigns oldAssigns
        removed = Set.difference oldAssigns newAssigns
        oldUf = srUnfilled oldResult
        newUf = srUnfilled newResult
        addedUf   = filter (`notElem` oldUf) newUf
        removedUf = filter (`notElem` newUf) oldUf
    in if Set.null added && Set.null removed && null addedUf && null removedUf
       then "No schedule changes.\n"
       else unlines $ concat
           [ if Set.null removed then [] else
               [ "  - " ++ lookupWorker wNames (assignWorker a)
                 ++ " @ " ++ lookupStation sNames (assignStation a)
                 ++ " on " ++ showSlot (assignSlot a)
               | a <- Set.toList removed ]
           , if Set.null added then [] else
               [ "  + " ++ lookupWorker wNames (assignWorker a)
                 ++ " @ " ++ lookupStation sNames (assignStation a)
                 ++ " on " ++ showSlot (assignSlot a)
               | a <- Set.toList added ]
           , if null removedUf then [] else
               [ "  Resolved: " ++ lookupStation sNames (unfilledStation u)
                 ++ " at " ++ showSlot (unfilledSlot u)
               | u <- removedUf ]
           , if null addedUf then [] else
               [ "  Unfilled: " ++ lookupStation sNames (unfilledStation u)
                 ++ " at " ++ showSlot (unfilledSlot u)
               | u <- addedUf ]
           , [ show (Set.size newAssigns) ++ " assignments, "
               ++ show (length newUf) ++ " unfilled"
               ++ " (was " ++ show (Set.size oldAssigns) ++ " / "
               ++ show (length oldUf) ++ ")" ]
           ]

-- | Display active hints in a session as a numbered list.
displayHintList :: Map.Map WorkerId String
                -> Map.Map StationId String
                -> Map.Map SkillId String
                -> Session -> String
displayHintList wNames sNames skNames sess =
    let hints = sessHints sess
    in if null hints
       then "No active hints.\n"
       else unlines $
           ("Active hints:")
           : zipWith (\i h -> "  " ++ show i ++ ". " ++ showHint wNames sNames skNames h)
                     [1::Int ..] hints

showHint :: Map.Map WorkerId String
         -> Map.Map StationId String
         -> Map.Map SkillId String
         -> Hint -> String
showHint _wNames sNames _skNames (CloseStation sid slot) =
    "Close station: " ++ lookupStation sNames sid ++ " on " ++ showSlot slot
showHint wNames sNames _skNames (PinAssignment wid sid slot) =
    "Pin: " ++ lookupWorker wNames wid ++ " @ " ++ lookupStation sNames sid
    ++ " on " ++ showSlot slot
showHint wNames _sNames _skNames (AddWorker wid _skills mHours) =
    "Add worker: " ++ lookupWorker wNames wid
    ++ maybe "" (\h -> " (" ++ show (round (toRational h / 3600) :: Int) ++ "h)") mHours
showHint wNames _sNames _skNames (WaiveOvertime wid) =
    "Waive overtime: " ++ lookupWorker wNames wid
showHint wNames _sNames skNames (GrantSkill wid skid) =
    "Grant skill: " ++ lookupWorker wNames wid ++ " -> " ++ lookupSkill skNames skid
showHint wNames sNames _skNames (OverridePreference wid sids) =
    "Override prefs: " ++ lookupWorker wNames wid
    ++ " -> " ++ intercalate ", " (map (lookupStation sNames) sids)

-- -----------------------------------------------------------------
-- Config display
-- -----------------------------------------------------------------

displayConfig :: [(String, Double)] -> String
displayConfig [] = "  (no config parameters)\n"
displayConfig params =
    let nameW = maximum (4 : map (length . fst) params) + 2
    in unlines $ "Scheduler config:"
       : [ "  " ++ padRight nameW k ++ showVal v | (k, v) <- sort params ]
  where
    showVal v
        | v == fromIntegral (round v :: Int) = show (round v :: Int)
        | otherwise = show v
