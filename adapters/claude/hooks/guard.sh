#!/bin/bash
# Claude Code PreToolUse (Bash) hook: returns "ask" for risky commands. Never blocks.
D="$(cd "$(dirname "$0")/../../.." && pwd)"
source "$D/core/common.sh"; source "$D/core/guard-rules.sh"
cmd=$(jq -r '.tool_input.command // ""')
[ -z "$cmd" ] && exit 0
reason=$(mp_guard_reason "$cmd")
[ -z "$reason" ] && exit 0
jq -n --arg r "MindPalace guard: $reason" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$r}}'
