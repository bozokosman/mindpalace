#!/bin/bash
# OpenAI Codex CLI adapter: runtime functions. EXPERIMENTAL (built from docs, not yet tested on a real install).
# Transcript: ~/.codex/sessions/YYYY/MM/DD/rollout-<ts>-<id>.jsonl, lines {"timestamp","type","payload"}.
CODEX_DIR="${CODEX_HOME:-$HOME/.codex}"

# Normalized messages. User messages injected by Codex (<environment_context>, <user_instructions>, AGENTS.md) are skipped.
# Verified against codex-rs protocol types (models.rs ContentItem, protocol.rs SessionMeta), 2026-11-02.
mp_agent_messages() {
  jq -c '
    select(.type == "response_item" and .payload.type == "message" and (.payload.role == "user" or .payload.role == "assistant")) |
    ([.payload.content[]? | select(.type == "input_text" or .type == "output_text" or .type == "text") | .text] | join("\n")) as $t |
    select($t != "" and ($t | startswith("<") | not) and ($t | startswith("# AGENTS.md") | not)) |
    {role: .payload.role, text: $t, ts: .timestamp}' "$1"
}

mp_agent_session_id() {
  local id; id=$(jq -r 'select(.type == "session_meta") | .payload.id // empty' "$1" 2>/dev/null | head -1)
  [ -n "$id" ] && echo "$id" || basename "$1" .jsonl
}
mp_agent_session_cwd() { mp_path "$(jq -r 'select(.type == "session_meta" or .type == "turn_context") | .payload.cwd // empty' "$1" 2>/dev/null | tail -1)"; }
mp_agent_recent_sessions() { find "$CODEX_DIR/sessions" -name 'rollout-*.jsonl' -mtime -2 -mmin +10 2>/dev/null; }

# Summarizer: prompt on stdin -> final message on stdout. Ephemeral (no session saved), read-only sandbox.
mp_agent_llm() {
  local m=(); [ -n "${CODEX_SUMMARY_MODEL:-}" ] && m=(-m "$CODEX_SUMMARY_MODEL")
  mp_timeout 240 codex exec - --ephemeral --skip-git-repo-check --sandbox read-only "${m[@]}"
}

# Maintainer: UNSUPPORTED (no mp_agent_edit). `codex exec --sandbox workspace-write` could edit the vault, but it
# also allows shell commands and reading every file, so the private folder cannot be kept off limits. The
# maintainer therefore stays off when Codex is the only tool; another connected tool can run it.
