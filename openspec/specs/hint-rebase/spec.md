## ADDED Requirements

### Requirement: Query audit entries since checkpoint
The system SHALL provide a `repoAuditSince` function that returns all audit log entries with `id > checkpoint` and `is_mutation = 1`, ordered by ID ascending. Each entry SHALL include the full `CommandMeta` fields.

#### Scenario: No mutations since checkpoint
- **WHEN** `repoAuditSince 42` is called and the latest audit entry ID is 42
- **THEN** the system returns an empty list

#### Scenario: Multiple mutations since checkpoint
- **WHEN** `repoAuditSince 42` is called and audit entries 43 (mutation), 44 (non-mutation), 45 (mutation) exist
- **THEN** the system returns entries 43 and 45 in order

### Requirement: Change classification
The system SHALL classify each audit entry into one of four categories relative to the active hint list: **irrelevant** (does not affect scheduler context), **compatible** (affects context but does not conflict with any hint), **conflicting** (directly contradicts one or more hints), or **structural** (changes the draft itself, invalidating the session).

#### Scenario: Irrelevant change
- **WHEN** the audit entry is `user create` and hints are `[GrantSkill 3 2]`
- **THEN** the entry is classified as irrelevant

#### Scenario: Compatible change
- **WHEN** the audit entry is `station add 5 dishwash` and hints are `[GrantSkill 3 2]`
- **THEN** the entry is classified as compatible (new station doesn't overlap with any hint)

#### Scenario: Conflicting change — revoke vs grant
- **WHEN** the audit entry is `worker revoke-skill 3 2` and hints include `GrantSkill (WorkerId 3) (SkillId 2)`
- **THEN** the entry is classified as conflicting

#### Scenario: Conflicting change — overtime off vs waive
- **WHEN** the audit entry is `worker set-overtime 5 off` and hints include `WaiveOvertime (WorkerId 5)`
- **THEN** the entry is classified as conflicting

#### Scenario: Conflicting change — preference change vs override
- **WHEN** the audit entry is `worker set-prefs 3 1 2` and hints include `OverridePreference (WorkerId 3) [StationId 1]`
- **THEN** the entry is classified as conflicting

#### Scenario: Structural change — draft commit
- **WHEN** the audit entry is `draft commit 1` and the hint session is for draft 1
- **THEN** the entry is classified as structural

#### Scenario: Structural change — draft discard
- **WHEN** the audit entry is `draft discard 1` and the hint session is for draft 1
- **THEN** the entry is classified as structural

#### Scenario: Skill implication change conflicts with GrantSkill
- **WHEN** the audit entry is `skill implication 2 3` and hints include `GrantSkill (WorkerId 5) (SkillId 2)`
- **THEN** the entry is classified as conflicting (implication change may alter effective skills)

### Requirement: Rebase command
The system SHALL provide `what-if rebase` that reconciles a stale hint session with data changes. The command SHALL query audit entries since the checkpoint, classify each, and then proceed based on the classification results.

#### Scenario: Rebase with no changes
- **WHEN** the user runs `what-if rebase` and no mutations occurred since checkpoint
- **THEN** the system displays "Hint session is up to date. No rebase needed."

#### Scenario: Rebase with only irrelevant/compatible changes
- **WHEN** the user runs `what-if rebase` and all mutations since checkpoint are irrelevant or compatible
- **THEN** the system auto-rebases: rebuilds the session from current context with existing hints, updates the checkpoint, and displays "Rebased over N changes. All hints preserved."

#### Scenario: Rebase with conflicting changes
- **WHEN** the user runs `what-if rebase` and some mutations conflict with hints
- **THEN** the system displays each conflict (e.g., "Conflict: hint 2 (GrantSkill carol cooking) vs. 'worker revoke-skill 3 2'") and prompts: "[D]rop conflicting hints / [K]eep all (force) / [A]bort"

#### Scenario: Rebase drop conflicting
- **WHEN** the user chooses "Drop" during rebase with 3 hints where hint 2 conflicts
- **THEN** hints 1 and 3 are retained, hint 2 is removed, the session is rebuilt and saved with updated checkpoint

#### Scenario: Rebase keep all (force)
- **WHEN** the user chooses "Keep" during rebase
- **THEN** all hints are retained, the session is rebuilt from current context (the conflicting hint may now have different effects), checkpoint is updated

#### Scenario: Rebase abort
- **WHEN** the user chooses "Abort" during rebase
- **THEN** the session is unchanged, checkpoint is not updated

#### Scenario: Rebase with structural changes
- **WHEN** the user runs `what-if rebase` and a structural change (draft commit/discard) occurred
- **THEN** the system displays "Draft was committed/discarded since last save. Hint session is no longer valid." and deletes the persisted session

### Requirement: Large gap detection
The system SHALL detect when the number of mutating audit entries since checkpoint exceeds a threshold (50). In this case, the system SHALL skip per-entry classification and prompt "Significant changes since last save (N mutations). Discard session or force resume?"

#### Scenario: Large audit gap
- **WHEN** the user resumes a session and there are 60 mutations since checkpoint
- **THEN** the system displays "Significant changes since last save (60 mutations). [D]iscard / [F]orce resume?"

### Requirement: Stale session detection on resume
When resuming a persisted hint session, the system SHALL check for audit entries since the checkpoint. If any mutations exist, the system SHALL inform the user and trigger the rebase flow before allowing hint operations.

#### Scenario: Resume with stale session
- **WHEN** the user resumes a hint session and 3 mutations occurred since checkpoint
- **THEN** the system displays "3 changes since last save. Running rebase..." and executes the rebase flow

#### Scenario: Resume with fresh session
- **WHEN** the user resumes a hint session and no mutations occurred since checkpoint
- **THEN** the session resumes directly with no rebase prompt
