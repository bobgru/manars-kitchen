module Service.FreezeLine
    ( computeFreezeLine
    , isFrozen
    , frozenDatesInRange
    , isDateUnfrozen
    , frozenRangeFor
    ) where

import Data.Time (Day, addDays)
import Data.Time.Clock (getCurrentTime, utctDay)
import qualified Data.Set as Set

-- | The freeze line is yesterday: dates on or before are frozen.
computeFreezeLine :: IO Day
computeFreezeLine = do
    today <- utctDay <$> getCurrentTime
    return (addDays (-1) today)

-- | A date is frozen if it is on or before the freeze line.
isFrozen :: Day -> Day -> Bool
isFrozen freezeLine date = date <= freezeLine

-- | Return the list of frozen dates within an inclusive range.
frozenDatesInRange :: Day -> Day -> Day -> [Day]
frozenDatesInRange freezeLine start end =
    [ d | d <- enumDays start end, isFrozen freezeLine d ]
  where
    enumDays s e
        | s > e     = []
        | otherwise = s : enumDays (addDays 1 s) e

-- | Check if a date falls within any unfrozen range in the set.
isDateUnfrozen :: Set.Set (Day, Day) -> Day -> Bool
isDateUnfrozen unfreezes date =
    any (\(s, e) -> date >= s && date <= e) (Set.toList unfreezes)

-- | The still-frozen sub-range of @start@..@end@, given a freeze line and the
-- set of temporarily unfrozen ranges. 'Nothing' when the range touches no
-- frozen date, or when every frozen date it touches has been unfrozen.
--
-- The result is the first and last still-frozen date, so it can be reported
-- without listing every date in between. Frozen dates are contiguous from
-- @start@ in practice — the freeze line is a single cut-off — but an unfreeze
-- may punch a hole in the middle, in which case the reported range spans the
-- hole.
frozenRangeFor :: Day -> Set.Set (Day, Day) -> Day -> Day -> Maybe (Day, Day)
frozenRangeFor freezeLine unfreezes start end =
    case filter (not . isDateUnfrozen unfreezes) (frozenDatesInRange freezeLine start end) of
        []       -> Nothing
        (d : ds) -> Just (d, last (d : ds))
