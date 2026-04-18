{-# LANGUAGE BangPatterns #-}
module Service.PubSub
    ( TopicBus
    , Topic(..)
    , SubscriptionId
    , ProgressEvent(..)
    , Source(..)
    , CommandEvent(..)
    , AppBus(..)
    , newTopicBus
    , newAppBus
    , subscribe
    , unsubscribe
    , publish
    , buildTopic
    , publishCommand
    , sourceString
    ) where

import Control.Concurrent.MVar
import qualified Data.Map.Strict as Map
import Data.Maybe (catMaybes)
import Text.Regex.Posix ((=~))

import Domain.Optimizer (OptProgress(..))
import Audit.CommandMeta (CommandMeta(..), classify)

-- | Topic for routing events.
newtype Topic = Topic String
    deriving (Eq, Ord, Show)

-- | Opaque subscription identifier returned by 'subscribe'.
newtype SubscriptionId = SubscriptionId Int
    deriving (Eq, Ord)

-- | In-process typed event bus with topic-based routing.
-- Subscribers register with a regex pattern and only receive
-- events whose topic matches.
data TopicBus e = TopicBus
    { tbNextId      :: !(MVar Int)
    , tbSubscribers :: !(MVar (Map.Map Int (String, Topic -> e -> IO ())))
    }

-- | Progress events emitted by service-layer operations.
data ProgressEvent
    = OptimizeProgress OptProgress

-- | Origin of a command event.
data Source = CLI | RPC | GUI | Demo
    deriving (Eq, Show)

-- | Payload for domain mutation events.
data CommandEvent = CommandEvent
    { ceCommand  :: !String
    , ceMeta     :: !CommandMeta
    , ceSource   :: !Source
    , ceUsername  :: !String
    }

-- | Application-level container holding typed channels.
data AppBus = AppBus
    { busCommands :: !(TopicBus CommandEvent)
    , busProgress :: !(TopicBus ProgressEvent)
    }

-- | Create a new topic bus with no subscribers.
newTopicBus :: IO (TopicBus e)
newTopicBus = TopicBus <$> newMVar 0 <*> newMVar Map.empty

-- | Create an AppBus with all channels.
newAppBus :: IO AppBus
newAppBus = AppBus <$> newTopicBus <*> newTopicBus

-- | Register a callback with a regex pattern.
-- The callback is invoked for events whose topic matches the pattern.
subscribe :: TopicBus e -> String -> (Topic -> e -> IO ()) -> IO SubscriptionId
subscribe bus pattern_ handler = do
    sid <- modifyMVar (tbNextId bus) $ \n ->
        let !n' = n + 1 in return (n', n)
    modifyMVar_ (tbSubscribers bus) $ \m ->
        return $! Map.insert sid (pattern_, handler) m
    return (SubscriptionId sid)

-- | Remove a subscription.
unsubscribe :: TopicBus e -> SubscriptionId -> IO ()
unsubscribe bus (SubscriptionId sid) =
    modifyMVar_ (tbSubscribers bus) $ \m ->
        return $! Map.delete sid m

-- | Publish an event to all subscribers whose regex matches the topic.
publish :: TopicBus e -> Topic -> e -> IO ()
publish bus topic@(Topic topicStr) event = do
    subs <- readMVar (tbSubscribers bus)
    mapM_ (\(pat, handler) ->
        if topicStr =~ ("^" ++ pat ++ "$" :: String) :: Bool
            then handler topic event
            else return ()
        ) (Map.elems subs)

-- | Build a topic from structured metadata.
buildTopic :: CommandMeta -> Topic
buildTopic meta = Topic $ intercalate' "." $ catMaybes
    [ cmEntityType meta
    , cmOperation meta
    , fmap show (cmEntityId meta)
    ]

-- | Build and publish a CommandEvent from a raw command string.
publishCommand :: TopicBus CommandEvent -> Source -> String -> String -> IO ()
publishCommand bus source username cmdStr = do
    let meta  = classify cmdStr
        topic = buildTopic meta
        event = CommandEvent cmdStr meta source username
    publish bus topic event

-- | Convert Source to the string used in the audit_log source column.
sourceString :: Source -> String
sourceString CLI  = "cli"
sourceString RPC  = "rpc"
sourceString GUI  = "gui"
sourceString Demo = "demo"

-- | Simple intercalate (avoids importing Data.List).
intercalate' :: String -> [String] -> String
intercalate' _ []     = ""
intercalate' _ [x]    = x
intercalate' sep (x:xs) = x ++ sep ++ intercalate' sep xs
