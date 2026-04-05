module Service.Auth
    ( AuthError(..)
    , register
    , login
    , changePassword
    ) where

import Auth.Types (UserId, Role, User(..))
import Auth.Password (hashPassword, checkPassword)
import Domain.Types (WorkerId)
import Repo.Types (Repository(..))

data AuthError
    = UsernameTaken
    | InvalidCredentials
    | HashingFailed
    | UserNotFound
    | WrongOldPassword
    deriving (Eq, Show)

-- | Register a new user. Returns error if username is taken.
register :: Repository -> String -> String -> Role -> WorkerId -> IO (Either AuthError UserId)
register repo name plainPass role wid = do
    existing <- repoGetUserByName repo name
    case existing of
        Just _  -> return (Left UsernameTaken)
        Nothing -> do
            mHash <- hashPassword plainPass
            case mHash of
                Nothing   -> return (Left HashingFailed)
                Just hash -> Right <$> repoCreateUser repo name hash role wid

-- | Authenticate a user by username and password.
login :: Repository -> String -> String -> IO (Either AuthError User)
login repo name plainPass = do
    mUser <- repoGetUserByName repo name
    case mUser of
        Nothing   -> return (Left InvalidCredentials)
        Just user
            | checkPassword plainPass (userPassHash user) -> return (Right user)
            | otherwise -> return (Left InvalidCredentials)

-- | Change a user's password. Requires the old password for verification.
changePassword :: Repository -> UserId -> String -> String -> IO (Either AuthError ())
changePassword repo uid oldPass newPass = do
    mUser <- repoGetUser repo uid
    case mUser of
        Nothing   -> return (Left UserNotFound)
        Just user
            | not (checkPassword oldPass (userPassHash user)) ->
                return (Left WrongOldPassword)
            | otherwise -> do
                mHash <- hashPassword newPass
                case mHash of
                    Nothing   -> return (Left HashingFailed)
                    Just hash -> do
                        repoUpdatePassword repo uid hash
                        return (Right ())
