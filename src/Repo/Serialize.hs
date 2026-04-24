{-# LANGUAGE OverloadedStrings #-}
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

import Data.Text (Text, pack, unpack)
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

roleToText :: Role -> Text
roleToText Admin  = "admin"
roleToText Normal = "normal"

textToRole :: Text -> Role
textToRole "admin" = Admin
textToRole _       = Normal

-- -----------------------------------------------------------------
-- AbsenceStatus
-- -----------------------------------------------------------------

statusToText :: AbsenceStatus -> Text
statusToText Pending  = "pending"
statusToText Approved = "approved"
statusToText Rejected = "rejected"

textToStatus :: Text -> AbsenceStatus
textToStatus "approved" = Approved
textToStatus "rejected" = Rejected
textToStatus _          = Pending

-- -----------------------------------------------------------------
-- Time conversions
-- -----------------------------------------------------------------

dayToText :: Day -> Text
dayToText = pack . formatTime defaultTimeLocale "%Y-%m-%d"

textToDay :: Text -> Day
textToDay t = case parseTimeM True defaultTimeLocale "%Y-%m-%d" (unpack t) of
    Just d  -> d
    Nothing -> error $ "Repo.Serialize.textToDay: invalid date: " ++ unpack t

todToText :: TimeOfDay -> Text
todToText = pack . formatTime defaultTimeLocale "%H:%M:%S"

textToTod :: Text -> TimeOfDay
textToTod t = case parseTimeM True defaultTimeLocale "%H:%M:%S" (unpack t) of
    Just tt -> tt
    Nothing -> error $ "Repo.Serialize.textToTod: invalid time: " ++ unpack t

diffTimeToSeconds :: DiffTime -> Int
diffTimeToSeconds = round . toRational

secondsToDiffTime :: Int -> DiffTime
secondsToDiffTime = fromIntegral
