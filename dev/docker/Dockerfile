# Container for running Claude Code with permission prompts disabled.
#
# Design constraints, in order of importance:
#
#   1. Claude Code refuses to start with --dangerously-skip-permissions as root,
#      so the agent must run as an unprivileged user.
#   2. The host's ~/.stack is mounted at runtime (116G: 58G of GHC toolchains
#      plus 56G of compiled snapshots). Stack bakes absolute paths into those
#      caches, so the container user's name, uid, gid and HOME must match the
#      host exactly or none of it is reusable.
#   3. Ubuntu 24.04's glibc 2.39 runs the host's glibc 2.35-linked GHC binaries
#      fine (glibc is backward compatible), and it ships git 2.43 -- which fixes
#      `wt list`'s would-conflict pre-flight, broken on the host's git 2.34.1
#      because `git merge-tree --write-tree` needs git >= 2.38.
#
# The container starts as root only long enough to apply the egress firewall,
# then drops to the unprivileged user via setpriv.

FROM ubuntu:24.04

# Match the host user so the mounted ~/.stack caches remain valid.
ARG USERNAME=bobgru
ARG USER_UID=1000
ARG USER_GID=1000

# Pin the toolchain to the host's versions. Node in particular is pinned exactly
# because web/node_modules is mounted from the host and contains prebuilt native
# binaries (esbuild, rollup); a matching runtime avoids any ABI surprises.
ARG NODE_VERSION=25.2.1
ARG STACK_VERSION=3.9.3

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl xz-utils \
      git \
      jq \
      # GHC runtime dependencies. The compiler itself comes from the mounted
      # ~/.stack/programs, but it still links against these.
      libgmp10 libtinfo6 zlib1g-dev build-essential \
      # Egress firewall.
      iptables ipset iproute2 dnsutils \
      # Quality of life for an agent working in a shell.
      ripgrep less procps unzip \
    && rm -rf /var/lib/apt/lists/*

# Ubuntu 24.04 ships a uid 1000 "ubuntu" user that collides with ours; remove it
# before creating the matching account.
RUN if id -u ubuntu >/dev/null 2>&1; then userdel -r ubuntu 2>/dev/null || true; fi \
    && groupadd --gid "$USER_GID" "$USERNAME" \
    && useradd --uid "$USER_UID" --gid "$USER_GID" --create-home --shell /bin/bash "$USERNAME"

# Node, pinned. Installed from the official tarball rather than a distro or
# NodeSource package so the version matches the host exactly.
RUN curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz" \
      -o /tmp/node.tar.xz \
    && tar -xJf /tmp/node.tar.xz -C /usr/local --strip-components=1 \
         --exclude CHANGELOG.md --exclude LICENSE --exclude README.md \
    && rm /tmp/node.tar.xz \
    && node --version && npm --version

# Stack, pinned. GHC is NOT installed here -- it arrives via the mounted
# ~/.stack/programs, which already holds ghc-tinfo6-9.10.3 for snapshot
# lts-24.35.
RUN curl -fsSL "https://github.com/commercialhaskell/stack/releases/download/v${STACK_VERSION}/stack-${STACK_VERSION}-linux-x86_64.tar.gz" \
      -o /tmp/stack.tar.gz \
    && tar -xzf /tmp/stack.tar.gz -C /tmp \
    && install -m 0755 "/tmp/stack-${STACK_VERSION}-linux-x86_64/stack" /usr/local/bin/stack \
    && rm -rf /tmp/stack.tar.gz "/tmp/stack-${STACK_VERSION}-linux-x86_64" \
    && stack --version

RUN npm install -g @anthropic-ai/claude-code && claude --version

# AWS CLI, for Bedrock users. Not needed to authenticate -- the launcher passes
# already-exchanged session credentials as environment variables, which the SDK
# reads directly -- but diagnosing an auth failure inside a container without it
# is painful. `aws sts get-caller-identity` is the one-line answer to "are my
# credentials live?", which is why sts is on the egress allowlist.
RUN curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscli.zip \
    && unzip -q /tmp/awscli.zip -d /tmp \
    && /tmp/aws/install \
    && rm -rf /tmp/awscli.zip /tmp/aws \
    && aws --version

# Note: sudo is deliberately NOT installed. The entrypoint applies the firewall
# while still root and then drops privileges permanently, so the agent user
# never needs to escalate -- and cannot.

COPY init-firewall.sh /usr/local/bin/init-firewall.sh
COPY entrypoint.sh    /usr/local/bin/entrypoint.sh
RUN chmod 0755 /usr/local/bin/init-firewall.sh /usr/local/bin/entrypoint.sh

# Relocate worktrees inside the repo. Worktrunk's default path template puts a
# worktree in a SIBLING directory of the repo, which would fall outside the
# single bind mount; the repo's parent holds unrelated projects and is
# deliberately not mounted. `.worktrees/` is already in worktrunk's built-in
# copy-ignored exclude list.
RUN install -d -o "$USER_UID" -g "$USER_GID" "/home/${USERNAME}/.config/worktrunk" \
    && printf '%s\n' \
        'worktree-path = "{{ repo_path }}/.worktrees/{{ branch | sanitize }}"' \
        > "/home/${USERNAME}/.config/worktrunk/config.toml" \
    && chown "$USER_UID:$USER_GID" "/home/${USERNAME}/.config/worktrunk/config.toml"

# Claude Code state (auth token, history, sessions) lives here. The launcher
# mounts a named volume over it so it survives rebuilds, and mounts
# settings.json over that read-only so the agent cannot disable its own hooks.
RUN install -d -o "$USER_UID" -g "$USER_GID" "/home/${USERNAME}/.claude" \
    && install -d -o root -g root /opt/guardrails /opt/statusline

ENV HOME=/home/${USERNAME} \
    CLAUDE_CONFIG_DIR=/home/${USERNAME}/.claude \
    DISABLE_ERROR_REPORTING=1 \
    DISABLE_TELEMETRY=1

WORKDIR /home/${USERNAME}/fun/manars-kitchen

# Starts as root to apply iptables, then drops to $USERNAME.
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash", "-l"]
