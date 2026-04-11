module Service.FreezeLine
    ( computeFreezeLine
    , isFrozen
    , frozenDatesInRange
    , isDateUnfrozen
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
