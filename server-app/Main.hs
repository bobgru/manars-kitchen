{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Network.Wai (Application, pathInfo, requestMethod)
import Network.Wai.Application.Static
    (staticApp, defaultFileServerSettings, ssIndices, ssLookupFile)
import Network.Wai.Handler.Warp (run)
import Servant (serveWithContext, Context(..))
import System.Environment (getArgs)
import WaiAppStatic.Types (unsafeToPiece, LookupResult(..))

import Repo.SQLite (mkSQLiteRepo)
import Server.Api (fullApi)
import Server.Auth (authHandler)
import Server.Execute (newExecuteEnv)
import Server.Handlers (fullServer)

main :: IO ()
main = do
    args <- getArgs
    let (dbPath, port) = parseArgs args
    putStrLn $ "Database: " ++ dbPath
    putStrLn $ "Listening on port " ++ show port
    (_conn, repo) <- mkSQLiteRepo dbPath
    execEnv <- newExecuteEnv repo
    let ctx = authHandler repo :. EmptyContext
        servantApp = serveWithContext fullApi ctx (fullServer execEnv repo)
    run port (spaFallback "web/dist" servantApp)

parseArgs :: [String] -> (String, Int)
parseArgs []     = ("run-db/manars-kitchen.db", 8080)
parseArgs [db]   = (db, 8080)
parseArgs [db,p] = (db, read p)
parseArgs _      = error "Usage: manars-server [DATABASE] [PORT]"

-- | Middleware that serves static files from the given directory.
--   For GET requests that don't match an API route or a static file,
--   falls back to index.html (SPA routing).
--   Non-GET requests and /api/* or /rpc/* paths go straight to Servant.
spaFallback :: FilePath -> Application -> Application
spaFallback dir servantApp req sendResponse =
    case pathInfo req of
        ("api" : _) -> servantApp req sendResponse
        ("rpc" : _) -> servantApp req sendResponse
        _ | requestMethod req == "GET" ->
              staticWithSpaFallback dir servantApp req sendResponse
          | otherwise -> servantApp req sendResponse

-- | Try static file first; if not found, serve index.html.
--   If index.html doesn't exist either, fall through to Servant (404).
staticWithSpaFallback :: FilePath -> Application -> Application
staticWithSpaFallback dir _servantApp req sendResponse = do
    let settings = (defaultFileServerSettings dir)
            { ssIndices = [unsafeToPiece "index.html"]
            }
        -- For non-root paths, check if the file exists; if not, serve index.html
        fallbackSettings = settings
            { ssLookupFile = \pieces -> do
                result <- ssLookupFile settings pieces
                case result of
                    LRNotFound -> ssLookupFile settings [unsafeToPiece "index.html"]
                    _ -> return result
            }
    staticApp fallbackSettings req sendResponse
