## REMOVED Requirements

### Requirement: Compact schedule view command
**Reason**: `schedule view-compact <name>` is removed with the named-schedule
surface. The compact 100-column renderer itself survives and is still required by
`calendar view-compact` (see `calendar-cli`) and `draft view-compact` (see
`draft-session`), so this capability's only remaining content was the deleted
command.

**Migration**: Use `draft view-compact <id>` for a draft or
`calendar view-compact <start> <end>` for committed dates.
