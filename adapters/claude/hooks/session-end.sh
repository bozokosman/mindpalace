#!/bin/bash
# Claude Code SessionEnd / PreCompact hook. Usage: session-end.sh end|compact
[ -n "$MINDPALACE_HOOK" ] && exit 0
D="$(cd "$(dirname "$0")/../../.." && pwd)"
source "$D/core/common.sh"
input=$(cat)
cwd=$(mp_path "$(jq -r '.cwd // empty' <<<"$input")")
tr=$(mp_path "$(jq -r '.transcript_path // empty' <<<"$input")")
sid=$(jq -r '.session_id // empty' <<<"$input")
[ -f "$tr" ] || exit 0
mp_summarize_bg claude "$cwd" "$tr" "$sid" "${1:-end}"
exit 0
