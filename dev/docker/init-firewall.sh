#!/bin/bash
#
# Egress allowlist for the Claude Code container.
#
# With permission prompts disabled, the network is the main exfiltration path
# that remains, so default-deny outbound and permit only what Claude Code needs
# to function. Anthropic's own devcontainer docs are explicit that a container
# does not stop a malicious project from exfiltrating anything reachable from
# inside it -- this script is what makes "reachable" a short list.
#
# Deliberately NOT allowed: github.com. This project does not need it at
# runtime. Haskell dependencies come from the mounted ~/.stack (snapshot
# lts-24.35, already fully built) and the frontend's node_modules is mounted
# too, so neither Stackage/Hackage nor npm is contacted for a normal build. Git
# pushes are blocked by a PreToolUse hook regardless.
#
# Must run as root, and the container needs --cap-add NET_ADMIN --cap-add NET_RAW.

set -euo pipefail

# Domains Claude Code needs. Sourced from Anthropic's published network
# requirements; trim further if you do not use plugins or docs lookups.
ALLOWED_DOMAINS=(
    # Claude Code updates and plugin marketplace downloads.
    downloads.claude.ai
    # Plugin marketplace catalog and artifacts.
    storage.googleapis.com
    # Documentation lookups.
    code.claude.com
    claude.com
    # npm, for plugin installation. Drop this if you install no plugins.
    registry.npmjs.org
)

# Inference endpoint. Which one depends on how Claude Code authenticates, and
# getting this wrong means the agent cannot talk to a model at all.
#
#   Bedrock  -- traffic goes to a regional AWS endpoint; api.anthropic.com is
#               not used. Note it is not thereby *blocked*: api.anthropic.com,
#               claude.com and code.claude.com share a CDN address
#               (160.79.104.10 as of 2026-08), and an ipset works at layer 3, so
#               allowing the docs domains necessarily allows the API endpoint
#               too. Hostname-level separation would need an SNI-filtering
#               proxy. See dev/docker/README.md 4.4.
#   Direct   -- api.anthropic.com.
#
# The launcher passes CLAUDE_CODE_USE_BEDROCK and AWS_REGION through.
if [ "${CLAUDE_CODE_USE_BEDROCK:-0}" = "1" ]; then
    region="${AWS_REGION:-us-east-1}"
    ALLOWED_DOMAINS+=(
        "bedrock-runtime.${region}.amazonaws.com"
        # Identity validation, and useful for diagnosing auth failures from
        # inside the container.
        "sts.${region}.amazonaws.com"
    )
    # Credentials arrive as already-exchanged short-lived session tokens, so the
    # SSO/OIDC endpoints are NOT needed here. If you switch to mounting ~/.aws
    # and letting the container do the token exchange itself, you must also add
    # oidc.<region>.amazonaws.com and portal.sso.<region>.amazonaws.com.
    HEALTHCHECK_HOST="bedrock-runtime.${region}.amazonaws.com"
else
    ALLOWED_DOMAINS+=(api.anthropic.com)
    HEALTHCHECK_HOST="api.anthropic.com"
fi

# Allow callers to extend the list without editing this file.
if [ -n "${ALLOWED_DOMAINS_EXTRA:-}" ]; then
    # shellcheck disable=SC2206
    ALLOWED_DOMAINS+=(${ALLOWED_DOMAINS_EXTRA//,/ })
fi

log() { printf '[firewall] %s\n' "$*"; }

# A second run inside the same container should be a no-op rather than an error.
iptables -F OUTPUT 2>/dev/null || true
ipset destroy claude-allow 2>/dev/null || true

ipset create claude-allow hash:ip family inet

# Resolve each domain and add every A record. These sit behind load balancers
# that hand out a rotating subset of a larger pool, so resolve several times to
# widen coverage -- AWS regional endpoints in particular return a different
# handful per query. The set is rebuilt on every container start; a long-running
# container may still outlive its entries and need a restart.
RESOLVE_ROUNDS="${RESOLVE_ROUNDS:-3}"

for domain in "${ALLOWED_DOMAINS[@]}"; do
    declare -A seen=()
    for _ in $(seq "$RESOLVE_ROUNDS"); do
        while read -r ip; do
            [ -n "$ip" ] || continue
            seen["$ip"]=1
        done < <(dig +short A "$domain" 2>/dev/null | grep -E '^[0-9.]+$' || true)
    done

    if [ "${#seen[@]}" -eq 0 ]; then
        log "WARNING: could not resolve ${domain}; traffic to it will be dropped"
        unset seen
        continue
    fi
    for ip in "${!seen[@]}"; do
        ipset add claude-allow "$ip" -exist
    done
    log "allowed ${domain} (${#seen[@]} address(es))"
    unset seen
done

# Loopback is unrestricted: the project's own server and test suites talk to
# 127.0.0.1, and Claude Code's OAuth callback listens locally.
iptables -A OUTPUT -o lo -j ACCEPT

# DNS must be permitted or nothing can resolve. This is a known small covert
# channel; closing it entirely would require a fixed-IP allowlist and no DNS.
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT

# Replies to connections we already permitted.
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# The allowlist itself.
iptables -A OUTPUT -m set --match-set claude-allow dst -j ACCEPT

# Everything else is refused. REJECT rather than DROP so callers fail fast with
# an error instead of hanging until timeout.
iptables -A OUTPUT -j REJECT --reject-with icmp-port-unreachable

log "egress restricted to ${#ALLOWED_DOMAINS[@]} domain(s)"

# Fail loudly if the policy is not actually in force -- a silently inert
# firewall is worse than no firewall, because it invites misplaced trust.
#
# Reachability is judged on whether the connection completed, not on the HTTP
# status: a bare GET of the API root legitimately returns 4xx. So drop -f and
# test curl's exit code, where 0 means a response was received and 7/28/35 mean
# the connection was refused or timed out.
if curl -sS --max-time 8 -o /dev/null "https://${HEALTHCHECK_HOST}/" 2>/dev/null; then
    log "verified: ${HEALTHCHECK_HOST} is reachable (inference endpoint)"
else
    log "ERROR: ${HEALTHCHECK_HOST} is NOT reachable; Claude Code will not work."
    log "       If this host resolves to a rotating address pool, restart the"
    log "       container to rebuild the address set."
    exit 1
fi

if curl -sS --max-time 8 -o /dev/null https://example.com/ 2>/dev/null; then
    log "ERROR: reached example.com, which is not on the allowlist."
    log "       The firewall is NOT effective; refusing to continue."
    exit 1
else
    log "verified: egress to a non-allowlisted host is blocked"
fi
