module Domain.Transaction
    ( -- * Transaction types
      ScheduleOp(..)
    , Transaction
    , applyOp
    , applyTransaction
      -- * Compound operations (as transactions)
    , reassignOps
    , swapOps
    , coverOps
    , rotateOps
      -- * Convenience: apply compound operations directly
    , reassign
    , swap
    , cover
    , rotate
      -- * Tests
    , spec
    ) where

import qualified Data.Set as Set
import Test.Hspec
import Test.QuickCheck hiding (cover)

import Domain.Types
import Domain.Schedule (assign, unassign, byWorkerSlot)

-- ---------------------------------------------------------------------
-- Transaction types
-- ---------------------------------------------------------------------

-- | A primitive schedule operation.
data ScheduleOp
    = Assign Assignment
    | Unassign Assignment
    deriving (Eq, Ord, Show, Read)

-- | A transaction is a sequence of operations applied atomically.
-- Intermediate states are not validated; only the final result is.
type Transaction = [ScheduleOp]

-- | Apply a single operation.
applyOp :: ScheduleOp -> Schedule -> Schedule
applyOp (Assign a)   = assign a
applyOp (Unassign a) = unassign a

-- | Apply a transaction: fold all operations left-to-right.
--
-- Law (equivalence):
--   applyTransaction [op1, op2, ..., opN] s
--     = applyOp opN (... (applyOp op2 (applyOp op1 s)) ...)
--
-- Validation is the caller's responsibility and checks only the result.
applyTransaction :: Transaction -> Schedule -> Schedule
applyTransaction ops s = foldl (flip applyOp) s ops

-- ---------------------------------------------------------------------
-- Compound operations as transactions
-- ---------------------------------------------------------------------

-- | Transaction that reassigns a worker from one station to another at a slot.
--
-- Law (decomposition):
--   reassign w s1 s2 t sched = assign (w,s2,t) (unassign (w,s1,t) sched)
reassignOps :: WorkerId -> StationId -> StationId -> Slot -> Transaction
reassignOps w from to t =
    [ Unassign (Assignment w from t)
    , Assign   (Assignment w to t)
    ]

-- | Transaction that swaps two workers' stations at a slot.
--
-- Laws:
--   swap w1 w2 t (swap w1 w2 t s) = s  (involution)
--   swap w1 w2 t s = swap w2 w1 t s     (symmetry)
--
-- Requires looking up current stations from the schedule.
-- Returns empty transaction if either worker lacks exactly one
-- assignment at the slot.
swapOps :: WorkerId -> WorkerId -> Slot -> Schedule -> Transaction
swapOps w1 w2 t sched =
    let a1s = Set.toList $ byWorkerSlot w1 t sched
        a2s = Set.toList $ byWorkerSlot w2 t sched
    in case (a1s, a2s) of
        ([a1], [a2]) ->
            let s1 = assignStation a1
                s2 = assignStation a2
            in [ Unassign (Assignment w1 s1 t)
               , Unassign (Assignment w2 s2 t)
               , Assign   (Assignment w1 s2 t)
               , Assign   (Assignment w2 s1 t)
               ]
        _ -> []

-- | Transaction where one worker covers another's assignment at a slot.
-- The covered worker's assignment is removed; the covering worker
-- gets the covered worker's station (and their own assignment, if any,
-- is removed).
coverOps :: WorkerId    -- ^ covering worker
         -> WorkerId    -- ^ worker being covered
         -> Slot
         -> Schedule
         -> Transaction
coverOps covering covered t sched =
    let coveredAssigns = Set.toList $ byWorkerSlot covered t sched
        coveringAssigns = Set.toList $ byWorkerSlot covering t sched
    in case coveredAssigns of
        [a] ->
            let st = assignStation a
            in map (Unassign) coveringAssigns
               ++ [ Unassign a
                  , Assign (Assignment covering st t)
                  ]
        _ -> []

-- | Transaction for cyclic rotation of workers through stations at a slot.
-- Each worker moves to the station of the next worker in the list,
-- with the last worker moving to the first worker's station.
--
-- Law:
--   Applying rotate n times to a cycle of length n returns to
--   the original schedule.
--
-- The list represents the cycle: [(w1,s1), (w2,s2), ...] means
-- w1 moves to s2, w2 moves to s3, ..., wn moves to s1.
rotateOps :: [(WorkerId, StationId)] -> Slot -> Transaction
rotateOps [] _ = []
rotateOps [_] _ = []
rotateOps cycle_@((_, firstStation) : _) t =
    let stations = map snd cycle_
        rotatedStations = drop 1 stations ++ [firstStation]
        workers = map fst cycle_
        removals  = [Unassign (Assignment w s t) | (w, s) <- cycle_]
        additions = [Assign   (Assignment w s t) | (w, s) <- zip workers rotatedStations]
    in removals ++ additions

-- ---------------------------------------------------------------------
-- Convenience: apply compound operations directly
-- ---------------------------------------------------------------------

-- | Move a worker from one station to another in a given slot.
reassign :: WorkerId -> StationId -> StationId -> Slot -> Schedule -> Schedule
reassign w from to t = applyTransaction (reassignOps w from to t)

-- | Two workers exchange stations in a given slot.
swap :: WorkerId -> WorkerId -> Slot -> Schedule -> Schedule
swap w1 w2 t sched = applyTransaction (swapOps w1 w2 t sched) sched

-- | One worker takes over another's assignment at a given slot.
cover :: WorkerId -> WorkerId -> Slot -> Schedule -> Schedule
cover covering covered t sched = applyTransaction (coverOps covering covered t sched) sched

-- | Cyclic rotation of workers through stations at a given slot.
rotate :: [(WorkerId, StationId)] -> Slot -> Schedule -> Schedule
rotate cycle_ t = applyTransaction (rotateOps cycle_ t)

-- ---------------------------------------------------------------------
-- Tests
-- ---------------------------------------------------------------------

spec :: Spec
spec = do
    describe "Transaction basics" $ do
        it "single assign" $ property $
            \a s -> applyTransaction [Assign a] s === assign a (s :: Schedule)

        it "single unassign" $ property $
            \a s -> applyTransaction [Unassign a] s === unassign a (s :: Schedule)

    describe "Reassign" $ do
        it "decomposes into unassign + assign" $ property $
            \w s1 s2 t sched ->
                reassign w s1 s2 t sched
                    === assign (Assignment w s2 t) (unassign (Assignment w s1 t) (sched :: Schedule))

        it "reassignOps applied matches reassign" $ property $
            forAll arbitrary $ \w ->
            forAll arbitrary $ \s1 ->
            forAll arbitrary $ \s2 ->
            forAll arbitrary $ \t ->
            forAll (scheduleContaining (Assignment w s1 t)) $ \sched ->
                applyTransaction (reassignOps w s1 s2 t) sched
                    === reassign w s1 s2 t sched

    describe "Swap" $ do
        it "involution: swap w1 w2 (swap w1 w2 s) = s" $ property $
            forAll scheduleWithSwappable $ \(w1, w2, _, _, t, sched) ->
                swap w1 w2 t (swap w1 w2 t sched) === sched

        it "symmetry: swap w1 w2 = swap w2 w1" $ property $
            forAll scheduleWithSwappable $ \(w1, w2, _, _, t, sched) ->
                swap w1 w2 t sched === swap w2 w1 t sched

        it "swapOps applied matches swap" $ property $
            forAll scheduleWithSwappable $ \(w1, w2, _, _, t, sched) ->
                applyTransaction (swapOps w1 w2 t sched) sched
                    === swap w1 w2 t sched
