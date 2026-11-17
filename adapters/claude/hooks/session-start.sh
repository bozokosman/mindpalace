#!/bin/bash
# Claude Code SessionStart hook: stdout becomes context.
[ -n "$MINDPALACE_HOOK" ] && exit 0
D="$(cd "$(dirname "$0")/../../.." && pwd)"
source "$D/core/common.sh"; source "$D/core/sessions.sh"; mp_adapter claude
input=$(cat)
cwd=$(mp_path "$(jq -r '.cwd // empty' <<<"$input")"); [ -z "$cwd" ] && cwd="$PWD"
tr=$(mp_path "$(jq -r '.transcript_path // empty' <<<"$input")")
mp_session_context claude "$cwd" "$(jq -r '.session_id // empty' <<<"$input")" "$tr" "$(jq -r '.source // empty' <<<"$input")"
mp_session_text
exit 0
