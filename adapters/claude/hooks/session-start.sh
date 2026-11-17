#!/bin/bash
# Claude Code SessionStart hook: stdout becomes context.
[ -n "$MINDPALACE_HOOK" ] && exit 0
D="$(cd "$(dirname "$0")/../../.." && pwd)"
source "$D/core/common.sh"; source "$D/core/memory.sh"; mp_adapter claude
input=$(cat)
cwd=$(mp_path "$(jq -r '.cwd // empty' <<<"$input")"); [ -z "$cwd" ] && cwd="$PWD"
sid=$(jq -r '.session_id // empty' <<<"$input")
mp_recover_start claude "$sid"
mem=$(mp_memory "$cwd")
[ -n "$mem" ] && { printf '%s\n' "$mem"; mp_health_line; }
exit 0
