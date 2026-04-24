{-# LANGUAGE OverloadedStrings #-}

module Server.EventStream (eventStreamApp) where

import Control.Concurrent (forkIO, threadDelay, killThread)
import Control.Concurrent.Chan (newChan, readChan, writeChan)
import Control.Exception (bracket, SomeException, try)
import Control.Monad (when, forever)
import Data.Aeson (encode, object, (.=))
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.ByteString.Builder (Builder, byteString, lazyByteString)
import Data.Time.Clock (getCurrentTime, diffUTCTime)
import Network.HTTP.Types (status200, status401)
import Network.Wai (Application, queryString, responseLBS, responseStream)

import Auth.Types (User(..), Username(..))
import Repo.Types (Repository(..))
import Audit.CommandMeta (CommandMeta(..))
import Service.PubSub (AppBus(..), CommandEvent(..), subscribe, unsubscribe, sourceString)

eventStreamApp :: Repository -> AppBus -> Application
eventStreamApp repo bus req sendResponse = do
    let mToken = lookup "token" (queryString req) >>= id
    case mToken of
        Nothing -> send401 "Missing token"
        Just tokBS -> do
            let tok = TE.decodeUtf8 tokBS
            mSession <- repoGetSessionByToken repo tok
            case mSession of
                Nothing -> send401 "Invalid session"
                Just (sid, uid, lastActive) -> do
                    now <- getCurrentTime
                    timeout <- repoGetIdleTimeoutMinutes repo
                    let elapsed = realToFrac (diffUTCTime now lastActive) / 60.0 :: Double
                    if elapsed > timeout
                        then send401 "Session expired"
                        else do
                            repoTouchSession repo sid
                            mUser <- repoGetUser repo uid
                            case mUser of
                                Nothing -> send401 "User not found"
                                Just user -> streamEvents bus user
  where
    send401 msg = sendResponse $ responseLBS status401
        [("Content-Type", "text/plain")] msg

    streamEvents appBus user = do
        let Username uname = userName user
            cmdBus = busCommands appBus
        -- Bus subscriber callbacks run on the publisher's thread, but WAI's
        -- write/flush are only safe from the responseStream callback thread.
        -- Route events through a Chan to decouple them.
        chan <- newChan
        sendResponse $ responseStream status200
            [ ("Content-Type", "text/event-stream")
            , ("Cache-Control", "no-cache")
            , ("Connection", "keep-alive")
            ] $ \write flush ->
                bracket
                    (subscribe cmdBus ".*" $ \_ event ->
                        when (cmIsMutation (ceMeta event) && ceUsername event == T.unpack uname) $
                            writeChan chan $ byteString "data: "
                                <> lazyByteString (encode $ object
                                    [ "command"    .= ceCommand event
                                    , "source"     .= sourceString (ceSource event)
                                    , "username"   .= ceUsername event
                                    , "entityType" .= cmEntityType (ceMeta event)
                                    , "operation"  .= cmOperation (ceMeta event)
                                    , "entityId"   .= cmEntityId (ceMeta event)
                                    , "clientId"   .= ceClientId event
                                    ])
                                <> byteString "\n\n"
                    )
                    (\subId -> unsubscribe cmdBus subId)
                    (\_ -> do
                        -- WAI's responseStream defers sending HTTP headers until
                        -- the first write+flush.  Without this, the browser's
                        -- EventSource stays in CONNECTING state indefinitely.
                        write (byteString ":ok\n\n")
                        flush
                        keepaliveThread <- forkIO $ forever $ do
                            threadDelay (30 * 1000000)
                            writeChan chan keepaliveMsg
                        let loop = do
                                msg <- readChan chan
                                ok <- try (write msg >> flush) :: IO (Either SomeException ())
                                case ok of
                                    Right () -> loop
                                    Left _   -> return ()
                        loop
                        killThread keepaliveThread
                    )

keepaliveMsg :: Builder
keepaliveMsg = byteString ":keepalive\n\n"
