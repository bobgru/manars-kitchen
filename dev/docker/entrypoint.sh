#!/bin/bash
#
# Applies the egress firewall as root, then drops to the unprivileged user.
#
# The privilege drop is not optional: Claude Code refuses to start with
# --dangerously-skip-permissions when running as root or under sudo.

set -euo pipefail

USERNAME="${CONTAINER_USER:-bobgru}"
USER_UID="$(id -u "$USERNAME")"
USER_GID="$(id -g "$USERNAME")"

if [ "$(id -u)" -eq 0 ]; then
    if [ "${SKIP_FIREWALL:-0}" = "1" ]; then
        echo "[entrypoint] SKIP_FIREWALL=1 -- egress is UNRESTRICTED" >&2
    else
        /usr/local/bin/init-firewall.sh
    fi

    # Named volumes are created root-owned; the agent user needs to write its
    # own config directory.
    chown "$USER_UID:$USER_GID" "/home/${USERNAME}/.claude" 2>/dev/null || true

    # Drop privileges for everything that follows. --init-groups picks up
    # supplementary groups; the user has no sudo rights beyond the firewall
    # script, which has already run.
    exec setpriv --reuid="$USER_UID" --regid="$USER_GID" --init-groups -- "$@"
fi

exec "$@"
