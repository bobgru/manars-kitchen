module Service.Auth
    ( AuthError(..)
    , register
    , login
    , changePassword
    ) where

import Data.Text (Text)
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

register :: Repository -> Text -> Text -> Role -> WorkerId -> IO (Either AuthError UserId)
register repo name plainPass role wid = do
    existing <- repoGetUserByName repo name
    case existing of
        Just _  -> return (Left UsernameTaken)
        Nothing -> do
            mHash <- hashPassword plainPass
            case mHash of
                Nothing   -> return (Left HashingFailed)
                Just hash -> Right <$> repoCreateUser repo name hash role wid

login :: Repository -> Text -> Text -> IO (Either AuthError User)
login repo name plainPass = do
    mUser <- repoGetUserByName repo name
    case mUser of
        Nothing   -> return (Left InvalidCredentials)
        Just user
            | checkPassword plainPass (userPassHash user) -> return (Right user)
            | otherwise -> return (Left InvalidCredentials)

changePassword :: Repository -> UserId -> Text -> Text -> IO (Either AuthError ())
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
