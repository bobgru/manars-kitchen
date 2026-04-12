## 1. Hint JSON Serialization

- [x] 1.1 Add Aeson dependency and derive/write ToJSON/FromJSON instances for Hint (tagged encoding with Slot as day/hour/duration)
- [x] 1.2 Add round-trip property tests for all 6 hint variants

## 2. Database Schema and Repo

- [x] 2.1 Add `hint_sessions` table to `Repo.Schema` (session_id, draft_id, hints_json, checkpoint, created_at, updated_at)
- [x] 2.2 Implement `repoSaveHintSession` (upsert by session_id + draft_id)
- [x] 2.3 Implement `repoLoadHintSession` (returns Maybe (hints, checkpoint))
- [x] 2.4 Implement `repoDeleteHintSession` (delete by session_id + draft_id)
- [x] 2.5 Implement `repoAuditSince` (query audit_log where id > checkpoint AND is_mutation = 1)
- [x] 2.6 Add repo tests for save/load/delete round-trip and audit-since query

## 3. Change Classification (Service.HintRebase)

- [x] 3.1 Create `Service.HintRebase` module with `ChangeCategory` type (Irrelevant, Compatible, Conflicting, Structural)
- [x] 3.2 Implement `classifyChange` function: given a `CommandMeta` and `[Hint]`, return `ChangeCategory`
- [x] 3.3 Implement conflict detection rules (GrantSkill vs revoke-skill, WaiveOvertime vs set-overtime off, OverridePreference vs set-prefs, CloseStation/PinAssignment vs station/worker mutations, skill implication vs GrantSkill)
- [x] 3.4 Implement `rebaseSession` function: given audit entries and hints, return classified results and recommended action
- [x] 3.5 Add unit tests for each classification category and conflict rule

## 4. CLI Integration — Auto-save

- [x] 4.1 Wire auto-save into hint add/revert/revert-all handlers: after modifying hint list, call `repoSaveHintSession` with current checkpoint
- [x] 4.2 Wire auto-save into `what-if apply`: after persisting the real mutation, update checkpoint to include the new audit entry
- [x] 4.3 Change draft mutation handler: mark session stale (update checkpoint) instead of destroying it, display stale message

## 5. CLI Integration — Resume and Rebase

- [x] 5.1 Add hint session resume check on draft open: load persisted session, offer to resume or discard
- [x] 5.2 On resume, check for audit entries since checkpoint; if none, rebuild session directly
- [x] 5.3 On resume with mutations, trigger rebase flow (auto-integrate or prompt)
- [x] 5.4 Implement `what-if rebase` command: classify changes, display conflicts, prompt for action (drop/keep/abort)
- [x] 5.5 Implement large-gap detection (>50 mutations): skip classification, prompt discard/force
- [x] 5.6 Add automatic rebase trigger when hint operation is attempted on a stale session

## 6. CLI Integration — Cleanup

- [x] 6.1 Delete persisted hint session on `draft commit`
- [x] 6.2 Delete persisted hint session on `draft discard`
- [x] 6.3 Add `what-if rebase` to command parser and help text

## 7. End-to-End Tests

- [x] 7.1 Test: add hints, exit CLI, re-enter, resume session — hints are preserved
- [x] 7.2 Test: add hints, make a mutation, rebase with compatible change — hints preserved
- [x] 7.3 Test: add hints, make a conflicting mutation, rebase — conflict detected and resolvable
- [x] 7.4 Test: draft commit/discard cleans up persisted hint session
