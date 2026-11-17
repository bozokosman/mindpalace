#!/bin/bash
# Codex SessionEnd / PreCompact hook. Usage: session-end.sh end|compact
[ -n "$MINDPALACE_HOOK" ] && exit 0
D="$(cd "$(dirname "$0")/../../.." && pwd)"
source "$D/core/common.sh"
input=$(cat)
cwd=$(mp_path "$(jq -r '.cwd // empty' <<<"$input")")
tr=$(mp_path "$(jq -r '.transcript_path // empty' <<<"$input")")
sid=$(jq -r '.session_id // empty' <<<"$input")
source "$D/core/sessions.sh"
[ "${1:-end}" = end ] && mp_open_end codex "$sid"   # a real end clears the open-session record; compaction does not
if [ ! -f "$tr" ] && [ -n "$sid" ]; then   # transcript_path can be null
  tr=$(find "${CODEX_HOME:-$HOME/.codex}/sessions" -name "rollout-*${sid}*.jsonl" 2>/dev/null | head -1)
fi
[ -f "$tr" ] || exit 0
mp_summarize_bg codex "$cwd" "$tr" "$sid" "${1:-end}"
exit 0
