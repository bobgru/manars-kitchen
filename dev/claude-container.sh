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

    # Three supported auth paths, checked in the order they are preferred.
    # Bedrock is detected first because on a Bedrock host the other two are
    # absent by design and their error messages would be misleading.
    if [ "${CLAUDE_CODE_USE_BEDROCK:-0}" = "1" ] || [ -n "${AWS_PROFILE:-}" ]; then
        AUTH_MODE=bedrock
        export_bedrock_credentials
    elif [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then
        AUTH_MODE=oauth
    elif [ -n "${ANTHROPIC_API_KEY:-}" ]; then
        AUTH_MODE=apikey
    else
        die "no credentials in the environment.

Pick whichever matches how you authenticate:

  Bedrock (AWS SSO)
      export CLAUDE_CODE_USE_BEDROCK=1
      export AWS_PROFILE=dev AWS_REGION=us-east-1
      aws sso login --profile dev        # on the HOST; needs a browser
    This script then exports short-lived session credentials into the
    container. Note that 'claude setup-token' does NOT apply to Bedrock.

  Anthropic subscription
      claude setup-token                # on the HOST; needs a browser
      export CLAUDE_CODE_OAUTH_TOKEN=...
    Interactive /login cannot complete inside a headless container: the OAuth
    callback has no browser to return to.

  API key
      export ANTHROPIC_API_KEY=..."
    fi
}

# Turn the host's AWS SSO session into short-lived session credentials and pass
# those in, rather than mounting ~/.aws.
#
# Why: the SSO cache in ~/.aws holds a refresh token that can mint new
# credentials for the session's full lifetime. Exchanging it on the host and
# passing only the result means the container receives a credential that expires
# on its own and cannot be renewed from inside. It also keeps the SSO and OIDC
# endpoints off the egress allowlist entirely.
#
# Trade-off: when these expire the session stops working and you must restart the
# container. Role credentials here last ~9 hours, so that is rarely a problem in
# practice; run `aws sso login` on the host first if the session itself lapsed.
export_bedrock_credentials() {
    command -v aws >/dev/null 2>&1 || die "aws CLI not found on the host, but Bedrock auth was selected.
Either install it, or mount ~/.aws into the container instead (see
dev/docker/README.md)."

    local profile="${AWS_PROFILE:-default}"
    local creds
    if ! creds="$(aws configure export-credentials --profile "$profile" --format process 2>/dev/null)"; then
        die "could not export credentials for AWS profile '${profile}'.

The SSO session has most likely expired. On the HOST run:

    aws sso login --profile ${profile}

then re-run this script. Refresh has to happen on the host because it needs a
browser, which a headless container does not have."
    fi

    AWS_ACCESS_KEY_ID="$(printf '%s' "$creds"  | jq -r '.AccessKeyId')"
    AWS_SECRET_ACCESS_KEY="$(printf '%s' "$creds" | jq -r '.SecretAccessKey')"
    AWS_SESSION_TOKEN="$(printf '%s' "$creds"  | jq -r '.SessionToken')"
    AWS_CREDS_EXPIRY="$(printf '%s' "$creds"   | jq -r '.Expiration // "unknown"')"

    [ -n "$AWS_ACCESS_KEY_ID" ] && [ "$AWS_ACCESS_KEY_ID" != "null" ] \
        || die "credential export for profile '${profile}' returned nothing usable."

    echo "auth: Bedrock via profile '${profile}' in ${AWS_REGION:-us-east-1}" >&2
    echo "      credentials expire at ${AWS_CREDS_EXPIRY}" >&2
    echo "      (refresh with 'aws sso login --profile ${profile}' on the host," >&2
    echo "       then restart the container -- it cannot renew them itself)" >&2

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

    # Credentials are passed as environment variables, never baked into the
    # image. The firewall script also reads CLAUDE_CODE_USE_BEDROCK/AWS_REGION to
    # decide which inference endpoint to allow and health-check.
    local -a auth=()
    case "${AUTH_MODE:-}" in
        bedrock)
            auth=(
                -e "CLAUDE_CODE_USE_BEDROCK=1"
                -e "AWS_REGION=${AWS_REGION:-us-east-1}"
                -e "AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID:-}"
                -e "AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY:-}"
                -e "AWS_SESSION_TOKEN=${AWS_SESSION_TOKEN:-}"
            )
            # AWS_PROFILE is deliberately NOT forwarded: with explicit
            # credentials in the environment, a profile name would send the SDK
            # looking for a ~/.aws that is not mounted.
            [ -n "${ANTHROPIC_MODEL:-}" ] && auth+=(-e "ANTHROPIC_MODEL=${ANTHROPIC_MODEL}")
            ;;
        oauth)  auth=(-e "CLAUDE_CODE_OAUTH_TOKEN=${CLAUDE_CODE_OAUTH_TOKEN}") ;;
        apikey) auth=(-e "ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}") ;;
    esac

    docker run --rm "${tty[@]}" \
        --hostname manars-claude \
        "${caps[@]}" \
        "${mounts[@]}" \
        "${auth[@]}" \
        -e "CONTAINER_USER=$CONTAINER_USER" \
        -e "SKIP_FIREWALL=${SKIP_FIREWALL:-0}" \
        -e "ALLOWED_DOMAINS_EXTRA=${ALLOWED_DOMAINS_EXTRA:-}" \
        -w "$REPO_DIR" \
        "$IMAGE" "$@"
}

case "${1:-shell}" in
    build)  build ;;
    yolo)   shift; run claude --dangerously-skip-permissions "$@" ;;
    shell)  shift || true; run bash -l ;;
    *)      run "$@" ;;
esac
