module Main (main) where

import Network.Wai.Handler.Warp (run)
import Servant (serve)
import System.Environment (getArgs)

import Repo.SQLite (mkSQLiteRepo)
import Server.Api (api)
import Server.Handlers (server)

main :: IO ()
main = do
    args <- getArgs
    let (dbPath, port) = parseArgs args
    putStrLn $ "Database: " ++ dbPath
    putStrLn $ "Listening on port " ++ show port
    (_conn, repo) <- mkSQLiteRepo dbPath
    run port (serve api (server repo))

parseArgs :: [String] -> (String, Int)
parseArgs []     = ("run-db/manars-kitchen.db", 8080)
parseArgs [db]   = (db, 8080)
parseArgs [db,p] = (db, read p)
parseArgs _      = error "Usage: manars-server [DATABASE] [PORT]"
