module Repo.Serialize
    ( -- * Role
      roleToText
    , textToRole
      -- * AbsenceStatus
    , statusToText
    , textToStatus
      -- * Day / TimeOfDay / DiffTime
    , dayToText
    , textToDay
    , todToText
    , textToTod
    , diffTimeToSeconds
    , secondsToDiffTime
    ) where

import Data.Time
    ( Day, TimeOfDay(..)
    , DiffTime
    , parseTimeM, defaultTimeLocale, formatTime
    )

import Auth.Types (Role(..))
import Domain.Absence (AbsenceStatus(..))

-- -----------------------------------------------------------------
-- Role
-- -----------------------------------------------------------------

roleToText :: Role -> String
roleToText Admin  = "admin"
roleToText Normal = "normal"

textToRole :: String -> Role
textToRole "admin" = Admin
textToRole _       = Normal

-- -----------------------------------------------------------------
-- AbsenceStatus
-- -----------------------------------------------------------------

statusToText :: AbsenceStatus -> String
statusToText Pending  = "pending"
statusToText Approved = "approved"
statusToText Rejected = "rejected"

textToStatus :: String -> AbsenceStatus
textToStatus "approved" = Approved
textToStatus "rejected" = Rejected
textToStatus _          = Pending

-- -----------------------------------------------------------------
-- Time conversions
-- -----------------------------------------------------------------

dayToText :: Day -> String
dayToText = formatTime defaultTimeLocale "%Y-%m-%d"

textToDay :: String -> Day
textToDay s = case parseTimeM True defaultTimeLocale "%Y-%m-%d" s of
    Just d  -> d
    Nothing -> error $ "Repo.Serialize.textToDay: invalid date: " ++ s

todToText :: TimeOfDay -> String
todToText = formatTime defaultTimeLocale "%H:%M:%S"

textToTod :: String -> TimeOfDay
textToTod s = case parseTimeM True defaultTimeLocale "%H:%M:%S" s of
    Just t  -> t
    Nothing -> error $ "Repo.Serialize.textToTod: invalid time: " ++ s

diffTimeToSeconds :: DiffTime -> Int
diffTimeToSeconds = round . toRational

secondsToDiffTime :: Int -> DiffTime
secondsToDiffTime = fromIntegral
