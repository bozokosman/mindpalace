#!/bin/bash
# Google Gemini CLI adapter: runtime functions. EXPERIMENTAL (built from docs, not yet tested on a real install).
# Transcript: ~/.gemini/tmp/<project_id>/chats/session-*.jsonl (one record per line; $set/$patch lines are skipped)
#             or legacy session-*.json (one object with .messages[]). Both are handled.
# Verified against gemini-cli chatRecordingService.ts / chatRecordingTypes.ts, 2026-11-02.
GEMINI_DIR="$HOME/.gemini"

mp_agent_messages() {
  jq -c '
    (if type == "object" and has("messages") then .messages[] else . end) |
    select(type == "object") |
    ((.type // .role // "") | tostring) as $r |
    (if $r == "user" then "user" elif ($r == "gemini" or $r == "model" or $r == "assistant") then "assistant" else empty end) as $role |
    ((.content // .parts // .text // "") |
      if type == "string" then . elif type == "array" then (map(if type == "string" then . else (.text // "") end) | join("\n")) else "" end) as $t |
    select($t != "" and ($t | startswith("<") | not) and ($t | startswith("/") | not) and ($t | startswith("?") | not)) |
    {role: $role, text: $t, ts: (.timestamp // .time // null)}' "$1"
}

mp_agent_session_id() {
  local id; id=$(jq -r 'select(type == "object") | .sessionId // empty' "$1" 2>/dev/null | head -1)
  [ -n "$id" ] && echo "$id" || basename "$1" | sed 's/\.[^.]*$//'
}
# Gemini records carry no cwd, so the catch-up safety net cannot place old sessions; summaries come from SessionEnd.
mp_agent_session_cwd() { mp_path "$(jq -r 'select(type == "object") | .cwd // empty' "$1" 2>/dev/null | head -1)"; }
mp_agent_recent_sessions() { find "$GEMINI_DIR/tmp" -path '*chats*' -name 'session-*' -mtime -2 -mmin +10 2>/dev/null; }

# Summarizer: piped stdin is appended to the -p prompt. Read-only approval mode, plain text out.
mp_agent_llm() {
  mp_timeout 240 gemini -p "Follow the instructions in the text below exactly. Do not use any tools." \
    -m "${GEMINI_SUMMARY_MODEL:-flash-lite}" -o text --approval-mode plan
}
