module Auth.Password
    ( hashPassword
    , checkPassword
    ) where

import Crypto.BCrypt
    ( hashPasswordUsingPolicy
    , slowerBcryptHashingPolicy
    , validatePassword
    )
import Data.Text (Text)
import qualified Data.Text.Encoding as TE

hashPassword :: Text -> IO (Maybe Text)
hashPassword plain = do
    mHash <- hashPasswordUsingPolicy slowerBcryptHashingPolicy (TE.encodeUtf8 plain)
    return (TE.decodeUtf8 <$> mHash)

checkPassword :: Text -> Text -> Bool
checkPassword plain hash =
    validatePassword (TE.encodeUtf8 hash) (TE.encodeUtf8 plain)
