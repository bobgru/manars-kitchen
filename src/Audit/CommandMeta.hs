{-# LANGUAGE OverloadedStrings #-}
module Audit.CommandMeta
    ( CommandMeta(..)
    , classify
    , render
    , defaultMeta
    -- Entity type constants
    , etWorker, etStation, etSkill, etShift, etAbsence
    , etUser, etConfig, etSchedule, etDraft, etCalendar
    , etPin, etWhatIf, etCheckpoint, etImportExport
    ) where

import Data.Char    (isDigit)
import Data.List    (intercalate, isPrefixOf)
import Data.Maybe   (catMaybes)
import Data.Text    (Text, pack, unpack)
import CLI.Commands (shellWords)

-- | Structured metadata for a logged command.
data CommandMeta = CommandMeta
    { cmEntityType  :: !(Maybe Text)    -- ^ e.g. "worker", "station"
    , cmOperation   :: !(Maybe Text)    -- ^ e.g. "grant-skill", "add"
    , cmEntityId    :: !(Maybe Int)     -- ^ primary entity ID
    , cmTargetId    :: !(Maybe Int)     -- ^ secondary entity ID
    , cmDateFrom    :: !(Maybe Text)    -- ^ YYYY-MM-DD
    , cmDateTo      :: !(Maybe Text)    -- ^ YYYY-MM-DD
    , cmIsMutation  :: !Bool
    , cmParams      :: !(Maybe Text)    -- ^ JSON blob for variadic args
    } deriving (Show, Eq)

-- | Default metadata: unknown command, not a mutation.
defaultMeta :: CommandMeta
defaultMeta = CommandMeta
    { cmEntityType = Nothing
    , cmOperation  = Nothing
    , cmEntityId   = Nothing
    , cmTargetId   = Nothing
    , cmDateFrom   = Nothing
    , cmDateTo     = Nothing
    , cmIsMutation = False
    , cmParams     = Nothing
    }

-- Entity type constants
etWorker, etStation, etSkill, etShift, etAbsence :: Text
etUser, etConfig, etSchedule, etDraft, etCalendar :: Text
etPin, etWhatIf, etCheckpoint, etImportExport :: Text
etWorker       = "worker"
etStation      = "station"
etSkill        = "skill"
etShift        = "shift"
etAbsence      = "absence"
etUser         = "user"
etConfig       = "config"
etSchedule     = "schedule"
etDraft        = "draft"
etCalendar     = "calendar"
etPin          = "pin"
etWhatIf       = "what-if"
etCheckpoint   = "checkpoint"
etImportExport = "import-export"

-- | Classify a raw command string into structured metadata.
classify :: String -> CommandMeta
classify input = case shellWords input of
    -- Schedule commands
    ("schedule" : op : rest) -> classifySchedule op rest
    -- Assignment commands
    ("assign" : rest) -> classifyAssign rest
    ("unassign" : rest) -> classifyUnassign rest
    -- Station commands
    ("station" : op : rest) -> classifyStation op rest
    -- Skill commands
    ("skill" : op : rest) -> classifySkill op rest
    -- Worker commands
    ("worker" : op : rest) -> classifyWorker op rest
    -- Shift commands
    ("shift" : op : rest) -> classifyShift op rest
    -- Absence commands
    ("absence-type" : op : rest) -> classifyAbsenceType op rest
    ("absence" : op : rest) -> classifyAbsence op rest
    ("vacation" : op : rest) -> classifyVacation op rest
    -- User commands
    ("user" : op : rest) -> classifyUser op rest
    -- Config commands
    ("config" : op : rest) -> classifyConfig op rest
    -- Pin commands
    ("pin" : "list" : _) -> nonMutating etPin "list"
    ("pin" : rest) -> classifyPin rest
    ("unpin" : rest) -> classifyUnpin rest
    -- Import/Export
    ("export" : rest) -> classifyExport rest
    ("import" : rest) -> classifyImport rest
    -- Audit (non-mutating)
    ["audit"]       -> nonMutating etSchedule "audit"
    ["replay"]      -> nonMutating etSchedule "replay"
    ("replay" : _)  -> nonMutating etSchedule "replay"
    ["demo"]        -> nonMutating etSchedule "demo"
    -- Checkpoint
    ("checkpoint" : op : rest) -> classifyCheckpoint op rest
    -- Calendar
    ("calendar" : op : rest) -> classifyCalendar op rest
    -- Draft
    ("draft" : op : rest) -> classifyDraft op rest
    -- What-if
    ("what-if" : op : rest) -> classifyWhatIf op rest
    -- Context (non-mutating)
    ("use" : _)     -> nonMutating etSchedule "use"
    ("context" : _) -> nonMutating etSchedule "context"
    -- Self
    ["password", "change"] -> nonMutating etUser "password-change"
    -- Help, quit
    ["help"]        -> nonMutating etSchedule "help"
    ("help" : _)    -> nonMutating etSchedule "help"
    ["quit"]        -> nonMutating etSchedule "quit"
    ["exit"]        -> nonMutating etSchedule "quit"
    _               -> defaultMeta

-- Schedule
classifySchedule :: String -> [String] -> CommandMeta
classifySchedule op rest = case op of
    "create" -> mutating etSchedule "create"
    "delete" -> mutating etSchedule "delete"
    "clear"  -> mutating etSchedule "clear"
    "list"   -> nonMutating etSchedule "list"
    "view"   -> nonMutating etSchedule "view"
    "view-compact"    -> nonMutating etSchedule "view-compact"
    "view-by-worker"  -> nonMutating etSchedule "view-by-worker"
    "view-by-station" -> nonMutating etSchedule "view-by-station"
    "hours"    -> nonMutating etSchedule "hours"
    "diagnose" -> nonMutating etSchedule "diagnose"
    _ -> nonMutating etSchedule (pack op)
  where _unused = rest  -- suppress warning

-- Assign / Unassign
classifyAssign :: [String] -> CommandMeta
classifyAssign (_sched : wid : sid : _date : _hr : _) =
    (mutating etSchedule "assign")
        { cmEntityId = readMaybe wid
        , cmTargetId = readMaybe sid
        }
classifyAssign _ = mutating etSchedule "assign"

classifyUnassign :: [String] -> CommandMeta
classifyUnassign (_sched : wid : sid : _date : _hr : _) =
    (mutating etSchedule "unassign")
        { cmEntityId = readMaybe wid
        , cmTargetId = readMaybe sid
        }
classifyUnassign _ = mutating etSchedule "unassign"

-- Station
classifyStation :: String -> [String] -> CommandMeta
classifyStation op rest = case op of
    "create" -> case rest of
        (sid : _) -> (mutating etStation "create") { cmEntityId = readMaybe sid }
        _         -> mutating etStation "create"
    "delete" -> case rest of
        (sid : _) -> (mutating etStation "delete") { cmEntityId = readMaybe sid }
        _         -> mutating etStation "delete"
    "force-delete" -> case rest of
        (sid : _) -> (mutating etStation "force-delete") { cmEntityId = readMaybe sid }
        _         -> mutating etStation "force-delete"
    "rename" -> case rest of
        (sid : _) -> (mutating etStation "rename") { cmEntityId = readMaybe sid }
        _         -> mutating etStation "rename"
    "view" -> case rest of
        (sid : _) -> (nonMutating etStation "view") { cmEntityId = readMaybe sid }
        _         -> nonMutating etStation "view"
    "set-hours" -> case rest of
        (sid : _) -> (mutating etStation "set-hours") { cmEntityId = readMaybe sid }
        _         -> mutating etStation "set-hours"
    "close-day" -> case rest of
        (sid : _) -> (mutating etStation "close-day") { cmEntityId = readMaybe sid }
        _         -> mutating etStation "close-day"
    "set-multi-hours" -> case rest of
        (sid : _) -> (mutating etStation "set-multi-hours") { cmEntityId = readMaybe sid }
        _         -> mutating etStation "set-multi-hours"
    "require-skill" -> case rest of
        (sid : skid : _) -> (mutating etStation "require-skill")
            { cmEntityId = readMaybe sid, cmTargetId = readMaybe skid }
        (sid : _) -> (mutating etStation "require-skill") { cmEntityId = readMaybe sid }
        _         -> mutating etStation "require-skill"
    "remove-required-skill" -> case rest of
        (sid : skid : _) -> (mutating etStation "remove-required-skill")
            { cmEntityId = readMaybe sid, cmTargetId = readMaybe skid }
        (sid : _) -> (mutating etStation "remove-required-skill") { cmEntityId = readMaybe sid }
        _         -> mutating etStation "remove-required-skill"
    "list" -> nonMutating etStation "list"
    _ -> nonMutating etStation (pack op)

-- Skill
classifySkill :: String -> [String] -> CommandMeta
classifySkill op rest = case op of
    "create" -> case rest of
        (sid : _) -> (mutating etSkill "create") { cmEntityId = readMaybe sid }
        _         -> mutating etSkill "create"
    "rename" -> case rest of
        (sid : _) -> (mutating etSkill "rename") { cmEntityId = readMaybe sid }
        _         -> mutating etSkill "rename"
    "delete" -> case rest of
        (sid : _) -> (mutating etSkill "delete") { cmEntityId = readMaybe sid }
        _         -> mutating etSkill "delete"
    "force-delete" -> case rest of
        (sid : _) -> (mutating etSkill "force-delete") { cmEntityId = readMaybe sid }
        _         -> mutating etSkill "force-delete"
    "implication" -> case rest of
        (a : b : _) -> (mutating etSkill "implication")
            { cmEntityId = readMaybe a, cmTargetId = readMaybe b }
        _ -> mutating etSkill "implication"
    "remove-implication" -> case rest of
        (a : b : _) -> (mutating etSkill "remove-implication")
            { cmEntityId = readMaybe a, cmTargetId = readMaybe b }
        _ -> mutating etSkill "remove-implication"
    "view" -> case rest of
        (sid : _) -> (nonMutating etSkill "view") { cmEntityId = readMaybe sid }
        _         -> nonMutating etSkill "view"
    "list" -> nonMutating etSkill "list"
    "info" -> nonMutating etSkill "info"
    _ -> nonMutating etSkill (pack op)

-- Worker
classifyWorker :: String -> [String] -> CommandMeta
classifyWorker op rest = case op of
    "grant-skill" -> twoIds etWorker "grant-skill" rest
    "revoke-skill" -> twoIds etWorker "revoke-skill" rest
    "set-hours" -> oneId etWorker "set-hours" rest
    "set-overtime" -> oneId etWorker "set-overtime" rest
    "set-prefs" -> case rest of
        (wid : sids) ->
            let base = (mutating etWorker "set-prefs") { cmEntityId = readMaybe wid }
            in if null sids then base
               else base { cmParams = Just (pack (toJsonIntList sids)) }
        _ -> mutating etWorker "set-prefs"
    "set-variety" -> oneId etWorker "set-variety" rest
    "set-shift-pref" -> case rest of
        (wid : names) ->
            let base = (mutating etWorker "set-shift-pref") { cmEntityId = readMaybe wid }
            in if null names then base
               else base { cmParams = Just (pack (toJsonStrList names)) }
        _ -> mutating etWorker "set-shift-pref"
    "set-weekend-only" -> oneId etWorker "set-weekend-only" rest
    "set-status" -> oneId etWorker "set-status" rest
    "set-overtime-model" -> oneId etWorker "set-overtime-model" rest
    "set-pay-tracking" -> oneId etWorker "set-pay-tracking" rest
    "set-temp" -> oneId etWorker "set-temp" rest
    "set-seniority" -> twoIds etWorker "set-seniority" rest
    "set-cross-training" -> twoIds etWorker "set-cross-training" rest
    "clear-cross-training" -> twoIds etWorker "clear-cross-training" rest
    "avoid-pairing" -> twoIds etWorker "avoid-pairing" rest
    "clear-avoid-pairing" -> twoIds etWorker "clear-avoid-pairing" rest
    "prefer-pairing" -> twoIds etWorker "prefer-pairing" rest
    "clear-prefer-pairing" -> twoIds etWorker "clear-prefer-pairing" rest
    "info" -> nonMutating etWorker "info"
    _ -> nonMutating etWorker (pack op)

-- Shift
classifyShift :: String -> [String] -> CommandMeta
classifyShift op _rest = case op of
    "create" -> mutating etShift "create"
    "delete" -> mutating etShift "delete"
    "list"   -> nonMutating etShift "list"
    _ -> nonMutating etShift (pack op)

-- Absence type
classifyAbsenceType :: String -> [String] -> CommandMeta
classifyAbsenceType op rest = case op of
    "create" -> case rest of
        (tid : _) -> (mutating etAbsence "type-create") { cmEntityId = readMaybe tid }
        _         -> mutating etAbsence "type-create"
    "list" -> nonMutating etAbsence "type-list"
    _ -> nonMutating etAbsence (pack ("type-" ++ op))

-- Absence
classifyAbsence :: String -> [String] -> CommandMeta
classifyAbsence op rest = case op of
    "set-allowance" -> case rest of
        (wid : tid : _) -> (mutating etAbsence "set-allowance")
            { cmEntityId = readMaybe wid, cmTargetId = readMaybe tid }
        _ -> mutating etAbsence "set-allowance"
    "approve" -> case rest of
        (aid : _) -> (mutating etAbsence "approve") { cmEntityId = readMaybe aid }
        _         -> mutating etAbsence "approve"
    "reject" -> case rest of
        (aid : _) -> (mutating etAbsence "reject") { cmEntityId = readMaybe aid }
        _         -> mutating etAbsence "reject"
    "request" -> case rest of
        (tid : wid : sd : ed : _) -> (mutating etAbsence "request")
            { cmEntityId = readMaybe tid
            , cmTargetId = readMaybe wid
            , cmDateFrom = dateOrNothing sd
            , cmDateTo   = dateOrNothing ed
            }
        _ -> mutating etAbsence "request"
    "list-pending" -> nonMutating etAbsence "list-pending"
    "list" -> nonMutating etAbsence "list"
    _ -> nonMutating etAbsence (pack op)

-- Vacation
classifyVacation :: String -> [String] -> CommandMeta
classifyVacation op _rest = case op of
    "remaining" -> nonMutating etAbsence "vacation-remaining"
    _ -> nonMutating etAbsence (pack ("vacation-" ++ op))

-- User
classifyUser :: String -> [String] -> CommandMeta
classifyUser op rest = case op of
    "create" -> mutating etUser "create"
    "delete" -> case rest of
        (uid : _) -> (mutating etUser "delete") { cmEntityId = readMaybe uid }
        _         -> mutating etUser "delete"
    "list" -> nonMutating etUser "list"
    _ -> nonMutating etUser (pack op)

-- Config
classifyConfig :: String -> [String] -> CommandMeta
classifyConfig op _rest = case op of
    "set"            -> mutating etConfig "set"
    "preset"         -> mutating etConfig "preset"
    "reset"          -> mutating etConfig "reset"
    "set-pay-period" -> mutating etConfig "set-pay-period"
    "show"           -> nonMutating etConfig "show"
    "show-pay-period" -> nonMutating etConfig "show-pay-period"
    "preset-list"    -> nonMutating etConfig "preset-list"
    _ -> nonMutating etConfig (pack op)

-- Pin
classifyPin :: [String] -> CommandMeta
classifyPin (wid : sid : _) = (mutating etPin "add")
    { cmEntityId = readMaybe wid, cmTargetId = readMaybe sid }
classifyPin _ = mutating etPin "add"

classifyUnpin :: [String] -> CommandMeta
classifyUnpin (wid : sid : _) = (mutating etPin "remove")
    { cmEntityId = readMaybe wid, cmTargetId = readMaybe sid }
classifyUnpin _ = mutating etPin "remove"

-- Export / Import
classifyExport :: [String] -> CommandMeta
classifyExport _ = nonMutating etImportExport "export"

classifyImport :: [String] -> CommandMeta
classifyImport _ = mutating etImportExport "import"

-- Checkpoint
classifyCheckpoint :: String -> [String] -> CommandMeta
classifyCheckpoint op _rest = case op of
    "create"   -> nonMutating etCheckpoint "create"
    "commit"   -> nonMutating etCheckpoint "commit"
    "rollback" -> nonMutating etCheckpoint "rollback"
    "list"     -> nonMutating etCheckpoint "list"
    _ -> nonMutating etCheckpoint (pack op)

-- Calendar
classifyCalendar :: String -> [String] -> CommandMeta
classifyCalendar op rest = case op of
    "commit" -> case rest of
        (_name : s : e : _) -> (mutating etCalendar "commit")
            { cmDateFrom = dateOrNothing s, cmDateTo = dateOrNothing e }
        _ -> mutating etCalendar "commit"
    "unfreeze" -> case rest of
        (s : e : _) -> (mutating etCalendar "unfreeze")
            { cmDateFrom = dateOrNothing s, cmDateTo = dateOrNothing e }
        (d : _) -> (mutating etCalendar "unfreeze")
            { cmDateFrom = dateOrNothing d, cmDateTo = dateOrNothing d }
        _ -> mutating etCalendar "unfreeze"
    "view"            -> nonMutating etCalendar "view"
    "view-by-worker"  -> nonMutating etCalendar "view-by-worker"
    "view-by-station" -> nonMutating etCalendar "view-by-station"
    "view-compact"    -> nonMutating etCalendar "view-compact"
    "hours"           -> nonMutating etCalendar "hours"
    "diagnose"        -> nonMutating etCalendar "diagnose"
    "history"         -> nonMutating etCalendar "history"
    "freeze-status"   -> nonMutating etCalendar "freeze-status"
    _ -> nonMutating etCalendar (pack op)

-- Draft
classifyDraft :: String -> [String] -> CommandMeta
classifyDraft op rest = case op of
    "create" -> case rest of
        (s : e : _) -> (mutating etDraft "create")
            { cmDateFrom = dateOrNothing s, cmDateTo = dateOrNothing e }
        _ -> mutating etDraft "create"
    "this-month" -> mutating etDraft "this-month"
    "next-month" -> mutating etDraft "next-month"
    "generate" -> case rest of
        (did : _) -> (mutating etDraft "generate") { cmEntityId = readMaybe did }
        _         -> mutating etDraft "generate"
    "commit" -> case rest of
        (did : _) -> (mutating etDraft "commit") { cmEntityId = readMaybe did }
        _         -> mutating etDraft "commit"
    "discard" -> case rest of
        (did : _) -> (mutating etDraft "discard") { cmEntityId = readMaybe did }
        _         -> mutating etDraft "discard"
    "list"         -> nonMutating etDraft "list"
    "open"         -> nonMutating etDraft "open"
    "view"         -> nonMutating etDraft "view"
    "view-compact" -> nonMutating etDraft "view-compact"
    "hours"        -> nonMutating etDraft "hours"
    "diagnose"     -> nonMutating etDraft "diagnose"
    _ -> nonMutating etDraft (pack op)

-- What-if
classifyWhatIf :: String -> [String] -> CommandMeta
classifyWhatIf op rest = case op of
    "apply" -> mutating etWhatIf "apply"
    -- All other what-if commands are non-mutating explorations
    "close-station" -> case rest of
        (sid : _) -> (nonMutating etWhatIf "close-station") { cmEntityId = readMaybe sid }
        _         -> nonMutating etWhatIf "close-station"
    "pin" -> case rest of
        (wid : sid : _) -> (nonMutating etWhatIf "pin")
            { cmEntityId = readMaybe wid, cmTargetId = readMaybe sid }
        _ -> nonMutating etWhatIf "pin"
    "add-worker" -> nonMutating etWhatIf "add-worker"
    "waive-overtime" -> case rest of
        (wid : _) -> (nonMutating etWhatIf "waive-overtime") { cmEntityId = readMaybe wid }
        _         -> nonMutating etWhatIf "waive-overtime"
    "grant-skill" -> case rest of
        (wid : sid : _) -> (nonMutating etWhatIf "grant-skill")
            { cmEntityId = readMaybe wid, cmTargetId = readMaybe sid }
        _ -> nonMutating etWhatIf "grant-skill"
    "override-prefs" -> case rest of
        (wid : sids) ->
            let base = (nonMutating etWhatIf "override-prefs") { cmEntityId = readMaybe wid }
            in if null sids then base
               else base { cmParams = Just (pack (toJsonIntList sids)) }
        _ -> nonMutating etWhatIf "override-prefs"
    "revert"     -> nonMutating etWhatIf "revert"
    "revert-all" -> nonMutating etWhatIf "revert-all"
    "list"       -> nonMutating etWhatIf "list"
    "rebase"     -> nonMutating etWhatIf "rebase"
    _ -> nonMutating etWhatIf (pack op)

-- =====================================================================
-- render
-- =====================================================================

-- | Render structured metadata back into a human-readable command string.
render :: CommandMeta -> String
render meta = case (cmEntityType meta, cmOperation meta) of
    (Nothing, _) -> ""
    (_, Nothing) -> ""
    (Just et, Just op) -> unwords $ catMaybes $ renderParts et op meta

renderParts :: Text -> Text -> CommandMeta -> [Maybe String]
renderParts et op meta
    -- Schedule-level assign/unassign: "assign <sched> <wid> <sid>"
    | et == etSchedule && op == "assign" =
        [ Just "assign", Just "?", fmap show (cmEntityId meta), fmap show (cmTargetId meta) ]
    | et == etSchedule && op == "unassign" =
        [ Just "unassign", Just "?", fmap show (cmEntityId meta), fmap show (cmTargetId meta) ]
    -- Absence type commands use "absence-type" prefix
    | et == etAbsence && "type-" `isPrefixOf` unpack op =
        [ Just "absence-type", Just (drop 5 (unpack op)) ]
        ++ idParts meta
    | et == etAbsence && "vacation-" `isPrefixOf` unpack op =
        [ Just "vacation", Just (drop 9 (unpack op)) ]
        ++ idParts meta
    -- Pin: "pin <wid> <sid> ..." or "unpin <wid> <sid> ..."
    | et == etPin && op == "add" =
        [ Just "pin" ] ++ idParts meta
    | et == etPin && op == "remove" =
        [ Just "unpin" ] ++ idParts meta
    | et == etPin && op == "list" =
        [ Just "pin", Just "list" ]
    -- Import/Export
    | et == etImportExport && op == "export" =
        [ Just "export" ]
    | et == etImportExport && op == "import" =
        [ Just "import" ]
    -- Calendar commit has name placeholder
    | et == etCalendar && op == "commit" =
        [ Just "calendar", Just "commit", Just "?" ]
        ++ dateParts meta
    -- What-if: "what-if <op> ..."
    | et == etWhatIf =
        [ Just "what-if", Just (unpack op) ]
        ++ idParts meta
        ++ paramsParts meta
    -- Worker variadic commands
    | et == etWorker && op `elem` ["set-prefs", "set-shift-pref", "override-prefs"] =
        [ Just (unpack et), Just (unpack op) ]
        ++ idParts meta
        ++ paramsParts meta
    -- Standard: "<entity> <op> [ids] [dates]"
    | otherwise =
        [ Just (unpack et), Just (unpack op) ]
        ++ idParts meta
        ++ dateParts meta
        ++ paramsParts meta

idParts :: CommandMeta -> [Maybe String]
idParts meta =
    [ fmap show (cmEntityId meta)
    , fmap show (cmTargetId meta)
    ]

dateParts :: CommandMeta -> [Maybe String]
dateParts meta =
    [ fmap unpack (cmDateFrom meta)
    , fmap unpack (cmDateTo meta)
    ]

paramsParts :: CommandMeta -> [Maybe String]
paramsParts meta = case cmParams meta of
    Nothing -> []
    Just p  -> map Just (parseJsonList (unpack p))

-- =====================================================================
-- Helpers
-- =====================================================================

-- | Create a mutating CommandMeta with entity type and operation.
mutating :: Text -> Text -> CommandMeta
mutating et op = defaultMeta
    { cmEntityType = Just et
    , cmOperation  = Just op
    , cmIsMutation = True
    }

-- | Create a non-mutating CommandMeta with entity type and operation.
nonMutating :: Text -> Text -> CommandMeta
nonMutating et op = defaultMeta
    { cmEntityType = Just et
    , cmOperation  = Just op
    , cmIsMutation = False
    }

-- | Extract one entity ID from the first argument.
oneId :: Text -> Text -> [String] -> CommandMeta
oneId et op (x : _) = (mutating et op) { cmEntityId = readMaybe x }
oneId et op _       = mutating et op

-- | Extract two IDs from the first two arguments.
twoIds :: Text -> Text -> [String] -> CommandMeta
twoIds et op (x : y : _) = (mutating et op)
    { cmEntityId = readMaybe x, cmTargetId = readMaybe y }
twoIds et op (x : _) = (mutating et op) { cmEntityId = readMaybe x }
twoIds et op _       = mutating et op

-- | Try to read an Int from a string.
readMaybe :: String -> Maybe Int
readMaybe s
    | not (null s) && all isDigit s = Just (read s)
    | otherwise = Nothing

-- | Check if a string looks like a date (YYYY-MM-DD).
isDate :: String -> Bool
isDate s = length s == 10
    && s !! 4 == '-'
    && s !! 7 == '-'
    && all isDigit (take 4 s ++ take 2 (drop 5 s) ++ take 2 (drop 8 s))

-- | Return the string as Text if it looks like a date, Nothing otherwise.
dateOrNothing :: String -> Maybe Text
dateOrNothing s = if isDate s then Just (pack s) else Nothing

-- | Encode a list of numeric strings as a JSON array of ints: "[1,2,4]"
toJsonIntList :: [String] -> String
toJsonIntList ss =
    let nums = [s | s <- ss, not (null s), all isDigit s]
    in "[" ++ intercalate "," nums ++ "]"

-- | Encode a list of strings as a JSON array: "[\"a\",\"b\"]"
toJsonStrList :: [String] -> String
toJsonStrList ss =
    "[" ++ intercalate "," (map (\s -> "\"" ++ s ++ "\"") ss) ++ "]"

-- | Parse a simple JSON list back into strings.
-- Handles "[1,2,4]" -> ["1","2","4"] and "[\"a\",\"b\"]" -> ["a","b"]
parseJsonList :: String -> [String]
parseJsonList s =
    let inner = dropWhile (== '[') $ reverse $ dropWhile (== ']') $ reverse s
        parts = splitOn' ',' inner
    in map stripQuotes parts
  where
    stripQuotes ('"' : rest) = reverse $ drop 1 $ reverse rest
    stripQuotes x = x

-- | Split a string on a separator character.
splitOn' :: Char -> String -> [String]
splitOn' _ "" = []
splitOn' sep s =
    let (chunk, rest) = break (== sep) s
    in chunk : case rest of
        []     -> []
        (_:xs) -> splitOn' sep xs
