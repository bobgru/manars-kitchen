{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE OverloadedStrings #-}

module Server.Auth
    ( -- * Auth types
      SessionAuth
      -- * Auth handler
    , authHandler
      -- * Login/logout
    , LoginReq(..)
    , LoginResp(..)
    , handleLogin
    , handleLogout
      -- * Authorization helpers
    , requireAdmin
    , requireSelfOrAdmin
    ) where

import Control.Monad (when)
import Control.Monad.IO.Class (liftIO)
import Data.Aeson (ToJSON(..), FromJSON(..), (.=), (.:), object, withObject)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BS8
import Data.Time.Clock (getCurrentTime, diffUTCTime)
import Network.Wai (Request, requestHeaders)
import Servant
    ( Handler, NoContent(..), throwError, ServerError(..)
    , err401, err403
    )
import Servant.Server.Experimental.Auth (AuthHandler, mkAuthHandler)
import Data.Aeson (encode)

import Auth.Types (User(..), UserId(..), Username(..), Role(..))
import Domain.Types (WorkerId(..))
import Repo.Types (Repository(..))
import qualified Service.Auth as SAuth

-- | Tag for Servant's generalized auth.
type SessionAuth = AuthHandler Request User

-- | Build the auth handler that validates session tokens.
authHandler :: Repository -> AuthHandler Request User
authHandler repo = mkAuthHandler handler
  where
    handler :: Request -> Handler User
    handler req = do
        -- Extract token from Authorization header
        let mAuth = lookup "Authorization" (requestHeaders req)
        tok <- case mAuth of
            Nothing -> throwError $ jsonError err401 "Missing authorization"
            Just bs -> case BS.stripPrefix "Bearer " bs of
                Nothing  -> throwError $ jsonError err401 "Invalid authorization format"
                Just t   -> return (BS8.unpack t)
        -- Look up session by token
        mSession <- liftIO $ repoGetSessionByToken repo tok
        case mSession of
            Nothing -> throwError $ jsonError err401 "Invalid session"
            Just (sid, uid, lastActive) -> do
                -- Check idle timeout
                now <- liftIO getCurrentTime
                timeout <- liftIO $ repoGetIdleTimeoutMinutes repo
                let elapsed = realToFrac (diffUTCTime now lastActive) / 60.0 :: Double
                when (elapsed > timeout) $
                    throwError $ jsonError err401 "Session expired"
                -- Touch session
                liftIO $ repoTouchSession repo sid
                -- Resolve user
                mUser <- liftIO $ repoGetUser repo uid
                case mUser of
                    Nothing -> throwError $ jsonError err401 "User not found"
                    Just u  -> return u

-- | JSON error helper for auth errors.
jsonError :: ServerError -> String -> ServerError
jsonError base msg = base
    { errBody = encode (object ["error" .= msg])
    , errHeaders = [("Content-Type", "application/json")]
    }

-- | Require the user to be Admin. Throws 403 if not.
requireAdmin :: User -> Handler ()
requireAdmin u = when (userRole u /= Admin) $
    throwError $ jsonError err403 "Forbidden"

-- | Require the user to be Admin or the worker ID to match. Throws 403 if not.
requireSelfOrAdmin :: User -> Int -> Handler ()
requireSelfOrAdmin u wid =
    when (userRole u /= Admin && userWorkerId u /= WorkerId wid) $
        throwError $ jsonError err403 "Forbidden"

-- -----------------------------------------------------------------
-- Login / Logout request/response types
-- -----------------------------------------------------------------

data LoginReq = LoginReq
    { lrUsername :: !String
    , lrPassword :: !String
    } deriving (Show)

instance FromJSON LoginReq where
    parseJSON = withObject "LoginReq" $ \v ->
        LoginReq <$> v .: "username" <*> v .: "password"

instance ToJSON LoginReq where
    toJSON r = object ["username" .= lrUsername r, "password" .= lrPassword r]

data LoginResp = LoginResp
    { lresToken    :: !String
    , lresUserId   :: !Int
    , lresUsername :: !String
    , lresRole     :: !String
    , lresWorkerId :: !Int
    } deriving (Show)

instance ToJSON LoginResp where
    toJSON r = object
        [ "token"    .= lresToken r
        , "user" .= object
            [ "id"       .= lresUserId r
            , "username" .= lresUsername r
            , "role"     .= lresRole r
            , "workerId" .= lresWorkerId r
            ]
        ]

instance FromJSON LoginResp where
    parseJSON = withObject "LoginResp" $ \v -> do
        tok <- v .: "token"
        u <- v .: "user"
        LoginResp tok <$> u .: "id" <*> u .: "username" <*> u .: "role" <*> u .: "workerId"

-- -----------------------------------------------------------------
-- Login handler
-- -----------------------------------------------------------------

handleLogin :: Repository -> LoginReq -> Handler LoginResp
handleLogin repo req = do
    result <- liftIO $ SAuth.login repo (lrUsername req) (lrPassword req)
    case result of
        Left _ -> throwError $ jsonError err401 "Invalid credentials"
        Right user -> do
            -- Close any existing active session
            mExisting <- liftIO $ repoGetActiveSession repo (userId user)
            case mExisting of
                Just existingSid -> liftIO $ repoCloseSession repo existingSid
                Nothing -> return ()
            -- Create new session
            (_sid, tok) <- liftIO $ repoCreateSession repo (userId user)
            let UserId uid = userId user
                Username uname = userName user
                WorkerId wid = userWorkerId user
                roleStr = case userRole user of
                    Admin  -> "admin"
                    Normal -> "normal"
            return $ LoginResp tok uid uname roleStr wid

-- -----------------------------------------------------------------
-- Logout handler
-- -----------------------------------------------------------------

handleLogout :: Repository -> User -> Handler NoContent
handleLogout repo user = do
    mSid <- liftIO $ repoGetActiveSession repo (userId user)
    case mSid of
        Just sid -> liftIO $ repoCloseSession repo sid
        Nothing  -> return ()
    return NoContent
