module Domain.SchedulerConfig
    ( -- * Types
      SchedulerConfig(..)
      -- * Defaults and presets
    , defaultConfig
    , presetConfig
    , presetNames
      -- * Serialization (Map <-> Record)
    , configToMap
    , configFromMap
    , configKeys
      -- * Tests
    , spec
    ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Test.Hspec

-- | All tunable scoring weights and rule thresholds.
data SchedulerConfig = SchedulerConfig
    { cfgShiftPrefBonus     :: !Double
      -- ^ Bonus for matching a worker's preferred shift.
    , cfgWeekendPrefBonus   :: !Double
      -- ^ Bonus for "weekend" preference on Sat/Sun.
    , cfgStationPrefBase    :: !Double
      -- ^ Base score for rank-0 station preference (decreases by 1 per rank).
    , cfgCoverageMultiplier :: !Double
      -- ^ Multiplier for shift coverage ratio (0..1) in shift scoring.
    , cfgCapacityMultiplier :: !Double
      -- ^ Multiplier for remaining-capacity ratio.  Must dominate
      -- preference scores to spread load evenly.
    , cfgOverLimitPenalty   :: !Double
      -- ^ Penalty (negative) when a worker is at or over their hour limit.
    , cfgNoLimitCapacity    :: !Double
      -- ^ Capacity score for workers with no hour limit.
    , cfgVarietyBonus       :: !Double
      -- ^ Bonus for assigning a worker to a station they haven't worked recently.
    , cfgVarietyPenalty     :: !Double
      -- ^ Penalty for assigning a worker to a recently-worked station.
    , cfgMultiStationBonus  :: !Double
      -- ^ Bonus for workers already assigned at the same slot (multi-station).
    , cfgCrossTrainingBonus :: !Double
      -- ^ Bonus when pairing workers of different seniority levels at
      -- the same slot (high with low for cross-training).
    , cfgCrossTrainingGoalBonus :: !Double
      -- ^ Bonus for assigning a worker to a station that matches one
      -- of their cross-training goals (when a mentor is present).
    , cfgPairingBonus :: !Double
      -- ^ Bonus (per preferred coworker) for assigning a worker to a
      -- slot where a preferred coworker is already assigned.
    , cfgMaxDailyRegularHours :: !Double
      -- ^ Max regular hours per day (in hours, e.g. 8.0).
    , cfgMaxDailyTotalHours   :: !Double
      -- ^ Max total hours per day including overtime (in hours).
    , cfgMaxConsecutiveHours  :: !Double
      -- ^ Max consecutive hours before mandatory break.
    , cfgMinRestHours         :: !Double
      -- ^ Min rest hours between end of one day and start of next.
      -- Optimization parameters
    , cfgOptEnabled           :: !Double
      -- ^ 1.0 = optimization enabled, 0.0 = greedy only (default).
    , cfgOptTimeLimitSecs     :: !Double
      -- ^ Maximum wall-clock seconds for the optimization loop.
    , cfgOptRandomness        :: !Double
      -- ^ Perturbation magnitude (0.0 = deterministic, 1.0 = max noise).
    , cfgOptProgressIntervalSecs :: !Double
      -- ^ Seconds between progress reports (0.0 = no progress output).
    , cfgGreedyStrategy          :: !Double
      -- ^ Greedy fill strategy: 0=bottleneck-first (default),
      --   1=chronological, 2=reverse-chronological,
      --   3=random-shuffle, 4=worker-first.
    } deriving (Eq, Show, Read)

-- | Current hardcoded values — the "balanced" preset.
defaultConfig :: SchedulerConfig
defaultConfig = SchedulerConfig
    { cfgShiftPrefBonus       = 12.0
    , cfgWeekendPrefBonus     = 8.0
    , cfgStationPrefBase      = 10.0
    , cfgCoverageMultiplier   = 15.0
    , cfgCapacityMultiplier   = 100.0
    , cfgOverLimitPenalty     = -100.0
    , cfgNoLimitCapacity      = 5.0
    , cfgVarietyBonus         = 3.0
    , cfgVarietyPenalty       = -3.0
    , cfgMultiStationBonus    = 8.0
    , cfgCrossTrainingBonus     = 6.0
    , cfgCrossTrainingGoalBonus = 8.0
    , cfgPairingBonus          = 5.0
    , cfgMaxDailyRegularHours  = 8.0
    , cfgMaxDailyTotalHours   = 16.0
    , cfgMaxConsecutiveHours  = 4.0
    , cfgMinRestHours         = 8.0
    , cfgOptEnabled           = 0.0
    , cfgOptTimeLimitSecs     = 30.0
    , cfgOptRandomness        = 0.3
    , cfgOptProgressIntervalSecs = 5.0
    , cfgGreedyStrategy          = 0.0
    }

-- | Named presets.
presetConfig :: String -> Maybe SchedulerConfig
presetConfig "balanced"         = Just defaultConfig
presetConfig "preference-first" = Just defaultConfig
    { cfgCapacityMultiplier = 25.0
    , cfgOverLimitPenalty   = -50.0
    , cfgShiftPrefBonus     = 20.0
    , cfgStationPrefBase    = 15.0
    }
presetConfig "capacity-first"   = Just defaultConfig
    { cfgCapacityMultiplier = 200.0
    , cfgOverLimitPenalty   = -200.0
    , cfgShiftPrefBonus     = 6.0
    , cfgStationPrefBase    = 5.0
    }
presetConfig _ = Nothing

-- | All available preset names.
presetNames :: [String]
presetNames = ["balanced", "preference-first", "capacity-first"]

-- | Table-driven key list: (key name, getter, setter).
-- Adding a new parameter = one record field + one entry here.
configKeys :: [(String, SchedulerConfig -> Double, Double -> SchedulerConfig -> SchedulerConfig)]
configKeys =
    [ ("shift-pref-bonus",       cfgShiftPrefBonus,       \v c -> c { cfgShiftPrefBonus = v })
    , ("weekend-pref-bonus",     cfgWeekendPrefBonus,     \v c -> c { cfgWeekendPrefBonus = v })
    , ("station-pref-base",      cfgStationPrefBase,      \v c -> c { cfgStationPrefBase = v })
    , ("coverage-multiplier",    cfgCoverageMultiplier,   \v c -> c { cfgCoverageMultiplier = v })
    , ("capacity-multiplier",    cfgCapacityMultiplier,   \v c -> c { cfgCapacityMultiplier = v })
    , ("over-limit-penalty",     cfgOverLimitPenalty,     \v c -> c { cfgOverLimitPenalty = v })
    , ("no-limit-capacity",      cfgNoLimitCapacity,      \v c -> c { cfgNoLimitCapacity = v })
    , ("variety-bonus",          cfgVarietyBonus,         \v c -> c { cfgVarietyBonus = v })
    , ("variety-penalty",        cfgVarietyPenalty,       \v c -> c { cfgVarietyPenalty = v })
    , ("multi-station-bonus",    cfgMultiStationBonus,    \v c -> c { cfgMultiStationBonus = v })
    , ("cross-training-bonus",   cfgCrossTrainingBonus,   \v c -> c { cfgCrossTrainingBonus = v })
    , ("cross-training-goal-bonus", cfgCrossTrainingGoalBonus, \v c -> c { cfgCrossTrainingGoalBonus = v })
    , ("pairing-bonus",           cfgPairingBonus,           \v c -> c { cfgPairingBonus = v })
    , ("max-daily-regular-hours", cfgMaxDailyRegularHours, \v c -> c { cfgMaxDailyRegularHours = v })
    , ("max-daily-total-hours",   cfgMaxDailyTotalHours,   \v c -> c { cfgMaxDailyTotalHours = v })
    , ("max-consecutive-hours",   cfgMaxConsecutiveHours,   \v c -> c { cfgMaxConsecutiveHours = v })
    , ("min-rest-hours",          cfgMinRestHours,          \v c -> c { cfgMinRestHours = v })
    , ("opt-enabled",             cfgOptEnabled,            \v c -> c { cfgOptEnabled = v })
    , ("opt-time-limit-secs",    cfgOptTimeLimitSecs,      \v c -> c { cfgOptTimeLimitSecs = v })
    , ("opt-randomness",          cfgOptRandomness,          \v c -> c { cfgOptRandomness = v })
    , ("opt-progress-interval",   cfgOptProgressIntervalSecs, \v c -> c { cfgOptProgressIntervalSecs = v })
    , ("greedy-strategy",         cfgGreedyStrategy,          \v c -> c { cfgGreedyStrategy = v })
    ]

-- | Convert a config record to a key-value map.
configToMap :: SchedulerConfig -> Map String Double
configToMap cfg = Map.fromList [(k, getter cfg) | (k, getter, _) <- configKeys]

-- | Reconstruct a config from a key-value map, falling back to 'defaultConfig'
-- for any missing keys.
configFromMap :: Map String Double -> SchedulerConfig
configFromMap m = foldl applyKey defaultConfig configKeys
  where
    applyKey cfg (k, _, setter) = case Map.lookup k m of
        Just v  -> setter v cfg
        Nothing -> cfg

-- ---------------------------------------------------------------------
-- Tests
-- ---------------------------------------------------------------------

spec :: Spec
spec = do
    describe "configToMap / configFromMap" $ do
        it "round-trips defaultConfig" $ do
            configFromMap (configToMap defaultConfig) `shouldBe` defaultConfig

        it "round-trips a modified config" $ do
            let cfg = defaultConfig { cfgCapacityMultiplier = 42.0 }
            configFromMap (configToMap cfg) `shouldBe` cfg

        it "missing keys fall back to defaults" $ do
            configFromMap Map.empty `shouldBe` defaultConfig

        it "extra keys are ignored" $ do
            let m = Map.insert "unknown-key" 999.0 (configToMap defaultConfig)
            configFromMap m `shouldBe` defaultConfig

        it "partial map applies present keys, defaults for rest" $ do
            let m = Map.fromList [("capacity-multiplier", 50.0)]
                cfg = configFromMap m
            cfgCapacityMultiplier cfg `shouldBe` 50.0
            cfgShiftPrefBonus cfg `shouldBe` cfgShiftPrefBonus defaultConfig

    describe "presets" $ do
        it "balanced is defaultConfig" $ do
            presetConfig "balanced" `shouldBe` Just defaultConfig

        it "all named presets resolve" $ do
            mapM_ (\name -> presetConfig name `shouldSatisfy` (/= Nothing)) presetNames

        it "unknown preset returns Nothing" $ do
            presetConfig "nonexistent" `shouldBe` Nothing

        it "capacity-first has higher capacity multiplier than balanced" $ do
            case presetConfig "capacity-first" of
                Just cap -> cfgCapacityMultiplier cap `shouldSatisfy` (> cfgCapacityMultiplier defaultConfig)
                Nothing -> expectationFailure "preset not found"

        it "preference-first has higher shift pref than balanced" $ do
            case presetConfig "preference-first" of
                Just pref -> cfgShiftPrefBonus pref `shouldSatisfy` (> cfgShiftPrefBonus defaultConfig)
                Nothing -> expectationFailure "preset not found"

    describe "configKeys completeness" $ do
        it "covers all 22 parameters" $ do
            length configKeys `shouldBe` 22

        it "all keys are unique" $ do
            let keys = [k | (k, _, _) <- configKeys]
            length keys `shouldBe` length (Map.fromList (zip keys keys))
