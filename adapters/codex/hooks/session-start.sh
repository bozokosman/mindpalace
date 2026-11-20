#!/bin/bash
# Codex SessionStart hook. Emits {"hookSpecificOutput":{"additionalContext":...}}.
# Codex has no @import in AGENTS.md, so the shared rules are injected here too.
# Codex caps this context at ~2500 tokens, so the total is kept under 9000 characters
# (the unfinished-session warning is kept whole; the rules and memory are trimmed to fit).
[ -n "$MINDPALACE_HOOK" ] && exit 0
D="$(cd "$(dirname "$0")/../../.." && pwd)"
source "$D/core/common.sh"; source "$D/core/sessions.sh"; mp_adapter codex
input=$(cat)
cwd=$(mp_path "$(jq -r '.cwd // empty' <<<"$input")"); [ -z "$cwd" ] && cwd="$PWD"
tr=$(mp_path "$(jq -r '.transcript_path // empty' <<<"$input")")
mp_session_context codex "$cwd" "$(jq -r '.session_id // empty' <<<"$input")" "$tr" "$(jq -r '.source // empty' <<<"$input")"
[ -z "$MP_CTX_MEM$MP_CTX_WARN" ] && exit 0
extra="$MP_CTX_STALE"; [ -n "$MP_CTX_WARN" ] && extra="${extra:+$extra
}$MP_CTX_WARN"; [ -n "$MP_CTX_HEALTH" ] && extra="${extra:+$extra
}$MP_CTX_HEALTH"
room=$((9000 - ${#extra} - 2)); [ "$room" -lt 0 ] && room=0
base=""; [ -n "$MP_CTX_MEM" ] && base=$( { mp_body "$VAULT/RULES.md"; echo; printf '%s\n' "$MP_CTX_MEM"; } | head -c "$room")
ctx="$base"; [ -n "$extra" ] && ctx="${ctx:+$ctx

}$extra"
ctx=$(printf '%s' "$ctx" | head -c 9000)
jq -n --arg m "$ctx" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$m}}'
