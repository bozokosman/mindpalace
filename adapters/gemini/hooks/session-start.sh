#!/bin/bash
# Gemini CLI SessionStart hook: stdout must be exactly one JSON object.
[ -n "$MINDPALACE_HOOK" ] && exit 0
D="$(cd "$(dirname "$0")/../../.." && pwd)"
source "$D/core/common.sh"; source "$D/core/sessions.sh"; mp_adapter gemini
input=$(cat)
cwd=$(mp_path "$(jq -r '.cwd // empty' <<<"$input")"); [ -z "$cwd" ] && cwd="$PWD"
tr=$(mp_path "$(jq -r '.transcript_path // empty' <<<"$input")")
mp_session_context gemini "$cwd" "$(jq -r '.session_id // empty' <<<"$input")" "$tr" "$(jq -r '.source // empty' <<<"$input")"
[ -z "$MP_CTX_MEM$MP_CTX_WARN" ] && exit 0
jq -n --arg m "$(mp_session_text)" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$m}}'
