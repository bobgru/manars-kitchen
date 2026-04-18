# Shell-Style Quoting for Command Arguments

## Problem

The command parser splits input with Haskell's `words`, which has no quote
awareness. Multi-word names like `"pizza oven"` cannot be entered via the
terminal pane -- `skill rename 1 "pizza oven"` produces five tokens instead
of four and falls through to `Unknown`. The only workaround is to use the
REST API directly, bypassing the terminal entirely.

## Solution

Replace `words` with a `shellWords` function that respects single and double
quotes with backslash escapes inside them. Drop it into the two call sites
(`CLI.Commands.parseCommand` and `Audit.CommandMeta.classify`) as a
direct replacement for `words`.

### Quoting rules

- **Double quotes**: `"pizza oven"` -> `pizza oven`
- **Single quotes**: `'pizza oven'` -> `pizza oven`
- **Escaped quotes inside**: `"Bob\"s Grill"` -> `Bob"s Grill`,
  `'Bob\'s Grill'` -> `Bob's Grill`
- **Unquoted tokens**: split on whitespace as before
- **Unclosed quotes**: lenient -- treat everything after the opening quote
  to end-of-input as one token (no error)

### Changes

1. **New function `shellWords`** in `CLI.Commands` (or a small utility module).
   Pure Haskell, no dependencies, ~15-20 lines. Character-by-character state
   machine with three states: unquoted, in-single-quote, in-double-quote.

2. **Two call-site changes**:
   - `CLI.Commands.parseCommand`: `words input` -> `shellWords input`
   - `Audit.CommandMeta.classify`: `words input` -> `shellWords input`

3. **Tests** for `shellWords` covering: basic splitting, double-quoted strings,
   single-quoted strings, escaped quotes, unclosed quotes, empty input,
   mixed quoted and unquoted tokens.

### What doesn't change

- No command patterns change -- they still match on the same token lists
- No `Command` constructors change
- No frontend changes -- the web terminal already sends raw strings
- No REST API changes

## Out of Scope

- Nested quotes (`"it's a 'test'"` treated as opaque inside double quotes,
  which is correct POSIX behavior but not explicitly tested)
- Tab completion or readline-style editing in the web terminal
- Helpful error messages suggesting quoting when too many tokens are detected
  (considered and deferred)
