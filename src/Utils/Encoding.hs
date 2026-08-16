module Utils.Encoding (
    setUtf8Encoding
    ) where

import GHC.IO.Encoding (setLocaleEncoding)
import System.IO (hSetEncoding, stdin, stdout, stderr, utf8)

-- | Read and write UTF-8 regardless of the ambient locale. Call this first in
-- every @main@.
--
-- This project's output is not ASCII: help text and demo scripts contain em
-- dashes, hspec prints check marks. Under a POSIX or C locale GHC picks ASCII
-- for the standard handles, and the first such character kills the program with
--
-- > commitBuffer: invalid argument (cannot encode character '\8212')
--
-- which reads like an IO bug rather than an encoding mismatch. Both test suites
-- failed this way on a host with @LANG@ unset.
--
-- 'setLocaleEncoding' fixes handles opened later, so reading a UTF-8 demo script
-- works too; the three standard handles already exist by now and need setting
-- individually.
setUtf8Encoding :: IO ()
setUtf8Encoding = do
    setLocaleEncoding utf8
    mapM_ (`hSetEncoding` utf8) [stdin, stdout, stderr]
