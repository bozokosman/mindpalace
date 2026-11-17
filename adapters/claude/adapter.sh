#!/bin/bash
# Claude Code adapter: runtime functions (sourced by core scripts).
# Transcript: ~/.claude/projects/<dir>/<session-id>.jsonl, one JSON event per line.
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

# Long-lived login: CLAUDE_OAUTH_TOKEN_FILE (e.g. written by `claude setup-token`) lets background calls run
# without an interactive login. All whitespace is stripped from the file content. The value is only put into
# the child's environment: it is never printed, and any echo of it in the CLI's stderr is redacted.
mp_claude_token_load() {
  local f="${CLAUDE_OAUTH_TOKEN_FILE:-}" t
  [ -n "$f" ] || return 0
  f="${f/#\~/$HOME}"
  [ -s "$f" ] || return 0
  t=$(tr -d '[:space:]' <"$f" 2>/dev/null)
  [ -n "$t" ] && export CLAUDE_CODE_OAUTH_TOKEN="$t"
  return 0
}
mp_claude_run() {   # run a command with the token loaded; stderr is passed on with the token redacted
  local ef rc; mp_claude_token_load; ef=$(mktemp)
  "$@" 2>"$ef"; rc=$?
  perl -pe 'BEGIN { $t = $ENV{CLAUDE_CODE_OAUTH_TOKEN} // "" } s/\Q$t\E/[TOKEN]/g if length $t' "$ef" >&2
  rm -f "$ef"; return $rc
}

# Normalized messages: {"role","text","ts"} per line, main conversation only (no subagents, tool output, system notes)
mp_agent_messages() {
  jq -c '
    select((.isSidechain // false) == false) |
    if .type == "user" and (.message.content | type) == "string" then
      select(.message.content | startswith("<") | not) | {role:"user", text:.message.content, ts:.timestamp}
    elif .type == "user" then
      (.message.content[]? | select(.type == "text") | .text | select(startswith("<") | not)) as $t | {role:"user", text:$t, ts:.timestamp}
    elif .type == "assistant" then
      ([.message.content[]? | select(.type == "text") | .text] | join("\n")) as $t | select($t != "") | {role:"assistant", text:$t, ts:.timestamp}
    else empty end' "$1"
}

mp_agent_title() { jq -r 'select(.type=="ai-title") | .aiTitle' "$1" | tail -1; }
mp_agent_session_id() { basename "$1" .jsonl; }
mp_agent_session_cwd() { mp_path "$(jq -r 'select(.cwd) | .cwd' "$1" 2>/dev/null | tail -1)"; }
mp_agent_recent_sessions() {
  find "$CLAUDE_DIR/projects" -maxdepth 2 -name '*.jsonl' -mtime -2 -mmin +10 2>/dev/null
}

# Summarizer: prompt on stdin -> plain text on stdout. Small model, no tools, not saved as a session.
mp_agent_llm() {
  mp_claude_run mp_timeout 180 claude -p --model "${CLAUDE_SUMMARY_MODEL:-haiku}" --effort "${CLAUDE_SUMMARY_EFFORT:-low}" \
    --tools "" --no-session-persistence
}

# Maintainer: prompt on stdin, edits files in the current folder (the vault). Read/Edit/Write/Glob/Grep only,
# no Bash, edits limited to the working folder (acceptEdits), the private folder forbidden, nothing asked, nothing saved.
mp_agent_edit() {
  local pd="${PRIVATE_DIR:-private}"
  mp_claude_run mp_timeout "${MAINTAIN_TIMEOUT:-600}" claude -p --model "${CLAUDE_MAINTAIN_MODEL:-haiku}" --effort low \
    --tools "Read,Edit,Write,Glob,Grep" --permission-mode acceptEdits --permission-prompts none \
    --disallowedTools "Read(./$pd/**)" "Edit(./$pd/**)" --no-session-persistence
}

# Open-session tracking: process name of the tool (for the parent-process walk) and an optional resume footnote.
mp_agent_proc_regex() { echo '^(claude|node|bun)$'; }
mp_agent_resume_hint() { local s; s=$(basename "$1" .jsonl); echo "claude --resume $s"; }
