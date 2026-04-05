module Domain.Absence
    ( -- * Types
      AbsenceType(..)
    , AbsenceStatus(..)
    , AbsenceRequest(..)
    , AbsenceContext(..)
    , emptyAbsenceContext
      -- * Request lifecycle
    , requestAbsence
    , approveAbsence
    , approveAbsenceOverride
    , rejectAbsence
      -- * Queries
    , approvedAbsences
    , absenceDaysInYear
    , absenceHoursInYear
    , vacationDaysRemaining
    , workerAbsencesInRange
    , isWorkerAvailable
    , unavailableDays
      -- * Tests
    , spec
    ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Time (Day, addDays, toGregorian, fromGregorian, diffDays)
import Test.Hspec

import Domain.Types

-- ---------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------

-- | Metadata for a type of absence.
data AbsenceType = AbsenceType
    { atName         :: !String
      -- ^ Human-readable name (e.g., "Vacation", "Training").
    , atYearlyLimit  :: !Bool
      -- ^ Whether this absence type has a per-worker yearly day limit.
      -- When True, approval checks the worker's allowance in
      -- 'acYearlyAllowance'. When False, there is no automatic limit
      -- (manager decides).
    } deriving (Eq, Ord, Show, Read)

-- | The status of an absence request.
data AbsenceStatus = Pending | Approved | Rejected
    deriving (Eq, Ord, Show, Read)

-- | A request for a worker to be absent over a range of days.
-- The range is inclusive on both ends: startDay through endDay.
data AbsenceRequest = AbsenceRequest
    { arId       :: !AbsenceId
    , arWorker   :: !WorkerId
    , arType     :: !AbsenceTypeId
    , arStartDay :: !Day
    , arEndDay   :: !Day
    , arStatus   :: !AbsenceStatus
    } deriving (Eq, Ord, Show, Read)

-- | All reference data and state for absence management.
data AbsenceContext = AbsenceContext
    { acTypes          :: !(Map AbsenceTypeId AbsenceType)
      -- ^ Registered absence types and their metadata.
    , acRequests       :: !(Map AbsenceId AbsenceRequest)
      -- ^ All absence requests (pending, approved, rejected).
    , acYearlyAllowance :: !(Map (WorkerId, AbsenceTypeId) Int)
      -- ^ Per-worker, per-type yearly day allowances.
      -- Only meaningful for types where 'atYearlyLimit' is True.
    , acNextId         :: !Int
      -- ^ Next absence ID to allocate.
    } deriving (Eq, Ord, Show, Read)

emptyAbsenceContext :: AbsenceContext
emptyAbsenceContext = AbsenceContext Map.empty Map.empty Map.empty 1

-- ---------------------------------------------------------------------
-- Request lifecycle
-- ---------------------------------------------------------------------

-- | Create a new pending absence request. Returns the updated context
-- and the ID of the new request.
requestAbsence :: WorkerId -> AbsenceTypeId -> Day -> Day
               -> AbsenceContext -> (AbsenceContext, AbsenceId)
requestAbsence w atype startDay endDay ctx =
    let aid = AbsenceId (acNextId ctx)
        req = AbsenceRequest aid w atype startDay endDay Pending
        ctx' = ctx
            { acRequests = Map.insert aid req (acRequests ctx)
            , acNextId   = acNextId ctx + 1
            }
    in (ctx', aid)

-- | Approve an absence request, checking the yearly allowance for
-- capped types. Returns Nothing if:
--   - The request doesn't exist or isn't pending.
--   - The type has a yearly limit and approving would exceed it.
approveAbsence :: AbsenceId -> AbsenceContext -> Maybe AbsenceContext
approveAbsence aid ctx =
    case Map.lookup aid (acRequests ctx) of
        Nothing -> Nothing
        Just req
            | arStatus req /= Pending -> Nothing
            | exceedsAllowance ctx req -> Nothing
            | otherwise -> Just (setStatus aid Approved ctx)

-- | Approve an absence request, overriding the yearly allowance check.
-- Returns Nothing only if the request doesn't exist or isn't pending.
approveAbsenceOverride :: AbsenceId -> AbsenceContext -> Maybe AbsenceContext
approveAbsenceOverride aid ctx =
    case Map.lookup aid (acRequests ctx) of
        Nothing -> Nothing
        Just req
            | arStatus req /= Pending -> Nothing
            | otherwise -> Just (setStatus aid Approved ctx)

-- | Reject a pending absence request.
-- Returns Nothing if the request doesn't exist or isn't pending.
rejectAbsence :: AbsenceId -> AbsenceContext -> Maybe AbsenceContext
rejectAbsence aid ctx =
    case Map.lookup aid (acRequests ctx) of
        Nothing -> Nothing
        Just req
            | arStatus req /= Pending -> Nothing
            | otherwise -> Just (setStatus aid Rejected ctx)

-- | Set the status of a request.
setStatus :: AbsenceId -> AbsenceStatus -> AbsenceContext -> AbsenceContext
setStatus aid status ctx =
    ctx { acRequests = Map.adjust (\r -> r { arStatus = status }) aid (acRequests ctx) }

-- | Would approving this request exceed the worker's yearly allowance?
exceedsAllowance :: AbsenceContext -> AbsenceRequest -> Bool
exceedsAllowance ctx req =
    case Map.lookup (arType req) (acTypes ctx) of
        Nothing -> False   -- unknown type, no limit
        Just at
            | not (atYearlyLimit at) -> False
            | otherwise ->
                let allowance = Map.findWithDefault 0
                        (arWorker req, arType req) (acYearlyAllowance ctx)
                    (year, _, _) = toGregorian (arStartDay req)
                    used = absenceDaysInYear (arWorker req) (arType req) year ctx
                    requested = requestDays req
                in used + requested > allowance

-- ---------------------------------------------------------------------
-- Queries
-- ---------------------------------------------------------------------

-- | All approved absence requests for a worker.
approvedAbsences :: WorkerId -> AbsenceContext -> [AbsenceRequest]
approvedAbsences w ctx =
    filter (\r -> arWorker r == w && arStatus r == Approved)
           (Map.elems (acRequests ctx))

-- | Number of approved absence days for a worker of a given type
-- in a calendar year.
absenceDaysInYear :: WorkerId -> AbsenceTypeId -> Integer -> AbsenceContext -> Int
absenceDaysInYear w atype year ctx =
    sum [ daysInYear year r
        | r <- Map.elems (acRequests ctx)
        , arWorker r == w
        , arType r == atype
        , arStatus r == Approved
        ]

-- | Number of approved absence hours for a worker of a given type
-- in a calendar year, assuming 8-hour work days.
absenceHoursInYear :: WorkerId -> AbsenceTypeId -> Integer -> AbsenceContext -> Int
absenceHoursInYear w atype year ctx = 8 * absenceDaysInYear w atype year ctx

-- | Remaining vacation days for a worker of a given type in a year.
-- Returns Nothing if the type has no yearly limit.
vacationDaysRemaining :: WorkerId -> AbsenceTypeId -> Integer
                      -> AbsenceContext -> Maybe Int
vacationDaysRemaining w atype year ctx =
    case Map.lookup atype (acTypes ctx) of
        Nothing -> Nothing
        Just at
            | not (atYearlyLimit at) -> Nothing
            | otherwise ->
                let allowance = Map.findWithDefault 0
                        (w, atype) (acYearlyAllowance ctx)
                    used = absenceDaysInYear w atype year ctx
                in Just (allowance - used)

-- | Approved absences for a worker that overlap a given date range
-- (inclusive on both ends).
workerAbsencesInRange :: WorkerId -> Day -> Day -> AbsenceContext -> [AbsenceRequest]
workerAbsencesInRange w from to ctx =
    filter (\r -> arWorker r == w
                  && arStatus r == Approved
                  && arStartDay r <= to
                  && arEndDay r >= from)
           (Map.elems (acRequests ctx))

-- | Is a worker available (not on approved absence) on a given day?
isWorkerAvailable :: WorkerId -> Day -> AbsenceContext -> Bool
isWorkerAvailable w day ctx =
    null (workerAbsencesInRange w day day ctx)

-- | The set of days a worker is unavailable due to approved absences
-- in a given date range.
unavailableDays :: WorkerId -> Day -> Day -> AbsenceContext -> Set Day
unavailableDays w from to ctx =
    let absences = workerAbsencesInRange w from to ctx
    in Set.fromList
        [ d
        | r <- absences
        , d <- dayRange (max from (arStartDay r)) (min to (arEndDay r))
        ]

-- ---------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------

-- | The number of days in an absence request (inclusive).
requestDays :: AbsenceRequest -> Int
requestDays r = fromIntegral (diffDays (arEndDay r) (arStartDay r) + 1)

-- | Number of days from an absence request that fall within a year.
daysInYear :: Integer -> AbsenceRequest -> Int
daysInYear year r =
    let janFirst = fromGregorian year 1 1
        decLast  = fromGregorian year 12 31
        s = max janFirst (arStartDay r)
        e = min decLast  (arEndDay r)
    in if s > e then 0 else fromIntegral (diffDays e s + 1)

-- | List of days in range [from, to] inclusive.
dayRange :: Day -> Day -> [Day]
dayRange from to
    | from > to = []
    | otherwise  = from : dayRange (addDays 1 from) to

-- ---------------------------------------------------------------------
-- Tests
-- ---------------------------------------------------------------------

abs_alice, abs_bob :: WorkerId
abs_alice = WorkerId 1
abs_bob   = WorkerId 2

abs_vacation, abs_training, abs_maternity :: AbsenceTypeId
abs_vacation  = AbsenceTypeId 1
abs_training  = AbsenceTypeId 2
abs_maternity = AbsenceTypeId 3

vacationType :: AbsenceType
vacationType = AbsenceType "Vacation" True

trainingType :: AbsenceType
trainingType = AbsenceType "Training" False

maternityType :: AbsenceType
maternityType = AbsenceType "Maternity Leave" False

absBaseCtx :: AbsenceContext
absBaseCtx = emptyAbsenceContext
    { acTypes = Map.fromList
        [ (abs_vacation,  vacationType)
        , (abs_training,  trainingType)
        , (abs_maternity, maternityType)
        ]
    , acYearlyAllowance = Map.fromList
        [ ((abs_alice, abs_vacation), 10)
        , ((abs_bob,   abs_vacation), 15)
        ]
    }

may4, may5, may8, may9, may11, may15 :: Day
may4  = fromGregorian 2026 5 4
may5  = fromGregorian 2026 5 5
may8  = fromGregorian 2026 5 8
may9  = fromGregorian 2026 5 9
may11 = fromGregorian 2026 5 11
may15 = fromGregorian 2026 5 15

spec :: Spec
spec = do
    describe "requestAbsence" $ do
        it "creates a pending request" $ do
            let (ctx, aid) = requestAbsence abs_alice abs_vacation may4 may8 absBaseCtx
                req = Map.lookup aid (acRequests ctx)
            fmap arStatus req `shouldBe` Just Pending
            fmap arWorker req `shouldBe` Just abs_alice
            fmap arType req `shouldBe` Just abs_vacation

        it "assigns unique IDs to successive requests" $ do
            let (ctx1, aid1) = requestAbsence abs_alice abs_vacation may4 may5 absBaseCtx
                (_, aid2) = requestAbsence abs_bob abs_training may8 may9 ctx1
            aid1 `shouldSatisfy` (/= aid2)

    describe "approveAbsence" $ do
        it "approves a pending request within allowance" $ do
            let (ctx, aid) = requestAbsence abs_alice abs_vacation may4 may8 absBaseCtx
                result = approveAbsence aid ctx
            result `shouldSatisfy` (/= Nothing)
            case result of
                Just ctx' -> do
                    let req = Map.lookup aid (acRequests ctx')
                    fmap arStatus req `shouldBe` Just Approved
                Nothing -> expectationFailure "expected approval"

        it "rejects approval when it would exceed yearly allowance" $ do
            let (ctx, aid) = requestAbsence abs_alice abs_vacation
                                may4 (fromGregorian 2026 5 14) absBaseCtx
            approveAbsence aid ctx `shouldBe` Nothing

        it "rejects approval of non-pending request" $ do
            let (ctx, aid) = requestAbsence abs_alice abs_vacation may4 may5 absBaseCtx
            case approveAbsence aid ctx of
                Nothing -> expectationFailure "approveAbsence returned Nothing"
                Just ctx' -> approveAbsence aid ctx' `shouldBe` Nothing

        it "rejects approval of nonexistent request" $
            approveAbsence (AbsenceId 999) absBaseCtx `shouldBe` Nothing

        it "considers already-approved days when checking allowance" $ do
            let (ctx1, aid1) = requestAbsence abs_alice abs_vacation may4 may8 absBaseCtx
            case approveAbsence aid1 ctx1 of
                Nothing -> expectationFailure "approveAbsence returned Nothing"
                Just ctx2 -> do
                    let (ctx3, aid2) = requestAbsence abs_alice abs_vacation
                                           may11 (fromGregorian 2026 5 16) ctx2
                    approveAbsence aid2 ctx3 `shouldBe` Nothing

        it "approves when exactly at allowance boundary" $ do
            let (ctx1, aid1) = requestAbsence abs_alice abs_vacation may4 may8 absBaseCtx
            case approveAbsence aid1 ctx1 of
                Nothing -> expectationFailure "approveAbsence returned Nothing"
                Just ctx2 -> do
                    let (ctx3, aid2) = requestAbsence abs_alice abs_vacation
                                           may11 may15 ctx2
                    approveAbsence aid2 ctx3 `shouldSatisfy` (/= Nothing)

    describe "approveAbsenceOverride" $ do
        it "approves even when over allowance" $ do
            let (ctx, aid) = requestAbsence abs_alice abs_vacation
                                may4 (fromGregorian 2026 5 14) absBaseCtx
            approveAbsenceOverride aid ctx `shouldSatisfy` (/= Nothing)

    describe "rejectAbsence" $ do
        it "rejects a pending request" $ do
            let (ctx, aid) = requestAbsence abs_alice abs_vacation may4 may8 absBaseCtx
            case rejectAbsence aid ctx of
                Nothing -> expectationFailure "rejectAbsence returned Nothing"
                Just ctx' -> do
                    let req = Map.lookup aid (acRequests ctx')
                    fmap arStatus req `shouldBe` Just Rejected

        it "fails on non-pending request" $ do
            let (ctx, aid) = requestAbsence abs_alice abs_vacation may4 may8 absBaseCtx
            case approveAbsence aid ctx of
                Nothing -> expectationFailure "approveAbsence returned Nothing"
                Just ctx' -> rejectAbsence aid ctx' `shouldBe` Nothing

    describe "Uncapped absence types (training, maternity)" $ do
        it "training has no yearly limit — always approvable" $ do
            let (ctx, aid) = requestAbsence abs_alice abs_training
                                may4 (fromGregorian 2026 5 31) absBaseCtx
            approveAbsence aid ctx `shouldSatisfy` (/= Nothing)

        it "maternity leave has no yearly limit" $ do
            let (ctx, aid) = requestAbsence abs_alice abs_maternity
                                (fromGregorian 2026 3 1) (fromGregorian 2026 5 31) absBaseCtx
            approveAbsence aid ctx `shouldSatisfy` (/= Nothing)

    describe "absenceDaysInYear" $ do
        it "counts approved days in the given year" $ do
            let (ctx1, aid1) = requestAbsence abs_alice abs_vacation may4 may8 absBaseCtx
            case approveAbsence aid1 ctx1 of
                Nothing -> expectationFailure "approveAbsence returned Nothing"
                Just ctx2 -> absenceDaysInYear abs_alice abs_vacation 2026 ctx2 `shouldBe` 5

        it "does not count pending requests" $ do
            let (ctx, _) = requestAbsence abs_alice abs_vacation may4 may8 absBaseCtx
            absenceDaysInYear abs_alice abs_vacation 2026 ctx `shouldBe` 0

        it "does not count rejected requests" $ do
            let (ctx1, aid1) = requestAbsence abs_alice abs_vacation may4 may8 absBaseCtx
            case rejectAbsence aid1 ctx1 of
                Nothing -> expectationFailure "rejectAbsence returned Nothing"
                Just ctx2 -> absenceDaysInYear abs_alice abs_vacation 2026 ctx2 `shouldBe` 0

        it "only counts days falling within the queried year" $ do
            let (ctx1, aid1) = requestAbsence abs_alice abs_vacation
                                   (fromGregorian 2026 12 28) (fromGregorian 2027 1 3) absBaseCtx
            case approveAbsenceOverride aid1 ctx1 of
                Nothing -> expectationFailure "approveAbsenceOverride returned Nothing"
                Just ctx2 -> do
                    absenceDaysInYear abs_alice abs_vacation 2026 ctx2 `shouldBe` 4
                    absenceDaysInYear abs_alice abs_vacation 2027 ctx2 `shouldBe` 3

    describe "absenceHoursInYear" $ do
        it "is 8 times the day count" $ do
            let (ctx1, aid1) = requestAbsence abs_alice abs_training may4 may8 absBaseCtx
            case approveAbsence aid1 ctx1 of
                Nothing -> expectationFailure "approveAbsence returned Nothing"
                Just ctx2 -> absenceHoursInYear abs_alice abs_training 2026 ctx2 `shouldBe` 40

    describe "vacationDaysRemaining" $ do
        it "returns full allowance with no absences" $
            vacationDaysRemaining abs_alice abs_vacation 2026 absBaseCtx
                `shouldBe` Just 10

        it "decreases after approved absences" $ do
            let (ctx1, aid1) = requestAbsence abs_alice abs_vacation may4 may8 absBaseCtx
            case approveAbsence aid1 ctx1 of
                Nothing -> expectationFailure "approveAbsence returned Nothing"
                Just ctx2 ->
                    vacationDaysRemaining abs_alice abs_vacation 2026 ctx2
                        `shouldBe` Just 5

        it "returns Nothing for uncapped types" $
            vacationDaysRemaining abs_alice abs_training 2026 absBaseCtx
                `shouldBe` Nothing

    describe "isWorkerAvailable" $ do
        it "is True when no absences" $
            isWorkerAvailable abs_alice may4 absBaseCtx `shouldBe` True

        it "is False on an approved absence day" $ do
            let (ctx1, aid1) = requestAbsence abs_alice abs_vacation may4 may8 absBaseCtx
            case approveAbsence aid1 ctx1 of
                Nothing -> expectationFailure "approveAbsence returned Nothing"
                Just ctx2 -> isWorkerAvailable abs_alice may5 ctx2 `shouldBe` False

        it "is True outside the absence range" $ do
            let (ctx1, aid1) = requestAbsence abs_alice abs_vacation may4 may8 absBaseCtx
            case approveAbsence aid1 ctx1 of
                Nothing -> expectationFailure "approveAbsence returned Nothing"
                Just ctx2 -> isWorkerAvailable abs_alice may9 ctx2 `shouldBe` True

        it "is True for pending (unapproved) absences" $ do
            let (ctx, _) = requestAbsence abs_alice abs_vacation may4 may8 absBaseCtx
            isWorkerAvailable abs_alice may5 ctx `shouldBe` True

        it "other workers are unaffected" $ do
            let (ctx1, aid1) = requestAbsence abs_alice abs_vacation may4 may8 absBaseCtx
            case approveAbsence aid1 ctx1 of
                Nothing -> expectationFailure "approveAbsence returned Nothing"
                Just ctx2 -> isWorkerAvailable abs_bob may5 ctx2 `shouldBe` True

    describe "unavailableDays" $ do
        it "returns the set of absent days in a range" $ do
            let (ctx1, aid1) = requestAbsence abs_alice abs_vacation may4 may8 absBaseCtx
            case approveAbsence aid1 ctx1 of
                Nothing -> expectationFailure "approveAbsence returned Nothing"
                Just ctx2 ->
                    unavailableDays abs_alice may4 may11 ctx2
                        `shouldBe` Set.fromList [may4, may5, fromGregorian 2026 5 6,
                                                 fromGregorian 2026 5 7, may8]

        it "clips to the queried range" $ do
            let (ctx1, aid1) = requestAbsence abs_alice abs_vacation may4 may8 absBaseCtx
            case approveAbsence aid1 ctx1 of
                Nothing -> expectationFailure "approveAbsence returned Nothing"
                Just ctx2 ->
                    unavailableDays abs_alice may5 (fromGregorian 2026 5 6) ctx2
                        `shouldBe` Set.fromList [may5, fromGregorian 2026 5 6]

    describe "workerAbsencesInRange" $ do
        it "finds overlapping absences" $ do
            let (ctx1, aid1) = requestAbsence abs_alice abs_vacation may4 may8 absBaseCtx
            case approveAbsence aid1 ctx1 of
                Nothing -> expectationFailure "approveAbsence returned Nothing"
                Just ctx2 -> do
                    let (ctx3, aid2) = requestAbsence abs_alice abs_training may11 may15 ctx2
                    case approveAbsence aid2 ctx3 of
                        Nothing -> expectationFailure "approveAbsence returned Nothing"
                        Just ctx4 ->
                            length (workerAbsencesInRange abs_alice may4 may15 ctx4) `shouldBe` 2

        it "excludes non-overlapping absences" $ do
            let (ctx1, aid1) = requestAbsence abs_alice abs_vacation may4 may5 absBaseCtx
            case approveAbsence aid1 ctx1 of
                Nothing -> expectationFailure "approveAbsence returned Nothing"
                Just ctx2 ->
                    length (workerAbsencesInRange abs_alice may8 may15 ctx2) `shouldBe` 0
