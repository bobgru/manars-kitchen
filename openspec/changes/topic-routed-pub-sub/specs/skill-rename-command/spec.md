# skill-rename-command Specification

## Purpose
Wire the existing `repoRenameSkill` repository function to a CLI command, RPC handler, and command classifier entry. Provides an explicit rename operation so that `skill create` can safely reject duplicates without losing the ability to rename.

## Requirements

### Requirement: CLI skill rename command
The system SHALL support `skill rename <id> <new-name>` as a CLI command.

#### Scenario: Successful rename
- **WHEN** user enters `skill rename 4 sauté`
- **AND** skill 4 exists
- **THEN** the skill's name is updated to "sauté"
- **AND** the output confirms the rename: `Renamed skill 4 to "sauté"`

#### Scenario: Rename nonexistent skill
- **WHEN** user enters `skill rename 99 newname`
- **AND** no skill with ID 99 exists
- **THEN** the command fails with an error message indicating skill 99 does not exist

### Requirement: Command type constructor
The `Command` type SHALL include a `SkillRename Int String` constructor.

#### Scenario: Parse skill rename
- **WHEN** `parseCommand "skill rename 4 sauté"` is called
- **THEN** it returns `SkillRename 4 "sauté"`

### Requirement: Classify skill rename
The `classify` function SHALL recognize `"skill rename"` commands.

#### Scenario: Classification
- **WHEN** `classify "skill rename 4 sauté"` is called
- **THEN** it returns CommandMeta with entityType="skill", operation="rename", entityId=4, isMutation=True

### Requirement: Skill rename is mutating
`isMutating (SkillRename _ _)` SHALL return True.

#### Scenario: Mutation check
- **WHEN** `isMutating` is called with `SkillRename 4 "sauté"`
- **THEN** it returns True

### Requirement: RPC skill rename handler
The RPC layer SHALL support skill rename, publishing a `CommandEvent` to `busCommands`.

#### Scenario: RPC rename
- **WHEN** the RPC skill rename endpoint is called with ID 4 and name "sauté"
- **THEN** the skill is renamed
- **AND** a `CommandEvent` is published with topic `"skill.rename.4"` and ceCommand containing `"skill rename 4 sauté"`

### Requirement: Admin-only
Skill rename SHALL require admin role, consistent with other skill mutations.

#### Scenario: Non-admin rejected
- **WHEN** a non-admin user attempts `skill rename 4 newname`
- **THEN** the command is rejected with a permission error
