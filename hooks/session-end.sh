#!/bin/bash
# SessionEnd / PreCompact entry point. Reads the hook JSON from stdin and starts the
# summary in the background, so Claude Code never waits for it.
# Usage (settings.json): session-end.sh end | session-end.sh compact
[ -n "$MINDPALACE_HOOK" ] && exit 0
source "$(dirname "$0")/common.sh"
mkdir -p "$STATE"

input=$(cat)
cwd=$(mp_path "$(jq -r '.cwd // empty' <<<"$input")")
tr=$(mp_path "$(jq -r '.transcript_path // empty' <<<"$input")")
sid=$(jq -r '.session_id // empty' <<<"$input")
[ -f "$tr" ] || exit 0

mp_detach bash "$MP_HOME/summarize.sh" "$(mp_label "$cwd")" "$tr" "$sid" "${1:-end}"
exit 0
