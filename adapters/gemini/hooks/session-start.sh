#!/bin/bash
# Gemini CLI SessionStart hook: stdout must be exactly one JSON object.
[ -n "$MINDPALACE_HOOK" ] && exit 0
D="$(cd "$(dirname "$0")/../../.." && pwd)"
source "$D/core/common.sh"; source "$D/core/memory.sh"; mp_adapter gemini
input=$(cat)
cwd=$(mp_path "$(jq -r '.cwd // empty' <<<"$input")"); [ -z "$cwd" ] && cwd="$PWD"
mp_recover_start gemini "$(jq -r '.session_id // empty' <<<"$input")"
mem=$(mp_memory "$cwd"); [ -n "$mem" ] && mem="$mem
$(mp_health_line)"
[ -z "$mem" ] && exit 0
jq -n --arg m "$mem" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$m}}'
