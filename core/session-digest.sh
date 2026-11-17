#!/bin/bash
# Short plain-text digest of the end of a transcript, for picking up an unfinished session.
# Usage: session-digest.sh <agent> <transcript> [N=50]
# Uses the adapter's normalized messages ({role,text,ts}); tool output and file contents are never printed. At most ~4000 characters.
export MINDPALACE_HOOK=1
source "$(cd "$(dirname "$0")" && pwd)/common.sh"
agent="$1"; tr="$2"; n="${3:-50}"
[ -f "$tr" ] || { echo "transcript not found"; exit 1; }
mp_adapter "$agent" || exit 1
mp_agent_messages "$tr" 2>/dev/null | tail -n "$n" | jq -r '
  select(.text != null and .text != "") |
  (if .role == "user" then "USER: " else "ASSISTANT: " end) + (.text | gsub("\\s+"; " ") | if length > 400 then .[0:400] + "..." else . end)' |
  mp_scrub | awk '{ l[NR]=$0 } END { t=0; s=NR+1; for (i=NR;i>=1;i--) { t+=length(l[i])+1; if (t>4000) break; s=i } for (i=s;i<=NR;i++) print l[i] }'
