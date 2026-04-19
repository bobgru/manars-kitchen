module Utils (
    shellWords,
    shellQuote
    ) where

shellWords :: String -> [String]
shellWords = go [] . dropWhile (== ' ')
  where
    go acc [] = reverse acc
    go acc (q:cs) | q == '"' || q == '\'' = let (tok, rest) = quoted q cs
                                            in go (tok : acc) (dropWhile (== ' ') rest)
    go acc cs = let (tok, rest) = break (== ' ') cs
                in go (tok : acc) (dropWhile (== ' ') rest)

    quoted q = collect []
      where
        collect buf []            = (reverse buf, [])
        collect buf ('\\':c:rest) = collect (c : buf) rest
        collect buf (c:rest)
            | c == q    = (reverse buf, rest)
            | otherwise = collect (c : buf) rest

shellQuote :: String -> String
shellQuote s
    | null s                 = "\"\""
    | not (any needsQuoting s) = s
    | otherwise              = "\"" ++ concatMap esc s ++ "\""
  where
    needsQuoting c = c == ' ' || c == '"' || c == '\'' || c == '\\'
    esc '"'  = "\\\""
    esc '\\' = "\\\\"
    esc c    = [c]
