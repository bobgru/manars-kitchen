## 1. Freeze Line Computation

- [ ] 1.1 Add `computeFreezeLine :: IO Day` function (returns yesterday) in a new `Service/FreezeLine.hs` module or within `Service/Calendar.hs`
- [ ] 1.2 Add `isFrozen :: Day -> Day -> Bool` helper that checks if a date is on or before the freeze line
- [ ] 1.3 Add `frozenDatesInRange :: Day -> Day -> Day -> [Day]` helper that returns the list of frozen dates within a given range

## 2. Session State for Unfreezes

- [ ] 2.1 Add `asUnfreezes :: IORef (Set (Day, Day))` field to `AppState` in `CLI/App.hs`
- [ ] 2.2 Update `mkAppState` to initialize the unfreezes `IORef` to an empty set
- [ ] 2.3 Add `isDateUnfrozen :: Set (Day, Day) -> Day -> Bool` helper that checks if a date falls within any unfrozen range

## 3. Unfreeze Commands

- [ ] 3.1 Add `CalendarUnfreeze` and `CalendarUnfreezeRange` and `CalendarFreezeStatus` command variants to `CLI/Commands.hs`
- [ ] 3.2 Add parser cases for `calendar unfreeze <date>` and `calendar unfreeze <start> <end>` and `calendar freeze-status` in `parseCommand`
- [ ] 3.3 Implement `handleCalendarUnfreeze` in `CLI/App.hs` — validate date, check if frozen, add to unfreezes IORef, print confirmation
- [ ] 3.4 Implement `handleCalendarFreezeStatus` in `CLI/App.hs` — compute freeze line, read unfreezes, display both

## 4. Draft Creation Freeze Check

- [ ] 4.1 Add freeze-line check to the draft creation flow — compute frozen dates in the draft's range, check against unfreezes, warn if any remain frozen
- [ ] 4.2 Implement confirmation prompt (y/N) that blocks draft creation if user declines
- [ ] 4.3 Skip freeze warning when all frozen dates in range have been explicitly unfrozen

## 5. Auto-Refreeze on Commit

- [ ] 5.1 Add freeze-line check to draft commit flow — after successful commit, check if any committed dates were on or before the freeze line
- [ ] 5.2 If historical dates were committed, clear the unfreezes IORef and display refreeze confirmation message
- [ ] 5.3 If only future dates were committed, skip the refreeze message

## 6. Help and CLI Integration

- [ ] 6.1 Add `calendar unfreeze` and `calendar freeze-status` entries to `helpRegistry` in `CLI/App.hs`
- [ ] 6.2 Add `calendar` group to `helpGroups` if not already present (may be added by Change 1)
- [ ] 6.3 Wire new command handlers into the `runRepl` dispatch in `CLI/App.hs`

## 7. Testing

- [ ] 7.1 Test freeze line computation: verify it returns yesterday for various system dates
- [ ] 7.2 Test `isFrozen` and `frozenDatesInRange` helpers with edge cases (today, yesterday, far past)
- [ ] 7.3 Test `isDateUnfrozen` against single dates and ranges in the unfreezes set
- [ ] 7.4 Test unfreeze command: single date, date range, range spanning freeze line, future date rejection, invalid date handling
- [ ] 7.5 Test draft creation freeze check: draft in future (no warning), draft in past (warning), draft spanning freeze line (partial warning), unfrozen dates bypass warning
- [ ] 7.6 Test auto-refreeze: commit with historical dates clears unfreezes, commit with only future dates leaves unfreezes unchanged
