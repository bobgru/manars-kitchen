{-# LANGUAGE OverloadedStrings #-}

module Server.Error
    ( ApiError(..)
    , throwApiError
    ) where

import Data.Aeson (object, (.=), encode)
import Servant (ServerError(..), err400, err404, err409, err500, Handler, throwError)

data ApiError
    = NotFound String
    | BadRequest String
    | Conflict String
    | InternalError String
    deriving (Show)

throwApiError :: ApiError -> Handler a
throwApiError (NotFound msg)      = throwError $ withJsonBody err404 msg
throwApiError (BadRequest msg)    = throwError $ withJsonBody err400 msg
throwApiError (Conflict msg)      = throwError $ withJsonBody err409 msg
throwApiError (InternalError msg) = throwError $ withJsonBody err500 msg

withJsonBody :: ServerError -> String -> ServerError
withJsonBody base msg = base
    { errBody = encode (object ["error" .= msg])
    , errHeaders = [("Content-Type", "application/json")]
    }
