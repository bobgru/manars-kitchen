## REMOVED Requirements

### Requirement: schedule assign and unassign take worker and station names
**Reason**: The `assign` and `unassign` commands are removed with the
named-schedule surface. There is no per-slot assignment command any more; slot-level
experimentation goes through what-ifs and slot-level persistence goes through
`draft generate` and `draft commit`.

**Migration**: None. A future manual per-slot editor would route through what-ifs
(ADR 0001), not through a resurrected `assign`.
