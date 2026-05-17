## ADDED Requirements

### Requirement: Worker management CLI verbs take a worker name
All `worker <verb> <name> ...` CLI commands SHALL accept a worker name (= `users.username`) as the primary argument. The verbs covered:
`grant-skill`, `revoke-skill`, `set-hours`, `set-overtime`, `set-prefs`, `set-shift-pref`, `set-variety`, `set-weekend-only`, `set-status`, `set-overtime-model`, `set-pay-tracking`, `set-temp`, `set-seniority`, `set-cross-training`, `clear-cross-training`, `avoid-pairing`, `clear-avoid-pairing`, `prefer-pairing`, `clear-prefer-pairing`.

Numeric strings SHALL continue to be accepted for compatibility (the resolver passes them through). For non-numeric strings, the system SHALL resolve the name against `users.username`. Both active and inactive workers SHALL be resolvable. Non-worker users (`worker_status = 'none'`) SHALL produce a "not a worker" error. Unknown names SHALL produce a "not found" error.

#### Scenario: grant-skill by worker name and skill name
- **WHEN** an admin runs `worker grant-skill alice grill`
- **THEN** the system resolves `alice` to her `WorkerId` and `grill` to a `SkillId`, and grants the skill

#### Scenario: revoke-skill by worker name
- **WHEN** an admin runs `worker revoke-skill alice grill`
- **THEN** the skill is revoked

#### Scenario: set-hours by worker name
- **WHEN** an admin runs `worker set-hours alice 40`
- **THEN** alice's max-period hours are set to 40

#### Scenario: set-prefs by worker name with station names
- **WHEN** an admin runs `worker set-prefs alice grill prep`
- **THEN** the system resolves `alice`, `grill`, `prep` to their ids and stores the preference list

#### Scenario: pairing verbs by names
- **WHEN** an admin runs `worker avoid-pairing alice bob`
- **THEN** the system resolves both names and stores the symmetric avoid-pairing relationship

#### Scenario: cross-training by name
- **WHEN** an admin runs `worker set-cross-training alice grill`
- **THEN** the system resolves `alice` to her WorkerId and `grill` to a SkillId, and adds the cross-training goal

#### Scenario: numeric worker arg still works
- **WHEN** an admin runs `worker set-hours 2 40`
- **THEN** the system interprets `2` as a numeric WorkerId and proceeds (existing behavior preserved)

#### Scenario: unknown worker name
- **WHEN** an admin runs `worker set-hours ghost 40` and no user named `ghost` exists
- **THEN** the system prints a not-found error and makes no change

#### Scenario: name resolves to a non-worker user
- **WHEN** an admin runs `worker set-hours admin-only 40` and `admin-only` is a user with `worker_status = 'none'`
- **THEN** the system prints a "not a worker" error and makes no change

#### Scenario: inactive worker resolves
- **WHEN** an admin runs `worker set-hours alice 40` and alice's status is `inactive`
- **THEN** the system resolves alice to her WorkerId and updates her hours; she remains inactive (config preserved for future reactivation)
