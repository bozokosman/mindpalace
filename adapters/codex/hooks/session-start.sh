#!/bin/bash
# Codex SessionStart hook. Emits {"hookSpecificOutput":{"additionalContext":...}}.
# Codex has no @import in AGENTS.md, so the shared rules are injected here too.
# Codex caps this context at ~2500 tokens, so the total is kept under 9000 characters.
[ -n "$MINDPALACE_HOOK" ] && exit 0
D="$(cd "$(dirname "$0")/../../.." && pwd)"
source "$D/core/common.sh"; source "$D/core/memory.sh"; mp_adapter codex
input=$(cat)
cwd=$(mp_path "$(jq -r '.cwd // empty' <<<"$input")"); [ -z "$cwd" ] && cwd="$PWD"
mp_recover_start codex "$(jq -r '.session_id // empty' <<<"$input")"
mem=$(mp_memory "$cwd"); [ -n "$mem" ] && mem="$mem
$(mp_health_line)"
[ -z "$mem" ] && exit 0
ctx=$( { mp_body "$VAULT/RULES.md"; echo; printf '%s\n' "$mem"; } | head -c 9000)
jq -n --arg m "$ctx" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$m}}'
