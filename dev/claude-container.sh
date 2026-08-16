#!/bin/bash
#
# Launch Claude Code in a container with permission prompts disabled.
#
#   ./dev/claude-container.sh              # interactive shell, claude ready
#   ./dev/claude-container.sh yolo         # straight into claude, prompts off
#   ./dev/claude-container.sh build        # (re)build the image
#   ./dev/claude-container.sh shell        # shell without starting claude
#
# What this does and does not protect:
#
#   Does    -- confines writes to the repo and ~/.stack, and confines network
#              egress to an allowlist of Anthropic domains. Keeps the git
#              guardrail hook un-editable by mounting it and the settings file
#              read-only.
#   Does NOT -- protect the mounted paths themselves. The agent can still damage
#              the repo working tree or the 116G ~/.stack cache; both are
#              recoverable but the cache is slow to rebuild. It also does not
#              prevent exfiltration of anything reachable inside the container
#              over the permitted egress. Only run this on a repo you trust.

set -euo pipefail

IMAGE=manars-kitchen-claude
STATE_VOLUME=manars-kitchen-claude-state

# Absolute host paths. The container deliberately mirrors them so Stack's cached
# absolute paths and worktrunk's repo_path templates keep working.
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTAINER_USER="$(id -un)"
CONTAINER_UID="$(id -u)"
CONTAINER_GID="$(id -g)"
CONTAINER_HOME="$HOME"

HOOK_SRC="$HOME/.claude/hooks/block-dangerous-git.sh"
SETTINGS_SRC="$REPO_DIR/dev/docker/claude-settings.json"
STACK_ROOT="$HOME/.stack"
WT_BIN="$(command -v wt || true)"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

build() {
    docker build \
        --build-arg "USERNAME=$CONTAINER_USER" \
        --build-arg "USER_UID=$CONTAINER_UID" \
        --build-arg "USER_GID=$CONTAINER_GID" \
        -t "$IMAGE" \
        "$REPO_DIR/dev/docker"
}

preflight() {
    [ -f "$HOOK_SRC" ] || die "git guardrail hook not found at $HOOK_SRC.
Run the git-guardrails setup first -- without it, skipping permission prompts
has no protection against destructive git commands."

    [ -x "$HOOK_SRC" ] || die "$HOOK_SRC is not executable (chmod +x it).
A non-executable hook fails open: the tool call proceeds."

    [ -d "$STACK_ROOT" ] || die "$STACK_ROOT not found; nothing to mount."

    if [ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" ] && [ -z "${ANTHROPIC_API_KEY:-}" ]; then
        die "no credentials in the environment.

Interactive /login does not work in a headless container -- the OAuth callback
cannot reach the browser. Instead, on the host run:

    claude setup-token

then export the value it prints and re-run this script:

    export CLAUDE_CODE_OAUTH_TOKEN=...

Alternatively export ANTHROPIC_API_KEY to bill via the API instead of your
subscription."
    fi

    docker image inspect "$IMAGE" >/dev/null 2>&1 || {
        echo "image $IMAGE not found; building it first" >&2
        build
    }
}

run() {
    preflight

    local -a mounts=(
        # The project. Read-write: this is the work.
        -v "$REPO_DIR:$REPO_DIR:rw"

        # 116G of prebuilt GHC toolchains and compiled snapshots. Read-write
        # because Stack writes pantry and stack.sqlite3 during a build.
        -v "$STACK_ROOT:$CONTAINER_HOME/.stack:rw"

        # Claude Code state (auth, history, sessions) persisted across runs, but
        # container-local -- deliberately NOT the host's ~/.claude, so a YOLO
        # session cannot rewrite the host's settings or hooks.
        -v "$STATE_VOLUME:$CONTAINER_HOME/.claude"

        # The guardrail, read-only. Mounted outside ~/.claude so the state
        # volume cannot shadow it.
        -v "$HOOK_SRC:/opt/guardrails/block-dangerous-git.sh:ro"

        # Settings, read-only and layered over the state volume. A read-only
        # bind mount cannot be written even by root inside the container, so the
        # hook cannot be unhooked.
        -v "$SETTINGS_SRC:$CONTAINER_HOME/.claude/settings.json:ro"
    )

    # Commit authorship inside the container.
    [ -f "$HOME/.gitconfig" ] && mounts+=(-v "$HOME/.gitconfig:$CONTAINER_HOME/.gitconfig:ro")

    # worktrunk, if installed on the host. Saves a Rust toolchain in the image.
    [ -n "$WT_BIN" ] && mounts+=(-v "$WT_BIN:/usr/local/bin/wt:ro")

    local -a caps=()
    if [ "${SKIP_FIREWALL:-0}" = "1" ]; then
        echo "WARNING: SKIP_FIREWALL=1 -- egress will be unrestricted" >&2
    else
        # Required to program iptables/ipset from inside the container.
        caps=(--cap-add NET_ADMIN --cap-add NET_RAW)
    fi

    # Only request a TTY when there is one; otherwise docker refuses to start
    # ("the input device is not a TTY"), which breaks scripted use and CI.
    local -a tty=(-i)
    [ -t 0 ] && [ -t 1 ] && tty=(-i -t)

    docker run --rm "${tty[@]}" \
        --hostname manars-claude \
        "${caps[@]}" \
        "${mounts[@]}" \
        -e "CONTAINER_USER=$CONTAINER_USER" \
        -e "SKIP_FIREWALL=${SKIP_FIREWALL:-0}" \
        -e "CLAUDE_CODE_OAUTH_TOKEN=${CLAUDE_CODE_OAUTH_TOKEN:-}" \
        -e "ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:-}" \
        -w "$REPO_DIR" \
        "$IMAGE" "$@"
}

case "${1:-shell}" in
    build)  build ;;
    yolo)   shift; run claude --dangerously-skip-permissions "$@" ;;
    shell)  shift || true; run bash -l ;;
    *)      run "$@" ;;
esac
