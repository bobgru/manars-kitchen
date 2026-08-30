# Container for running Claude Code with permission prompts disabled.
#
# Design constraints, in order of importance:
#
#   1. Claude Code refuses to start with --dangerously-skip-permissions as root,
#      so the agent must run as an unprivileged user.
#   2. The image owns the Haskell toolchain: GHC and every dependency of
#      manars-kitchen are built in here. The host's ~/.stack is NOT mounted any
#      more. That mount required the host to be Linux on a matching
#      architecture, with GHC actually present in ~/.stack/programs -- three
#      assumptions that all fail on a macOS host, where GHC lives in ~/.ghcup as
#      Mach-O binaries. Self-contained costs image size and buys portability.
#      Stack still bakes absolute paths into its caches, so the container user's
#      name, uid, gid and HOME continue to match the host.
#   3. Every download is architecture-selected (`dpkg --print-architecture`), so
#      the image builds on both x86_64 Linux and arm64 macOS. Ubuntu 24.04 also
#      ships git 2.43, which fixes `wt list`'s would-conflict pre-flight -- broken
#      on the Linux host's git 2.34.1 because `git merge-tree --write-tree` needs
#      git >= 2.38.
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
      # GHC's runtime and link-time dependencies. libgmp-dev, not just libgmp10:
      # GHC needs the libgmp.so symlink at link time, and its absence is the
      # `cannot find -lgmp` failure documented in docs/STATUS.md.
      libgmp10 libgmp-dev libtinfo6 zlib1g-dev build-essential \
      # Egress firewall.
      iptables ipset iproute2 dnsutils \
      # Quality of life for an agent working in a shell.
      ripgrep less procps unzip \
    && rm -rf /var/lib/apt/lists/*

# Ubuntu 24.04 ships a uid 1000 "ubuntu" user that collides with ours; remove it
# before creating the matching account.
#
# The gid may already be taken by a system group. On macOS `id -g` is 20, which
# is `dialout` in Ubuntu, so an unconditional groupadd fails with
# "GID '20' already exists" and the build dies here. Reuse whatever group owns
# that gid instead: what the mounted repo needs is the numeric gid to match, not
# the group's name.
RUN if id -u ubuntu >/dev/null 2>&1; then userdel -r ubuntu 2>/dev/null || true; fi \
    && if ! getent group "$USER_GID" >/dev/null; then \
           groupadd --gid "$USER_GID" "$USERNAME"; \
       fi \
    && useradd --uid "$USER_UID" --gid "$USER_GID" --create-home --shell /bin/bash "$USERNAME"

# Node, pinned. Installed from the official tarball rather than a distro or
# NodeSource package so the version matches the host exactly.
RUN set -eux; \
    case "$(dpkg --print-architecture)" in \
      amd64) node_arch=x64 ;; \
      arm64) node_arch=arm64 ;; \
      *) echo "unsupported architecture: $(dpkg --print-architecture)" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${node_arch}.tar.xz" \
      -o /tmp/node.tar.xz; \
    tar -xJf /tmp/node.tar.xz -C /usr/local --strip-components=1 \
         --exclude CHANGELOG.md --exclude LICENSE --exclude README.md; \
    rm /tmp/node.tar.xz; \
    node --version && npm --version

# Stack, pinned. GHC arrives further down via `stack setup`, which picks the
# compiler the pinned snapshot asks for rather than us naming a version twice.
RUN set -eux; \
    case "$(dpkg --print-architecture)" in \
      amd64) stack_arch=x86_64 ;; \
      arm64) stack_arch=aarch64 ;; \
      *) echo "unsupported architecture: $(dpkg --print-architecture)" >&2; exit 1 ;; \
    esac; \
    dir="stack-${STACK_VERSION}-linux-${stack_arch}"; \
    curl -fsSL "https://github.com/commercialhaskell/stack/releases/download/v${STACK_VERSION}/${dir}.tar.gz" \
      -o /tmp/stack.tar.gz; \
    tar -xzf /tmp/stack.tar.gz -C /tmp; \
    install -m 0755 "/tmp/${dir}/stack" /usr/local/bin/stack; \
    rm -rf /tmp/stack.tar.gz "/tmp/${dir}"; \
    stack --version

RUN npm install -g @anthropic-ai/claude-code && claude --version

# AWS CLI, for Bedrock users. Not needed to authenticate -- the launcher passes
# already-exchanged session credentials as environment variables, which the SDK
# reads directly -- but diagnosing an auth failure inside a container without it
# is painful. `aws sts get-caller-identity` is the one-line answer to "are my
# credentials live?", which is why sts is on the egress allowlist.
RUN set -eux; \
    case "$(dpkg --print-architecture)" in \
      amd64) aws_arch=x86_64 ;; \
      arm64) aws_arch=aarch64 ;; \
      *) echo "unsupported architecture: $(dpkg --print-architecture)" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${aws_arch}.zip" -o /tmp/awscli.zip; \
    unzip -q /tmp/awscli.zip -d /tmp; \
    /tmp/aws/install; \
    rm -rf /tmp/awscli.zip /tmp/aws; \
    aws --version

# Note: sudo is deliberately NOT installed. The entrypoint applies the firewall
# while still root and then drops privileges permanently, so the agent user
# never needs to escalate -- and cannot.

COPY dev/docker/init-firewall.sh /usr/local/bin/init-firewall.sh
COPY dev/docker/entrypoint.sh    /usr/local/bin/entrypoint.sh
RUN chmod 0755 /usr/local/bin/init-firewall.sh /usr/local/bin/entrypoint.sh

# Worktrunk, pinned. Upstream publishes prebuilt *static musl* binaries, so this
# needs no Rust toolchain and costs ~8 MB -- which is why it is installed here
# rather than mounted from the host. The old mount
# (-v "$WT_BIN:/usr/local/bin/wt:ro") only worked when host and container shared
# OS and architecture: on a macOS host it is a Mach-O binary in a Linux container
# and every `wt` call died with "exec format error". See README 5.7.
#
# Bump: fetch the new tag's *.tar.xz.sha256 from the release page and paste both
# sums. The build fails loudly on mismatch rather than installing something else.
ARG WORKTRUNK_VERSION=0.75.0
RUN set -eux; \
    case "$(dpkg --print-architecture)" in \
      amd64) wt_arch=x86_64; \
             wt_sha=9ca16c77245c01edb079620a4375a8a49046fded4d4e571dd21930fd0235eca3 ;; \
      arm64) wt_arch=aarch64; \
             wt_sha=2504fdc07152fadd2c53c6d71268c6684aa08fb9f5a3ea4ec740c8747d3dde88 ;; \
      *) echo "unsupported architecture: $(dpkg --print-architecture)" >&2; exit 1 ;; \
    esac; \
    dir="worktrunk-${wt_arch}-unknown-linux-musl"; \
    curl -fsSL "https://github.com/max-sixty/worktrunk/releases/download/v${WORKTRUNK_VERSION}/${dir}.tar.xz" \
      -o /tmp/wt.tar.xz; \
    echo "${wt_sha}  /tmp/wt.tar.xz" | sha256sum -c -; \
    tar -xJf /tmp/wt.tar.xz -C /tmp; \
    install -m 0755 "/tmp/${dir}/wt" /usr/local/bin/wt; \
    rm -rf /tmp/wt.tar.xz "/tmp/${dir}"; \
    wt --version

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

# ---------------------------------------------------------------------------
# Haskell toolchain and dependencies.
#
# Only the three files that define the build are copied, so Docker's layer cache
# reuses everything below whenever they are unchanged -- editing source does not
# invalidate it. That is the whole point: a rebuild after a code change is
# instant, and the next build shares the compiled dependencies.
#
# `stack setup` installs the compiler the pinned snapshot asks for (lts-24.35 =>
# GHC 9.10.3) rather than naming a version here that could drift from
# stack.yaml.
#
# Run as $USERNAME so ~/.stack is owned by the agent, which then needs no write
# to root-owned paths. Switch back to root at the end: the entrypoint applies
# iptables before dropping privileges with setpriv.
#
# NOTE for whoever edits this: do not add --fast to any stack invocation, here or
# at runtime. It changes the build flags, so none of this matches and the whole
# dependency set recompiles. See CLAUDE.md.
# ---------------------------------------------------------------------------
# The staging directory must be writable by $USERNAME: stack creates a
# .stack-work in the working directory even for --only-dependencies.
RUN install -d -o "$USER_UID" -g "$USER_GID" "/home/${USERNAME}/deps"
COPY --chown=${USER_UID}:${USER_GID} \
     stack.yaml stack.yaml.lock manars-kitchen.cabal Setup.hs \
     /home/${USERNAME}/deps/

USER ${USERNAME}
RUN set -eux; \
    cd "$HOME/deps"; \
    stack setup; \
    stack build --only-dependencies; \
    stack path --compiler-exe; \
    rm -rf "$HOME/deps/.stack-work"
USER root

WORKDIR /home/${USERNAME}/fun/manars-kitchen

# Starts as root to apply iptables, then drops to $USERNAME.
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash", "-l"]
