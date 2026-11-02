#!/bin/bash
# Gemini CLI BeforeTool (shell) hook. Gemini hooks cannot "ask", so risky commands are denied
# with a message telling the agent to get the user's OK and let the user run it.
D="$(cd "$(dirname "$0")/../../.." && pwd)"
source "$D/core/common.sh"; source "$D/core/guard-rules.sh"
cmd=$(jq -r '.tool_input.command // .tool_input.cmd // ""')
[ -z "$cmd" ] && exit 0
reason=$(mp_guard_reason "$cmd")
[ -z "$reason" ] && exit 0
jq -n --arg r "MindPalace guard: $reason Blocked. Explain to the user what this command does and ask them to run it themselves if they agree." \
  '{decision:"deny", reason:$r}'
