module CLI.Resolve
    ( EntityKind(..)
    , EntityRef(..)
    , SessionContext
    , emptyContext
    , resolveInput
    , lookupByName
    , entityKindName
    ) where

import Data.Char (toLower, isDigit)
import Data.List (find, isPrefixOf)
import Data.IORef
import qualified Data.Map.Strict as Map
import qualified Data.Text as T
import Repo.Types (Repository(..))
import CLI.Commands (shellWords)
import Auth.Types (User(..), Username(..))
import Domain.Types (WorkerId(..), SkillId(..), StationId(..), AbsenceTypeId(..))
import Domain.Skill (Skill(..))
import Domain.Absence (AbsenceType(..), AbsenceContext(..))

-- | Entity types that can be resolved by name.
data EntityKind = EWorker | ESkill | EStation | EAbsenceType
    deriving (Eq, Ord, Show)

-- | A resolved entity reference: ID + display name.
data EntityRef = EntityRef
    { erId   :: !Int
    , erName :: !String
    } deriving (Show)

-- | Session context: active entity per type.
type SessionContext = Map.Map EntityKind EntityRef

emptyContext :: SessionContext
emptyContext = Map.empty

-- | What to do with each argument after the command prefix.
data ArgSpec
    = Resolve EntityKind   -- ^ Look up this argument as the given entity kind
    | Skip                 -- ^ Leave this argument alone
    | ResolveRest EntityKind -- ^ All remaining arguments are this entity kind

-- | Mapping from command prefix to resolution rules for remaining args.
commandEntityMap :: [([String], [ArgSpec])]
commandEntityMap =
    [ (["worker", "grant-skill"],          [Resolve EWorker, Resolve ESkill])
    , (["worker", "revoke-skill"],         [Resolve EWorker, Resolve ESkill])
    , (["worker", "set-hours"],            [Resolve EWorker, Skip])
    , (["worker", "set-overtime"],         [Resolve EWorker, Skip])
    , (["worker", "set-prefs"],            [Resolve EWorker, ResolveRest EStation])
    , (["worker", "set-variety"],          [Resolve EWorker, Skip])
    , (["worker", "set-shift-pref"],       [Resolve EWorker])  -- rest are shift names, not entities
    , (["worker", "set-weekend-only"],     [Resolve EWorker, Skip])
    , (["worker", "set-seniority"],        [Resolve EWorker, Skip])
    , (["worker", "set-cross-training"],   [Resolve EWorker, Resolve ESkill])
    , (["worker", "clear-cross-training"], [Resolve EWorker, Resolve ESkill])
    , (["worker", "avoid-pairing"],        [Resolve EWorker, Resolve EWorker])
    , (["worker", "clear-avoid-pairing"],  [Resolve EWorker, Resolve EWorker])
    , (["worker", "prefer-pairing"],       [Resolve EWorker, Resolve EWorker])
    , (["worker", "clear-prefer-pairing"], [Resolve EWorker, Resolve EWorker])
    , (["station", "remove"],              [Resolve EStation])
    , (["station", "set-hours"],           [Resolve EStation, Skip, Skip])
    , (["station", "set-multi-hours"],     [Resolve EStation, Skip, Skip])
    , (["station", "close-day"],           [Resolve EStation, Skip])
    , (["station", "require-skill"],       [Resolve EStation, Resolve ESkill])
    , (["station", "remove-required-skill"], [Resolve EStation, Resolve ESkill])
    , (["skill", "view"],                  [Resolve ESkill])
    , (["skill", "delete"],                [Resolve ESkill])
    , (["skill", "force-delete"],           [Resolve ESkill])
    , (["skill", "implication"],           [Resolve ESkill, Resolve ESkill])
    , (["skill", "remove-implication"],  [Resolve ESkill, Resolve ESkill])
    , (["assign"],                         [Skip, Resolve EWorker, Resolve EStation, Skip, Skip])
    , (["unassign"],                       [Skip, Resolve EWorker, Resolve EStation, Skip, Skip])
    , (["absence", "set-allowance"],       [Resolve EWorker, Resolve EAbsenceType, Skip])
    , (["absence", "request"],             [Resolve EAbsenceType, Resolve EWorker, Skip, Skip])
    , (["vacation", "remaining"],          [Resolve EAbsenceType])
    , (["pin"],                            [Resolve EWorker, Resolve EStation, Skip, Skip])
    , (["unpin"],                          [Resolve EWorker, Resolve EStation, Skip, Skip])
    -- What-if (add-worker omitted: handler resolves skills due to complex arg structure)
    , (["what-if", "close-station"],       [Resolve EStation, Skip, Skip])
    , (["what-if", "pin"],                 [Resolve EWorker, Resolve EStation, Skip, Skip])
    , (["what-if", "waive-overtime"],      [Resolve EWorker])
    , (["what-if", "grant-skill"],         [Resolve EWorker, Resolve ESkill])
    , (["what-if", "override-prefs"],      [Resolve EWorker, ResolveRest EStation])
    ]

-- | Find the matching command prefix and its resolution specs.
findMapping :: [String] -> Maybe (Int, [ArgSpec])
findMapping ws =
    -- Try longest prefix first (2 words, then 1 word)
    case find (\(prefix, _) -> prefix `isPrefixOf` ws) (commandsOfPrefixLen 2) of
        Just (_, specs) -> Just (2, specs)
        Nothing -> case find (\(prefix, _) -> prefix `isPrefixOf` ws) (commandsOfPrefixLen 1) of
            Just (_, specs) -> Just (1, specs)
            Nothing -> Nothing
  where
    commandsOfPrefixLen n = filter (\(p, _) -> length p == n) commandEntityMap

-- | Resolve entity names in input, substituting dots from context.
-- Returns the line with names replaced by IDs, or an error message.
resolveInput :: Repository -> IORef SessionContext -> String -> IO (Either String String)
resolveInput repo ctxRef input = do
    let ws = shellWords input
    case findMapping ws of
        Nothing -> return (Right input)  -- no resolution needed
        Just (prefixLen, specs) -> do
            ctx <- readIORef ctxRef
            let prefix = take prefixLen ws
                args   = drop prefixLen ws
            result <- resolveArgs repo ctx specs args
            case result of
                Left err -> return (Left err)
                Right resolvedArgs ->
                    return (Right (unwords (prefix ++ resolvedArgs)))

-- | Resolve a list of arguments according to their specs.
resolveArgs :: Repository -> SessionContext -> [ArgSpec] -> [String]
            -> IO (Either String [String])
resolveArgs repo ctx specs args = go specs args []
  where
    go [] remaining acc = return (Right (reverse acc ++ remaining))
    go _ [] acc = return (Right (reverse acc))
    go (ResolveRest kind : _) remaining acc = do
        results <- mapM (resolveOne repo ctx kind) remaining
        case sequence results of
            Left err -> return (Left err)
            Right resolved -> return (Right (reverse acc ++ resolved))
    go (Skip : rest) (a:as) acc = go rest as (a : acc)
    go (Resolve kind : rest) (a:as) acc = do
        result <- resolveOne repo ctx kind a
        case result of
            Left err -> return (Left err)
            Right resolved -> go rest as (resolved : acc)

-- | Resolve a single token: handle dot substitution, numeric passthrough, name lookup.
resolveOne :: Repository -> SessionContext -> EntityKind -> String
           -> IO (Either String String)
resolveOne _repo ctx kind "." =
    case Map.lookup kind ctx of
        Just ref -> return (Right (show (erId ref)))
        Nothing  -> return (Left ("No " ++ entityKindName kind
                                  ++ " context set. Use 'use "
                                  ++ entityKindName kind ++ " <name>' first."))
resolveOne repo _ctx kind token
    | all isDigit token && not (null token) = return (Right token)  -- numeric, use as-is
    | otherwise = lookupByName repo kind token

-- | Look up an entity by name (case-insensitive).
lookupByName :: Repository -> EntityKind -> String -> IO (Either String String)
lookupByName repo EWorker name = do
    users <- repoListUsers repo
    let nameLower = T.toLower (T.pack name)
        matches = [ userWorkerId u
                  | u <- users
                  , let Username uname = userName u
                  , T.toLower uname == nameLower
                  ]
    case matches of
        [WorkerId wid] -> return (Right (show wid))
        []             -> return (Left ("Unknown worker: " ++ name))
        _              -> return (Left ("Ambiguous worker: " ++ name))
lookupByName repo ESkill name = do
    skills <- repoListSkills repo
    let matches = [ sid
                  | (SkillId sid, sk) <- skills
                  , map toLower (T.unpack $ skillName sk) == map toLower name
                  ]
    case matches of
        [sid] -> return (Right (show sid))
        []    -> return (Left ("Unknown skill: " ++ name))
        _     -> return (Left ("Ambiguous skill: " ++ name))
lookupByName repo EStation name = do
    stations <- repoListStations repo
    let nameLower = T.toLower (T.pack name)
        matches = [ sid
                  | (StationId sid, sname) <- stations
                  , T.toLower sname == nameLower
                  ]
    case matches of
        [sid] -> return (Right (show sid))
        []    -> return (Left ("Unknown station: " ++ name))
        _     -> return (Left ("Ambiguous station: " ++ name))
lookupByName repo EAbsenceType name = do
    ctx <- repoLoadAbsenceCtx repo
    let nameLower = T.toLower (T.pack name)
        matches = [ tid
                  | (AbsenceTypeId tid, at) <- Map.toList (acTypes ctx)
                  , T.toLower (atName at) == nameLower
                  ]
    case matches of
        [tid] -> return (Right (show tid))
        []    -> return (Left ("Unknown absence type: " ++ name))
        _     -> return (Left ("Ambiguous absence type: " ++ name))

entityKindName :: EntityKind -> String
entityKindName EWorker      = "worker"
entityKindName ESkill       = "skill"
entityKindName EStation     = "station"
entityKindName EAbsenceType = "absence-type"
