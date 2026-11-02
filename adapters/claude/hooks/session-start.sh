#!/bin/bash
# Claude Code SessionStart hook: stdout becomes context.
[ -n "$MINDPALACE_HOOK" ] && exit 0
D="$(cd "$(dirname "$0")/../../.." && pwd)"
source "$D/core/common.sh"; source "$D/core/memory.sh"; mp_adapter claude
input=$(cat)
cwd=$(mp_path "$(jq -r '.cwd // empty' <<<"$input")"); [ -z "$cwd" ] && cwd="$PWD"
mp_catchup claude "$(jq -r '.session_id // empty' <<<"$input")" >/dev/null 2>&1
mp_memory "$cwd"
exit 0
