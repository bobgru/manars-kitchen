module Main (main) where

import System.IO (hFlush, stdout, hSetEcho, stdin)
import System.Environment (getArgs)
import System.Exit (exitFailure)
import Data.Time.Clock (getCurrentTime)
import Data.Time.Format (formatTime, defaultTimeLocale)

import Auth.Types (User(..), Username(..), Role(..))
import Domain.Types (WorkerId(..))
import Repo.SQLite (mkSQLiteRepo)
import Repo.Types (Repository(..))
import Service.Auth (register, login)
import CLI.App (mkAppState, runRepl, runDemo)

main :: IO ()
main = do
    args <- getArgs
    let (demoDelay, rest) = parseDelay args
    case rest of
        ["--help"]       -> printUsage
        ["-h"]           -> printUsage
        ["--demo", file] -> demoFromFile demoDelay file
        ["--demo"]       -> demoFromFile demoDelay "demo/restaurant-setup.txt"
        _ -> do
            let dbPath = case args of
                    [p] -> p
                    _   -> "run-db/manars-kitchen.db"
            putStrLn $ "Using database: " ++ dbPath
            (_conn, repo) <- mkSQLiteRepo dbPath
            ensureAdminExists repo
            user <- loginLoop repo
            st <- mkAppState repo user
            runRepl st

-- | Parse all flags from args in any order.
-- Returns (delay in microseconds, remaining positional/flag args).
-- Default demo delay is 500ms.
parseDelay :: [String] -> (Int, [String])
parseDelay = go (500000, [])
  where
    go (_, acc) ("--no-delay" : rest)  = go (0, acc) rest
    go (_, acc) ("--delay" : ms : rest)
        | all (`elem` "0123456789") ms = go (read ms * 1000, acc) rest
    go (d, acc) (x : rest)             = go (d, acc ++ [x]) rest
    go (d, acc) []                     = (d, acc)

demoFromFile :: Int -> FilePath -> IO ()
demoFromFile delayUs file = do
    now <- getCurrentTime
    let stamp = formatTime defaultTimeLocale "%Y%m%d-%H%M%S" now
        dbPath = "demo-db/demo-" ++ stamp ++ ".db"
    putStrLn $ "Demo database: " ++ dbPath
    putStrLn $ "Script: " ++ file
    putStrLn ""
    (_conn, repo) <- mkSQLiteRepo dbPath
    contents <- readFile file
    let cmds = filter (\l -> not (null l)) (lines contents)
    runDemo repo delayUs cmds

-- | Ensure at least one admin user exists. If not, create default admin/admin.
ensureAdminExists :: Repository -> IO ()
ensureAdminExists repo = do
    users <- repoListUsers repo
    case filter (\u -> userRole u == Admin) users of
        [] -> do
            result <- register repo "admin" "admin" Admin (WorkerId 1)
            case result of
                Right _uid ->
                    putStrLn "Created default admin user (admin/admin), Worker 1"
                Left err -> do
                    putStrLn $ "Error creating admin: " ++ show err
                    exitFailure
        _ -> return ()

printUsage :: IO ()
printUsage = do
    putStrLn "Usage: manars-cli [OPTIONS] [DATABASE]"
    putStrLn ""
    putStrLn "Options:"
    putStrLn "  --help, -h          Show this help message"
    putStrLn "  --demo [FILE]       Run demo (default: demo/restaurant-setup.txt)"
    putStrLn "  --no-delay          Skip delay between demo commands"
    putStrLn "  --delay <ms>        Set demo delay in milliseconds (default: 500)"
    putStrLn ""
    putStrLn "Arguments:"
    putStrLn "  DATABASE            SQLite database path (default: run-db/manars-kitchen.db)"
    putStrLn ""
    putStrLn "Type 'help' at the REPL prompt for available commands."

loginLoop :: Repository -> IO User
loginLoop repo = do
    putStr "Username: "
    hFlush stdout
    name <- getLine
    putStr "Password: "
    hFlush stdout
    hSetEcho stdin False
    pass <- getLine
    hSetEcho stdin True
    putStrLn ""
    result <- login repo name pass
    case result of
        Right user -> do
            let Username uname = userName user
            putStrLn $ "Welcome, " ++ uname ++ "!"
            return user
        Left _ -> do
            putStrLn "Invalid credentials. Try again."
            loginLoop repo
