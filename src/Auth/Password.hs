module Auth.Password
    ( hashPassword
    , checkPassword
    ) where

import Crypto.BCrypt
    ( hashPasswordUsingPolicy
    , slowerBcryptHashingPolicy
    , validatePassword
    )
import qualified Data.ByteString.Char8 as BS

-- | Hash a plaintext password using bcrypt.
hashPassword :: String -> IO (Maybe String)
hashPassword plain = do
    mHash <- hashPasswordUsingPolicy slowerBcryptHashingPolicy (BS.pack plain)
    return (BS.unpack <$> mHash)

-- | Check a plaintext password against a stored bcrypt hash.
checkPassword :: String -> String -> Bool
checkPassword plain hash =
    validatePassword (BS.pack hash) (BS.pack plain)
