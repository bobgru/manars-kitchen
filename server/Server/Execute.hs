module Server.Execute
    ( ExecuteEnv(..)
    , newExecuteEnv
    , executeCommandText
    ) where

import Control.Concurrent.MVar (MVar, newMVar, withMVar)
import Control.Exception (SomeException, evaluate, try)
import GHC.IO.Handle (hDuplicate, hDuplicateTo)
import System.IO (stdout, hFlush, hClose, hGetContents, hSetEncoding, utf8)
import System.Process (createPipe)

import Auth.Types (User(..))
import Repo.Types (Repository, SessionId(..))
import Service.PubSub (AppBus(..), newAppBus)
import CLI.App (mkAppState, handleCommand, registerAuditSubscriber)
import CLI.Commands (Command(..), parseCommand)

-- | Environment for command execution. Holds an MVar to serialize
--   stdout capture across concurrent requests.
data ExecuteEnv = ExecuteEnv
    { eeRepo :: !Repository
    , eeLock :: !(MVar ())
    , eeBus  :: !AppBus
    }

-- | Create a new execution environment with a shared event bus.
newExecuteEnv :: Repository -> IO ExecuteEnv
newExecuteEnv repo = do
    lock <- newMVar ()
    bus  <- newAppBus
    _ <- registerAuditSubscriber (busCommands bus) repo
    return (ExecuteEnv repo lock bus)

-- | Parse and execute a command string, returning the formatted text output.
--   Thread-safe: concurrent calls are serialized via MVar.
executeCommandText :: ExecuteEnv -> User -> String -> IO String
executeCommandText env user input = do
    let cmd = parseCommand input
    case cmd of
        Quit -> return "Use the browser logout button to end your session."
        PasswordChange -> return "Password change is not supported in the web terminal."
        _ -> captureStdout (eeLock env) $ do
            -- Create a temporary AppState with default (empty) IORefs.
            -- This makes the terminal stateless: context, checkpoints,
            -- unfreezes, and hint sessions are not preserved between calls.
            st <- mkAppState (eeRepo env) user (SessionId 0)
            handleCommand st cmd

-- | Capture everything written to stdout during an IO action.
--   Uses an MVar to ensure only one capture runs at a time.
--   Stdout is redirected to a pipe; the pipe is read after the action completes.
captureStdout :: MVar () -> IO () -> IO String
captureStdout lock action = withMVar lock $ \() -> do
    (readH, writeH) <- createPipe
    hSetEncoding readH utf8
    hSetEncoding writeH utf8
    origStdout <- hDuplicate stdout
    hDuplicateTo writeH stdout
    hClose writeH
    -- Run the action; catch exceptions to ensure stdout is always restored.
    _ <- try action :: IO (Either SomeException ())
    hFlush stdout
    -- Restore original stdout. This also closes the pipe's write end,
    -- which allows hGetContents on readH to see EOF.
    hDuplicateTo origStdout stdout
    hClose origStdout
    -- Read all captured output.
    output <- hGetContents readH
    _ <- evaluate (length output)
    hClose readH
    return output
