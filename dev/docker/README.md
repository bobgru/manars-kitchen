# Running Claude Code without permission prompts, in a container

Analysis, decisions and assumptions behind `dev/claude-container.sh`.
Written 2026-08-16. Shareable as-is.

Everything marked **VERIFIED** was tested on the machine described below, with
the observed output quoted. Everything marked **DOCUMENTED** comes from
Anthropic's published docs. Everything marked **UNCONFIRMED** is neither — treat
it as a risk, not a fact.

---

## 1. The problem

Claude Code asks permission before each tool call. That is the right default, but
it makes long autonomous runs impractical. `--dangerously-skip-permissions`
("YOLO mode") removes the prompts and, with them, the last line of defence
against a destructive command.

The common claim is that a container makes YOLO mode safe. That is **half true**,
and the half that is false matters. A container bounds what an agent can reach.
It does nothing about what the agent can do to what you deliberately handed it.

The design below is built on a specific safety argument rather than on "it's in
Docker, so it's fine":

1. A **PreToolUse hook** refuses destructive git commands. This is the primary
   control, and it must survive YOLO mode (§3).
2. The hook must be **un-editable by the agent** — otherwise a YOLO session can
   remove its own restraint (§4.2).
3. **Egress is default-deny.** With prompting off, the network is the main
   exfiltration path left (§4.4).
4. **Writable surface is deliberately small** and everything on it is
   reconstructible (§4.3, §6).

---

## 2. Assumptions

This setup assumes all of the following. Where an assumption fails, the safety
argument weakens — noted per item.

| # | Assumption | If it does not hold |
|---|---|---|
| A1 | **A git guardrail PreToolUse hook is installed and executable.** Ours is `~/.claude/hooks/block-dangerous-git.sh`, wired from `~/.claude/settings.json`, blocking `git push`, `reset --hard`, `clean -f`, `branch -D`, `checkout .`, `restore .`, `wt step push`. | YOLO mode has no protection against destructive git commands. The launcher refuses to start (`preflight`) rather than run unprotected. |
| A2 | **The hook is executable.** A non-executable hook **fails open** — the tool call proceeds. | Silent loss of all protection. The launcher checks `-x` explicitly for this reason. |
| A3 | **The repo is trusted.** Anthropic's docs are explicit that a container does not stop a malicious project from exfiltrating anything reachable inside it, including Claude credentials. | This design is not a malware sandbox. Do not point it at untrusted code. |
| A4 | **Docker is usable without sudo** and the kernel supports `NET_ADMIN`/`NET_RAW` for iptables. | The firewall cannot be applied. `SKIP_FIREWALL=1` degrades to no egress control — announced loudly at startup. |
| A5 | **Single-user Linux workstation, uid/gid 1000.** The container user is built to match. | The mounted build cache is unusable (see A6) and file ownership breaks. Rebuild the image with `--build-arg USER_UID=...`. |
| A6 | **A large host build cache exists and is worth reusing.** Here: `~/.stack`, 116 GB. | Drop the mount and accept a long cold start. This is the single biggest performance decision. |
| A7 | **Worktrunk (`wt`) is used for parallel agents**, and its worktree path template is under our control. Default template places worktrees in a *sibling* directory of the repo. | Worktrees land outside the bind mount and are invisible to the container. See §5.3. |
| A8 | **Credentials are supplied by environment variable**, obtained on the host. Interactive `/login` cannot complete in a headless container — the OAuth callback cannot reach a browser, and neither can an AWS SSO login. | No authentication. See §7 for the three paths; note `claude setup-token` is **not** the answer for Bedrock. |
| A9 | **Mounted paths are reconstructible.** Repo is in git; the build cache can be rebuilt. | You are trusting a YOLO agent with unrecoverable data. Don't. |

---

## 3. The load-bearing finding: hooks still fire in YOLO mode

**The question:** does a `PreToolUse` hook still execute, and still block, when
permission prompts are skipped? The entire safety argument rests on this.

**What the docs say — DOCUMENTED, and insufficient.** Anthropic's permission-modes
documentation states that explicit `ask` rules still force a prompt in
`bypassPermissions` mode. It says **nothing** about whether `PreToolUse` hooks
execute, and nothing about whether `deny` rules survive. Both are **UNCONFIRMED**
from documentation alone. Reasoning by analogy from `ask` rules to hooks is
tempting and unsound — they are different mechanisms.

**VERIFIED by direct experiment.** The probe: a command the guardrail blocks
(`git branch -D`) against a **nonexistent** branch, so the test is harmless
whichever way it resolves — blocked means the hook works; not blocked means git
errors on a missing branch and nothing is destroyed.

```
$ claude -p --dangerously-skip-permissions < probe.txt
PreToolUse:Bash hook error: BLOCKED: git branch -D zzz-nonexistent-guardrail-probe
Matched dangerous pattern: \bgit +branch +-[a-zA-Z]*D
```

The hook fired and blocked the call. Re-confirmed **inside the container**:

```
BLOCKED  git push origin master
BLOCKED  git -C /home/.../.worktrees/x push
BLOCKED  git reset --hard
BLOCKED  wt step push
allowed  wt merge
allowed  git status
```

**Re-verify this after every Claude Code upgrade.** It is undocumented behaviour
and could change without notice. The probe above is safe to re-run and takes
seconds. If it ever stops blocking, this whole setup is unsound until fixed.

**Defence in depth.** Because the behaviour is undocumented,
`dev/docker/claude-settings.json` *also* carries `ask` rules for the same
commands — the one mechanism documented to survive bypass mode. The hook stays
primary because it normalises the command first and therefore catches forms that
prefix-matched permission rules miss (§5.1).

---

## 4. Design decisions

### 4.1 Non-root container user — forced, not chosen

**DOCUMENTED:** Claude Code refuses to start with `--dangerously-skip-permissions`
as root or under sudo:

```
--dangerously-skip-permissions cannot be used with root/sudo privileges
```

The container therefore starts as root only long enough to program iptables,
then drops privileges permanently via `setpriv`. **`sudo` is deliberately not
installed** — the agent never needs to escalate and cannot.

### 4.2 Guardrail immutability via read-only bind mount

**The threat:** in YOLO mode Claude can write `~/.claude/settings.json` and
delete its own hook. Isolation is meaningless if the agent can disarm it.

**Decision:** mount the hook script and `settings.json` as **read-only bind
mounts**. Read-only bind mounts are enforced by the kernel — not even root
inside the container can write them.

**VERIFIED:**
```
attempting to modify the hook (should FAIL):
  bash: /opt/guardrails/block-dangerous-git.sh: Read-only file system
  correctly refused: hook is immutable
settings.json:
  correctly refused: settings are immutable
```

**Rejected alternative — admin/managed settings.** Claude Code supports
administrator-controlled settings that users cannot override, which is the
"proper" mechanism. We could not confirm the file path: it is assembled at
runtime inside the compiled binary rather than stored as a string literal, so
searching the installed package found only the bare filename. **UNCONFIRMED**, so
we did not depend on it. The read-only mount achieves the same end with a
guarantee we could test. If you can confirm the managed-settings path for your
platform, it is the cleaner option.

**Rejected alternative — mounting the host `~/.claude`.** Convenient for auth
persistence, but hands the agent write access to your host-wide Claude
configuration. Instead, container state lives in a **named volume**, with only
`settings.json` layered read-only over it.

### 4.3 Small, reconstructible writable surface

Writable: the repo, and the host build cache. Nothing else. Everything writable
is reconstructible (A9).

Deliberately **not** mounted:
- `~/.ssh` — Anthropic's self-hosted guidance advises against putting broad
  credentials in an agent environment. Nothing here needs it; pushes are blocked.
- Cloud credential directories — also `deny`-listed for reads in
  `claude-settings.json` as belt-and-braces.
- The repo's **parent** directory — it holds 33 unrelated projects. See §5.3 for
  the consequence and fix.

### 4.4 Default-deny egress

`init-firewall.sh` sets `iptables` `OUTPUT` policy to reject, then allows
loopback, DNS, established connections, and an ipset of resolved addresses for:

```
api.anthropic.com      downloads.claude.ai    storage.googleapis.com
code.claude.com        claude.com             registry.npmjs.org
```

`github.com` is **not** allowed. Viable here because dependencies come from the
mounted caches and pushes are blocked. Add it if you need to fetch or read PRs
inside the container, understanding it becomes an egress path.

**The script fails closed and self-tests.** A silently inert firewall is worse
than none, because it invites misplaced trust:

```
[firewall] verified: api.anthropic.com is reachable
[firewall] verified: egress to a non-allowlisted host is blocked
```

If either check fails the container refuses to start. Note the reachability test
judges the *connection*, not the HTTP status — a bare `GET` of an API root
legitimately returns 4xx.

**Bedrock users:** the allowlist is different. Traffic goes to
`bedrock-runtime.<region>.amazonaws.com`, not `api.anthropic.com`, and `sts` is
allowed so `aws sts get-caller-identity` works for diagnosis. The script switches
automatically on `CLAUDE_CODE_USE_BEDROCK`, and health-checks whichever endpoint
is actually in use — a health check against the wrong endpoint would pass while
the agent could not reach a model at all. Because credentials arrive
pre-exchanged (§7), the SSO and OIDC endpoints are *not* needed; if you switch to
mounting `~/.aws` and doing the token exchange in-container, you must add
`oidc.<region>.amazonaws.com` and `portal.sso.<region>.amazonaws.com`.

**Residual holes, stated plainly:**

- **An ipset cannot separate hostnames that share an address.** VERIFIED:
  `api.anthropic.com`, `claude.com` and `code.claude.com` all resolved to
  `160.79.104.10`. So allowing the docs domains also allows the API endpoint,
  and in Bedrock mode `api.anthropic.com` remains reachable despite being
  unnecessary. Anthropic endpoints are a benign case, but the general point is
  the limit of layer-3 filtering: any allowlisted domain grants every other
  domain sharing its CDN address. True hostname control needs an SNI-filtering
  proxy, which this setup does not have.
- **DNS is permitted** and is a low-bandwidth covert channel. Closing it needs a
  fixed-IP allowlist and no resolution.
- **Addresses rotate.** These endpoints sit behind pools that return a rotating
  subset per query; the script resolves each domain several times to widen
  coverage, but a long-running container can still outlive its entries and need a
  restart. AWS regional endpoints are the most prone to this.
- **`storage.googleapis.com` resolves to ~15 addresses** of shared Google
  infrastructure — a broad allowance. Drop it if you install no plugins.

### 4.5 Host status line, reused read-only

The container's `~/.claude` is a fresh named volume, so the host's status line is
not there. Rather than duplicate the script into the image, the launcher
bind-mounts the host's `~/.claude/statusline.sh` at
`/opt/statusline/statusline.sh` read-only and `claude-settings.json` points
`statusLine.command` at that path — the same pattern as the guardrail hook, and
for the same reason: a path outside `~/.claude` cannot be shadowed by the state
volume, and read-only means the agent cannot edit what runs on every render.

Every dependency the script has is already in the image: `bash`, `jq`, `awk`
(mawk), `sed`, `stty`, `git`. Its terminal-width probe walks `/proc` for an
ancestor's controlling tty, which works inside the container. VERIFIED by piping
a synthetic status JSON into the mounted script — three-zone layout with the
width honored.

The mount is **optional**: it is cosmetic, so a missing or non-executable script
warns in preflight instead of aborting, and the status line simply renders empty.

---

## 5. Non-obvious findings worth knowing

### 5.1 Naive guardrail patterns miss `git -C <dir> push`

Both the hook we started from and Claude Code's permission rules match command
**prefixes** or literal substrings. Git accepts global options *before* the
subcommand, so `git -C /path/to/worktree push` contains no literal `git push`
and slips through. This is not hypothetical: driving parallel worktrees from a
primary checkout is exactly `git -C <path>` shaped.

Our hook normalises first — collapsing whitespace and iteratively stripping
git's and worktrunk's global options — then matches. **VERIFIED** across 32
cases, including false-positive checks so ordinary work is not blocked:

```
BLOCKED  git -C dir -c k=v push          allowed  git log --grep=push
BLOCKED  git --git-dir=... push          allowed  git commit -m "add push handler"
BLOCKED  git branch -Dr origin/x         allowed  git branch -d merged-branch
```

### 5.2 `wt merge` should NOT be blocked

We initially blocked it as a "pushing command". **That was wrong.** `wt merge` is
entirely local — commit, squash, rebase, fast-forward, cleanup — and never
fetches or pushes. Blocking it also defeats a `pre-merge` hook used as a local
CI gate. `wt step push` is the command that actually pushes. Corrected.

### 5.3 Worktrees land outside the mount

Worktrunk's default path template is
`{{ repo_path }}/../{{ repo }}.{{ branch }}` — a **sibling** of the repo,
therefore outside a repo-only bind mount. Mounting the parent would expose
unrelated projects (A3, §4.3).

**Fix:** override in the container's worktrunk config —

```toml
worktree-path = "{{ repo_path }}/.worktrees/{{ branch | sanitize }}"
```

`.worktrees/` is already in worktrunk's built-in copy-ignored excludes. Add it to
`.gitignore`.

### 5.4 Reusing a host build cache requires identical user and HOME

Build tools bake absolute paths into their caches. Reusing the host's
`~/.stack` (116 GB: 58 GB of compiler toolchains, 56 GB of compiled
dependencies) requires the container user to match the host in **name, uid, gid
and HOME**. Get this wrong and the mount is dead weight.

Two incidental notes: Ubuntu 24.04 ships its own uid-1000 `ubuntu` user that
collides and must be removed first; and glibc is backward compatible, so a
newer base image runs the host's older-glibc compiler binaries fine.

**VERIFIED** — the container installs no compiler, yet:
```
toolchains visible: 26
The Glorious Glasgow Haskell Compilation System, version 9.10.3
$ stack build   →   0.47s (no-op, cache is live)
$ npm run build →   2.0s
```

### 5.5 A newer base image can fix host tooling bugs

The host's git 2.34.1 broke worktrunk's would-conflict pre-flight, which needs
`git merge-tree --write-tree` (git ≥ 2.38). The container's git 2.43 fixes it
incidentally. Worth checking whether your container is *better* than your host,
not merely equivalent.

### 5.6 Containers do not fix shared-`/tmp` test collisions

Our integration tests hardcode fixed `/tmp` database paths. Two concurrent runs
corrupt each other and produce **20–99 misleading failures on correct code**,
including trivial assertions. `/tmp` is container-local, so *one* container per
agent would isolate this — but a single container running parallel worktrees
still collides. Fix the test paths; don't rely on the container.

---

## 6. What this does NOT protect against

State this to anyone you share the setup with.

- **The mounts themselves.** A YOLO agent can wreck the working tree or delete
  the 116 GB cache. Recoverable, but the cache is slow to rebuild.
- **Non-git destruction.** The guardrail covers git. **Nothing stops `rm -rf`.**
- **Exfiltration over permitted egress.** Anthropic's docs are explicit that a
  container does not prevent a malicious project from exfiltrating anything
  reachable inside it — including the Claude credentials in the state volume.
  The allowlist narrows this; it does not close it.
- **Prompt injection.** Content the agent reads can redirect its behaviour. The
  guardrail constrains *actions*, not intentions.
- **`deny` rules in YOLO mode.** **UNCONFIRMED** whether they survive. The
  `deny` entries in `claude-settings.json` may be inert. Do not rely on them as
  a sole control.

The honest summary: this bounds blast radius and removes the most likely
catastrophic mistakes. It is not a security boundary against a determined
adversary.

---

## 7. Setup

The launcher auto-detects which of three auth paths you use and refuses to start
if none is available.

### Bedrock via AWS SSO (what this project uses)

```bash
# on the HOST -- needs a browser, so it cannot be done inside the container
aws sso login --profile dev

# usually already exported from your shell profile
export CLAUDE_CODE_USE_BEDROCK=1 AWS_PROFILE=dev AWS_REGION=us-east-1

./dev/claude-container.sh yolo
```

`claude setup-token` **does not apply to Bedrock** — it mints an Anthropic
subscription OAuth token, which a Bedrock deployment never uses.

The launcher runs `aws configure export-credentials` on the host and passes the
resulting short-lived session credentials in as environment variables. It prints
the expiry when it starts.

**Why exchange on the host rather than mount `~/.aws`:** the SSO cache holds a
refresh token that can mint fresh credentials for the whole session lifetime.
Exchanging on the host and passing only the result means the container holds a
credential that expires by itself and cannot be renewed from inside — and it
keeps the SSO/OIDC endpoints off the allowlist. The cost is that when it expires
the session stops; re-run `aws sso login` on the host and restart the container.
Observed lifetime here is ~9 hours, so this is rarely disruptive.

`AWS_PROFILE` is deliberately *not* forwarded into the container: with explicit
credentials in the environment, a profile name would send the SDK looking for a
`~/.aws` that is not mounted.

The image includes the AWS CLI purely for diagnosis —
`aws sts get-caller-identity` answers "are my credentials live?" in one line.

### Anthropic subscription, or an API key

```bash
claude setup-token                        # on the HOST; needs a browser
export CLAUDE_CODE_OAUTH_TOKEN=...        # or: export ANTHROPIC_API_KEY=...
./dev/claude-container.sh yolo
```

Interactive `/login` cannot complete in a headless container: the OAuth callback
has nowhere to return to.

### Common commands

```bash
./dev/claude-container.sh build           # (re)build the image
./dev/claude-container.sh yolo            # straight into YOLO mode
./dev/claude-container.sh shell           # plain shell, no agent
SKIP_FIREWALL=1 ./dev/claude-container.sh shell         # debugging only
ALLOWED_DOMAINS_EXTRA=github.com ./dev/claude-container.sh yolo   # widen egress
```

`preflight` refuses to start if the guardrail hook is missing or
non-executable (A1, A2), or if no credentials are available.

### Adapting to another repo

1. Replace the `~/.stack` mount with your ecosystem's cache, and confirm §5.4's
   user/HOME matching for it.
2. Adjust the pinned toolchain versions in the `Dockerfile` to match your host —
   particularly the language runtime, if you mount a dependency directory
   containing prebuilt native binaries.
3. Revisit the egress allowlist. Add your package registry if dependencies are
   not pre-cached.
4. Keep §4.1, §4.2 and §4.4 unchanged — they are the safety argument, not
   project detail.

### Acceptance checklist for a new machine

Run these and confirm each before trusting the setup:

- [ ] `id` inside the container is non-root, uid matches host
- [ ] writing to the mounted hook fails with `Read-only file system`
- [ ] writing to `~/.claude/settings.json` fails likewise
- [ ] both firewall self-tests pass at startup
- [ ] the `git branch -D <nonexistent>` probe is **BLOCKED** under
      `--dangerously-skip-permissions` (§3)
- [ ] `command -v sudo` finds nothing
- [ ] a real build completes without downloading dependencies

---

## 8. Known annoyance: false positives on prose

The hook inspects the **entire** Bash command line, so it blocks commands whose
*text* merely contains a pattern. This fired three times in one session on
completely legitimate work: a test harness with patterns in quoted arguments, a
nested prompt string, and a commit message that mentioned pushing.

**Workaround:** keep such text in a file — `git commit -F <file>`, prompts via
stdin — so the command line stays clean.

**Do not obfuscate commands to get around the hook.** If it blocks something
legitimate, move the text out of the command line or amend the pattern list
deliberately. Working around a guardrail defeats its purpose, and an agent
should escalate to a human instead.

A more precise hook would parse the command and inspect only the executable and
its arguments. That is a real improvement and is not implemented.

---

## 9. Unresolved

- The managed-settings path (§4.2) — confirming it would give a cleaner
  immutability mechanism than read-only mounts.
- Whether `permissions.deny` survives bypass mode (§6).
- DNS as a covert channel (§4.4) — closing it needs a fixed-IP allowlist.
- A command-parsing hook instead of regex matching (§8).
- Per-agent containers as isolation for parallel work (§5.6) — plausible, untried.

---

## Files

| Path | Role |
|---|---|
| `dev/claude-container.sh` | Launcher; mounts, capabilities, preflight checks |
| `dev/docker/Dockerfile` | Image; pinned toolchain, matching non-root user |
| `dev/docker/entrypoint.sh` | Applies firewall as root, drops privileges |
| `dev/docker/init-firewall.sh` | Egress allowlist with fail-closed self-tests |
| `dev/docker/claude-settings.json` | Hook wiring + redundant `ask`/`deny` rules + status line; mounted read-only |
| `~/.claude/hooks/block-dangerous-git.sh` | The guardrail itself (host-side; mounted in read-only) |
| `~/.claude/statusline.sh` | The status line (host-side; mounted in read-only, §4.5) |
