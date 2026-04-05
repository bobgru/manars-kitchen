module Service.Config
    ( loadConfig
    , saveConfig
    , applyPreset
    , setConfigParam
    , listConfigParams
    ) where

import Domain.SchedulerConfig
    ( SchedulerConfig, configToMap, configKeys
    , presetConfig
    )
import qualified Data.Map.Strict as Map
import Repo.Types (Repository(..))

-- | Load the current scheduler config (falls back to defaults for missing keys).
loadConfig :: Repository -> IO SchedulerConfig
loadConfig = repoLoadSchedulerConfig

-- | Save a complete scheduler config.
saveConfig :: Repository -> SchedulerConfig -> IO ()
saveConfig = repoSaveSchedulerConfig

-- | Apply a named preset, overwriting all config values.
-- Returns Nothing if the preset name is unknown.
applyPreset :: Repository -> String -> IO (Maybe SchedulerConfig)
applyPreset repo name = case presetConfig name of
    Nothing  -> return Nothing
    Just cfg -> do
        repoSaveSchedulerConfig repo cfg
        return (Just cfg)

-- | Set a single config parameter by key name.
-- Returns Nothing if the key is unknown.
setConfigParam :: Repository -> String -> Double -> IO (Maybe SchedulerConfig)
setConfigParam repo key val = do
    case lookup key [(k, setter) | (k, _, setter) <- configKeys] of
        Nothing -> return Nothing
        Just setter -> do
            cfg <- repoLoadSchedulerConfig repo
            let cfg' = setter val cfg
            repoSaveSchedulerConfig repo cfg'
            return (Just cfg')

-- | List all config parameters as (key, current value) pairs.
listConfigParams :: Repository -> IO [(String, Double)]
listConfigParams repo = do
    cfg <- repoLoadSchedulerConfig repo
    return $ Map.toList (configToMap cfg)
