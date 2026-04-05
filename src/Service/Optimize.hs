{-# LANGUAGE BangPatterns #-}
module Service.Optimize
    ( optimizeSchedule
    ) where

import Control.Monad (when)
import Data.IORef
import Data.Time.Clock (UTCTime, getCurrentTime, diffUTCTime)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import System.Random (StdGen, newStdGen, randoms, split)

import Data.List (minimumBy)
import Data.Ord (comparing)

import Domain.Types (Schedule(..))
import Domain.Scheduler
    ( SchedulerContext(..), ScheduleResult(..), Unfilled(..), UnfilledKind(..)
    , GreedyStrategy(..), allStrategies
    , buildScheduleFrom
    )
import Domain.SchedulerConfig (SchedulerConfig(..))
import Domain.Optimizer
    ( OptProgress(..), OptPhase(..)
    , scoreSchedule
    , iteratedGreedyStep
    , hillClimbStep
    )

-- | Run the optimization loop over a schedule.
--
-- If optimization is disabled (@cfgOptEnabled <= 0.0@), runs the greedy
-- algorithm once and returns immediately.
--
-- Otherwise:
--   Phase 1 (hard constraints): iterated greedy with neighborhood
--   destruction and perturbed rebuilding until all positions are filled
--   or the time limit is reached.
--
--   Phase 2 (soft constraints): hill climbing with random swaps to
--   improve the total soft score while maintaining feasibility.
optimizeSchedule :: SchedulerContext
                 -> Schedule          -- ^ Seed (pinned assignments)
                 -> (OptProgress -> IO ())  -- ^ Progress callback
                 -> IO ScheduleResult
optimizeSchedule ctx seed reportProgress = do
    let cfg = schConfig ctx
    if cfgOptEnabled cfg <= 0.0
        then return (buildScheduleFrom seed ctx)
        else do
            gen <- newStdGen
            startTime <- getCurrentTime
            lastReport <- newIORef startTime
            -- Try all 5 strategies; pick the best starting point
            let !initialResult = bestOfStrategies ctx seed
                timeLimit = cfgOptTimeLimitSecs cfg
                randomness = cfgOptRandomness cfg
                progressInterval = cfgOptProgressIntervalSecs cfg
            -- Phase 1: satisfy hard constraints
            (bestResult, gen', iter1) <-
                hardPhase seed ctx initialResult gen startTime lastReport
                          timeLimit randomness progressInterval
                          reportProgress 0
            -- Phase 2: optimize soft constraints (only if hard constraints met)
            let !trulyUnfilled = countTrulyUnfilled (srUnfilled bestResult)
            if trulyUnfilled > 0
                then return bestResult
                else do
                    let !score0 = scoreSchedule ctx (srSchedule bestResult)
                    softPhase ctx bestResult score0 gen' startTime lastReport
                              timeLimit progressInterval reportProgress iter1

-- | Phase 1: Iterated greedy to satisfy hard constraints.
hardPhase :: Schedule -> SchedulerContext -> ScheduleResult -> StdGen
          -> UTCTime -> IORef UTCTime -> Double -> Double -> Double
          -> (OptProgress -> IO ()) -> Int
          -> IO (ScheduleResult, StdGen, Int)
hardPhase seed ctx !bestResult !gen startTime lastReport timeLimit randomness
          progressInterval reportProgress !iteration = do
    now <- getCurrentTime
    let !elapsed = realToFrac (diffUTCTime now startTime) :: Double
    if elapsed >= timeLimit
        then return (bestResult, gen, iteration)
        else do
            let !bestUnfilled = countTrulyUnfilled (srUnfilled bestResult)
            if bestUnfilled == 0
                then return (bestResult, gen, iteration)
                else do
                    let (!gen1, !gen2) = split gen
                        (!gen3, !gen4) = split gen2
                        (!gen5, !gen6) = split gen4
                        destroyRs = randoms gen1 :: [Double]
                        perturbRs = randoms gen3 :: [Double]
                        -- Pick a random strategy for this iteration
                        strategyRs = randoms gen5 :: [Double]
                        !iterStrategy = case strategyRs of
                            (r:_) -> toEnum (floor (r * 5.0) `mod` 5)
                            []    -> BottleneckFirst  -- unreachable: randoms is infinite
                        -- Deep-force the result so that thunks referencing
                        -- the infinite destroyRs/perturbRs streams and the
                        -- previous iteration's schedule are not retained.
                        !newResult = forceResult $ iteratedGreedyStep seed ctx
                                         bestResult randomness destroyRs perturbRs
                                         iterStrategy
                        !newUnfilled = countTrulyUnfilled (srUnfilled newResult)
                        !best' = if newUnfilled < bestUnfilled
                                 then newResult
                                 else bestResult
                        !iter' = iteration + 1
                    -- Report progress at wall-clock intervals
                    maybeReport lastReport now progressInterval $ do
                        let !elapsed' = realToFrac (diffUTCTime now startTime) :: Double
                        reportProgress OptProgress
                            { opIteration = iter'
                            , opBestUnfilled = min bestUnfilled newUnfilled
                            , opBestScore = 0.0
                            , opElapsedSecs = elapsed'
                            , opPhase = PhaseHard
                            }
                    -- Pass gen6 (not gen4) so gen5's strategy randoms
                    -- are not reused in subsequent iterations.
                    hardPhase seed ctx best' gen6 startTime lastReport timeLimit
                              randomness progressInterval reportProgress iter'

-- | Phase 2: Hill climbing to improve soft constraints.
softPhase :: SchedulerContext -> ScheduleResult -> Double -> StdGen
          -> UTCTime -> IORef UTCTime -> Double -> Double
          -> (OptProgress -> IO ()) -> Int
          -> IO ScheduleResult
softPhase ctx !bestResult !bestScore !gen startTime lastReport timeLimit
          progressInterval reportProgress !iteration = do
    now <- getCurrentTime
    let !elapsed = realToFrac (diffUTCTime now startTime) :: Double
    if elapsed >= timeLimit
        then return bestResult
        else do
            let (!gen1, !gen2) = split gen
                rs = randoms gen1 :: [Double]
                currentSched = srSchedule bestResult
                -- hillClimbStep returns strict (schedule, score) thanks
                -- to BangPatterns; forceResult deep-forces the schedule
                -- so thunks from trySwap/assign chains are not retained.
                (!newSched, !newScore) = hillClimbStep ctx currentSched bestScore rs
                !improved = newScore > bestScore
                !best' = if improved
                         then forceResult (bestResult { srSchedule = newSched })
                         else bestResult
                !score' = max bestScore newScore
                !iter' = iteration + 1
            maybeReport lastReport now progressInterval $ do
                let !elapsed' = realToFrac (diffUTCTime now startTime) :: Double
                reportProgress OptProgress
                    { opIteration = iter'
                    , opBestUnfilled = length (srUnfilled bestResult)
                    , opBestScore = score'
                    , opElapsedSecs = elapsed'
                    , opPhase = PhaseSoft
                    }
            softPhase ctx best' score' gen2 startTime lastReport timeLimit
                      progressInterval reportProgress iter'

-- | Try all greedy strategies and pick the best starting point.
-- "Best" = fewest truly-unfilled positions; ties broken by soft score.
bestOfStrategies :: SchedulerContext -> Schedule -> ScheduleResult
bestOfStrategies ctx seed =
    let results = [ let cfg' = (schConfig ctx)
                              { cfgGreedyStrategy = fromIntegral (fromEnum s) }
                        ctx' = ctx { schConfig = cfg' }
                    in buildScheduleFrom seed ctx'
                  | s <- allStrategies
                  ]
        -- Compare by (fewest unfilled, highest soft score)
        rank r = ( countTrulyUnfilled (srUnfilled r)
                 , negate (scoreSchedule ctx (srSchedule r))
                 )
    in minimumBy (comparing rank) results

-- Helpers

countTrulyUnfilled :: [Unfilled] -> Int
countTrulyUnfilled = length . filter (\u -> unfilledKind u == TrulyUnfilled)

-- | Report progress only if enough wall-clock time has elapsed since the
-- last report. This avoids flooding the output with per-iteration reports.
maybeReport :: IORef UTCTime -> UTCTime -> Double -> IO () -> IO ()
maybeReport lastRef now interval action
    | interval <= 0 = return ()
    | otherwise = do
        lastTime <- readIORef lastRef
        let sinceLast = realToFrac (diffUTCTime now lastTime) :: Double
        when (sinceLast >= interval) $ do
            writeIORef lastRef now
            action

-- | Deep-force a ScheduleResult to prevent thunk buildup across
-- optimization iterations.  We traverse each container so that no
-- thunks from previous iterations (perturbation streams, intermediate
-- Set/Map operations, lazy (++) chains) remain reachable.
forceResult :: ScheduleResult -> ScheduleResult
forceResult (ScheduleResult sched@(Schedule s) u o) =
    -- Force every Assignment in the Set (strict fields → WHNF suffices)
    Set.foldl' (\_ !_ -> ()) () s `seq`
    -- Force every Unfilled in the list (strict fields → WHNF suffices)
    foldl' (\_ !_ -> ()) () u `seq`
    -- Force every entry in the overtime Map
    Map.foldl' (\_ !_ -> ()) () o `seq`
    ScheduleResult sched u o
