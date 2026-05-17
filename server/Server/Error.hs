{-# LANGUAGE OverloadedStrings #-}

module Server.Error
    ( ApiError(..)
    , throwApiError
    , throwConflictWithBody
    ) where

import Data.Aeson (ToJSON, object, (.=), encode, toJSON)
import Servant (ServerError(..), err400, err401, err403, err404, err409, err500, Handler, throwError)

data ApiError
    = NotFound String
    | BadRequest String
    | Unauthorized String
    | Forbidden String
    | Conflict String
    | InternalError String
    deriving (Show)

throwApiError :: ApiError -> Handler a
throwApiError (NotFound msg)      = throwError $ withJsonBody err404 msg
throwApiError (BadRequest msg)    = throwError $ withJsonBody err400 msg
throwApiError (Unauthorized msg)  = throwError $ withJsonBody err401 msg
throwApiError (Forbidden msg)     = throwError $ withJsonBody err403 msg
throwApiError (Conflict msg)      = throwError $ withJsonBody err409 msg
throwApiError (InternalError msg) = throwError $ withJsonBody err500 msg

-- | Throw a 409 Conflict with an arbitrary JSON-encodable body.
throwConflictWithBody :: ToJSON a => a -> Handler b
throwConflictWithBody body = throwError $ err409
    { errBody = encode (toJSON body)
    , errHeaders = [("Content-Type", "application/json")]
    }

withJsonBody :: ServerError -> String -> ServerError
withJsonBody base msg = base
    { errBody = encode (object ["error" .= msg])
    , errHeaders = [("Content-Type", "application/json")]
    }
