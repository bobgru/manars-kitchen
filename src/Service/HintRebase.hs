{-# LANGUAGE OverloadedStrings #-}
module Service.HintRebase
    ( ChangeCategory(..)
    , RebaseResult(..)
    , classifyChange
    , rebaseSession
    , spec
    ) where

import Test.Hspec
import Data.Time (TimeOfDay(..))

import Domain.Types (WorkerId(..), StationId(..), SkillId(..), Slot(..))
import Domain.Hint (Hint(..))
import Repo.Types (AuditEntry(..))
import Audit.CommandMeta
    ( CommandMeta(..)
    , classify
    , etWorker, etStation, etSkill, etDraft , etPin
    )

-- | How a single audit entry relates to the active hint set.
data ChangeCategory
    = Irrelevant     -- ^ Does not affect scheduler context at all
    | Compatible     -- ^ Affects context but no hint references the same entities
    | Conflicting    -- ^ Directly contradicts one or more hints
    | Structural     -- ^ Changes the draft itself (commit/discard) — session invalid
    deriving (Eq, Ord, Show)

-- | Result of classifying all audit entries since the checkpoint.
data RebaseResult
    = UpToDate
      -- ^ No mutations since checkpoint.
    | AutoRebase !Int
      -- ^ All changes were irrelevant or compatible. Int = number of changes processed.
    | HasConflicts ![(AuditEntry, ChangeCategory)]
      -- ^ Some entries are conflicting. Includes all entries with their categories.
    | SessionInvalid !String
      -- ^ A structural change invalidated the session (e.g., draft committed).
    deriving (Eq, Show)

-- | Classify a single audit entry against the active hint list.
-- Uses the entry's command string to derive CommandMeta, then checks
-- for entity overlap with hints.
classifyChange :: Int -> AuditEntry -> [Hint] -> ChangeCategory
classifyChange draftId entry hints =
    let meta = case aeCommand entry of
            Just cmd -> classify cmd
            Nothing  -> CommandMeta Nothing Nothing Nothing Nothing Nothing Nothing False Nothing
    in classifyMeta draftId meta hints

-- | Core classification logic on structured metadata.
classifyMeta :: Int -> CommandMeta -> [Hint] -> ChangeCategory
classifyMeta draftId meta hints
    -- Structural: draft commit/discard for our draft
    | isStructural draftId meta = Structural
    -- Non-mutating entries are irrelevant (shouldn't appear since we filter,
    -- but handle defensively)
    | not (cmIsMutation meta) = Irrelevant
    -- Check if this mutation affects any hint
    | any (conflictsWith meta) hints = Conflicting
    -- Mutation that doesn't touch any scheduler context
    | isIrrelevantEntity meta = Irrelevant
    -- Mutation that affects scheduler context but no hint conflicts
    | otherwise = Compatible

-- | Check if this is a structural change (draft commit/discard).
isStructural :: Int -> CommandMeta -> Bool
isStructural _draftId meta = case (cmEntityType meta, cmOperation meta) of
    (Just et, Just op) | et == etDraft && op `elem` ["commit", "discard"] -> True
    _ -> False

-- | Entities that never affect scheduler context.
isIrrelevantEntity :: CommandMeta -> Bool
isIrrelevantEntity meta = case cmEntityType meta of
    Just et | et `elem` irrelevantEntities -> True
    _ -> False
  where
    irrelevantEntities =
        [ "user", "import-export", "checkpoint", "absence"
        , "shift"  -- shifts don't overlap with hint entity types
        ]

-- | Check if a mutation conflicts with a specific hint.
conflictsWith :: CommandMeta -> Hint -> Bool
conflictsWith meta hint = case hint of
    GrantSkill (WorkerId wid) (SkillId sid) ->
        -- Conflicts with: worker revoke-skill w s, skill implication changes involving s
        matchWorkerSkill meta wid sid
        || matchSkillImplication meta sid

    WaiveOvertime (WorkerId wid) ->
        -- Conflicts with: worker set-overtime w (any value)
        matchWorkerOvertime meta wid

    OverridePreference (WorkerId wid) _ ->
        -- Conflicts with: worker set-prefs w ...
        matchWorkerPrefs meta wid

    CloseStation (StationId sid) _ ->
        -- Conflicts with: station mutations affecting this station
        matchStationMutation meta sid

    PinAssignment (WorkerId wid) (StationId sid) _ ->
        -- Conflicts with: mutations to worker w or station s
        matchWorkerMutation meta wid || matchStationMutation meta sid

    AddWorker {} ->
        -- AddWorker introduces synthetic entities — only structural changes conflict
        False

-- | Worker revoke-skill for the same worker+skill pair.
matchWorkerSkill :: CommandMeta -> Int -> Int -> Bool
matchWorkerSkill meta wid sid = case (cmEntityType meta, cmOperation meta) of
    (Just et, Just op) | et == etWorker && op == "revoke-skill" ->
        cmEntityId meta == Just wid && cmTargetId meta == Just sid
    _ -> False

-- | Skill implication change involving the skill.
matchSkillImplication :: CommandMeta -> Int -> Bool
matchSkillImplication meta sid = case (cmEntityType meta, cmOperation meta) of
    (Just et, Just op) | et == etSkill && op == "implication" ->
        cmEntityId meta == Just sid || cmTargetId meta == Just sid
    _ -> False

-- | Worker set-overtime for the same worker.
matchWorkerOvertime :: CommandMeta -> Int -> Bool
matchWorkerOvertime meta wid = case (cmEntityType meta, cmOperation meta) of
    (Just et, Just op) | et == etWorker && op == "set-overtime" ->
        cmEntityId meta == Just wid
    _ -> False

-- | Worker set-prefs for the same worker.
matchWorkerPrefs :: CommandMeta -> Int -> Bool
matchWorkerPrefs meta wid = case (cmEntityType meta, cmOperation meta) of
    (Just et, Just op) | et == etWorker && op == "set-prefs" ->
        cmEntityId meta == Just wid
    _ -> False

-- | Any mutation to a specific station.
matchStationMutation :: CommandMeta -> Int -> Bool
matchStationMutation meta sid = case cmEntityType meta of
    Just et | et == etStation -> cmEntityId meta == Just sid
    Just et | et == etPin -> cmEntityId meta == Just sid || cmTargetId meta == Just sid
    _ -> False

-- | Any mutation to a specific worker.
matchWorkerMutation :: CommandMeta -> Int -> Bool
matchWorkerMutation meta wid = case cmEntityType meta of
    Just et | et == etWorker -> cmEntityId meta == Just wid
    _ -> False

-- | Classify all audit entries and produce a rebase result.
-- If the list is empty, returns UpToDate.
-- If any entry is Structural, returns SessionInvalid.
-- If any entry is Conflicting, returns HasConflicts with all entries.
-- Otherwise returns AutoRebase.
rebaseSession :: Int -> [AuditEntry] -> [Hint] -> RebaseResult
rebaseSession _draftId [] _hints = UpToDate
rebaseSession draftId entries hints =
    let classified = [(e, classifyChange draftId e hints) | e <- entries]
        hasStructural = any ((== Structural) . snd) classified
        hasConflicting = any ((== Conflicting) . snd) classified
    in if hasStructural
       then SessionInvalid "Draft was committed or discarded since last save."
       else if hasConflicting
            then HasConflicts classified
            else AutoRebase (length entries)

-- ---------------------------------------------------------------------
-- Tests
-- ---------------------------------------------------------------------

mkEntry :: Int -> String -> AuditEntry
mkEntry eid cmd = AuditEntry
    { aeId = eid
    , aeTimestamp = "2026-04-12 10:00:00"
    , aeUsername = "test"
    , aeCommand = Just cmd
    , aeEntityType = Nothing
    , aeOperation = Nothing
    , aeEntityId = Nothing
    , aeTargetId = Nothing
    , aeDateFrom = Nothing
    , aeDateTo = Nothing
    , aeIsMutation = True
    , aeParams = Nothing
    , aeSource = "cli"
    }

spec :: Spec
spec = do
    describe "classifyChange" $ do
        let hints = [GrantSkill (WorkerId 3) (SkillId 2)]

        it "user create is irrelevant" $
            classifyChange 1 (mkEntry 1 "user create alice pass admin") hints
                `shouldBe` Irrelevant

        it "station add (different station) is compatible" $
            classifyChange 1 (mkEntry 2 "station add 5 dishwash") hints
                `shouldBe` Compatible

        it "worker revoke-skill same pair is conflicting" $
            classifyChange 1 (mkEntry 3 "worker revoke-skill 3 2") hints
                `shouldBe` Conflicting

        it "worker revoke-skill different pair is compatible" $
            classifyChange 1 (mkEntry 4 "worker revoke-skill 3 9") hints
                `shouldBe` Compatible

        it "draft commit is structural" $
            classifyChange 1 (mkEntry 5 "draft commit 1") hints
                `shouldBe` Structural

        it "draft discard is structural" $
            classifyChange 1 (mkEntry 6 "draft discard 1") hints
                `shouldBe` Structural

    describe "WaiveOvertime conflicts" $ do
        let hints = [WaiveOvertime (WorkerId 5)]

        it "worker set-overtime same worker is conflicting" $
            classifyChange 1 (mkEntry 1 "worker set-overtime 5 off") hints
                `shouldBe` Conflicting

        it "worker set-overtime different worker is compatible" $
            classifyChange 1 (mkEntry 2 "worker set-overtime 6 off") hints
                `shouldBe` Compatible

    describe "OverridePreference conflicts" $ do
        let hints = [OverridePreference (WorkerId 3) [StationId 1]]

        it "worker set-prefs same worker is conflicting" $
            classifyChange 1 (mkEntry 1 "worker set-prefs 3 1 2") hints
                `shouldBe` Conflicting

        it "worker set-prefs different worker is compatible" $
            classifyChange 1 (mkEntry 2 "worker set-prefs 4 1") hints
                `shouldBe` Compatible

    describe "CloseStation conflicts" $ do
        let hints = [CloseStation (StationId 1) (Slot (toEnum 0) (TimeOfDay 9 0 0) 3600)]

        it "station mutation to same station is conflicting" $
            classifyChange 1 (mkEntry 1 "station set-hours 1 8 17") hints
                `shouldBe` Conflicting

        it "station mutation to different station is compatible" $
            classifyChange 1 (mkEntry 2 "station set-hours 2 8 17") hints
                `shouldBe` Compatible

    describe "PinAssignment conflicts" $ do
        let hints = [PinAssignment (WorkerId 1) (StationId 2) (Slot (toEnum 0) (TimeOfDay 9 0 0) 3600)]

        it "worker mutation to pinned worker is conflicting" $
            classifyChange 1 (mkEntry 1 "worker set-hours 1 20") hints
                `shouldBe` Conflicting

        it "station mutation to pinned station is conflicting" $
            classifyChange 1 (mkEntry 2 "station set-hours 2 9 17") hints
                `shouldBe` Conflicting

    describe "GrantSkill + skill implication" $ do
        let hints = [GrantSkill (WorkerId 5) (SkillId 2)]

        it "skill implication involving the granted skill is conflicting" $
            classifyChange 1 (mkEntry 1 "skill implication 2 3") hints
                `shouldBe` Conflicting

        it "skill implication not involving the granted skill is compatible" $
            classifyChange 1 (mkEntry 2 "skill implication 4 5") hints
                `shouldBe` Compatible

    describe "rebaseSession" $ do
        let hints = [GrantSkill (WorkerId 3) (SkillId 2)]

        it "empty entries -> UpToDate" $
            rebaseSession 1 [] hints `shouldBe` UpToDate

        it "all irrelevant -> AutoRebase" $
            let entries = [mkEntry 1 "user create x y admin"]
            in case rebaseSession 1 entries hints of
                AutoRebase n -> n `shouldBe` 1
                other -> expectationFailure ("Expected AutoRebase, got: " ++ show other)

        it "conflicting entry -> HasConflicts" $
            let entries = [mkEntry 1 "worker revoke-skill 3 2"]
            in case rebaseSession 1 entries hints of
                HasConflicts cs -> length cs `shouldBe` 1
                other -> expectationFailure ("Expected HasConflicts, got: " ++ show other)

        it "structural entry -> SessionInvalid" $
            let entries = [mkEntry 1 "draft commit 1"]
            in case rebaseSession 1 entries hints of
                SessionInvalid _ -> return ()
                other -> expectationFailure ("Expected SessionInvalid, got: " ++ show other)
