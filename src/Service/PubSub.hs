{-# LANGUAGE BangPatterns #-}
module Service.PubSub
    ( PubSub
    , SubscriptionId
    , ProgressEvent(..)
    , newPubSub
    , subscribe
    , unsubscribe
    , publish
    ) where

import Control.Concurrent.MVar
import qualified Data.Map.Strict as Map

import Domain.Optimizer (OptProgress(..))

-- | Opaque subscription identifier returned by 'subscribe'.
newtype SubscriptionId = SubscriptionId Int
    deriving (Eq, Ord)

-- | In-process typed event bus.  Supports zero, one, or many
-- concurrent subscribers.  Events published with no subscribers
-- are silently dropped.
data PubSub e = PubSub
    { psNextId      :: !(MVar Int)
    , psSubscribers :: !(MVar (Map.Map Int (e -> IO ())))
    }

-- | Progress events emitted by service-layer operations.
data ProgressEvent
    = OptimizeProgress OptProgress

-- | Create a new bus with no subscribers.
newPubSub :: IO (PubSub e)
newPubSub = PubSub <$> newMVar 0 <*> newMVar Map.empty

-- | Register a callback.  Returns a 'SubscriptionId' for later
-- removal via 'unsubscribe'.
subscribe :: PubSub e -> (e -> IO ()) -> IO SubscriptionId
subscribe bus handler = do
    sid <- modifyMVar (psNextId bus) $ \n ->
        let !n' = n + 1 in return (n', n)
    modifyMVar_ (psSubscribers bus) $ \m ->
        return $! Map.insert sid handler m
    return (SubscriptionId sid)

-- | Remove a subscription.  Subsequent publishes will not invoke
-- the removed callback.
unsubscribe :: PubSub e -> SubscriptionId -> IO ()
unsubscribe bus (SubscriptionId sid) =
    modifyMVar_ (psSubscribers bus) $ \m ->
        return $! Map.delete sid m

-- | Publish an event to all current subscribers.  If no subscribers
-- are registered, the event is silently dropped.
publish :: PubSub e -> e -> IO ()
publish bus event = do
    subs <- readMVar (psSubscribers bus)
    mapM_ (\handler -> handler event) (Map.elems subs)
