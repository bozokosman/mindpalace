#!/bin/bash
# Shared helpers, sourced by every MindPalace script. Agent-agnostic.
# Works on Linux, macOS (bash 3.2+) and Windows (Git Bash).
# Installed layout: $MP_HOME/{core,adapters/<agent>}/, $MP_HOME/mindpalace.conf, $MP_HOME/state/
MP_HOME="${MP_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

case "$(uname -s)" in
  Linux*)  MP_OS=linux ;;
  Darwin*) MP_OS=macos ;;
  MINGW*|MSYS*|CYGWIN*) MP_OS=windows ;;
  *) MP_OS=other ;;
esac

if [ "$MP_OS" = windows ]; then
  # jq.exe may print CRLF; strip it so bash comparisons work.
  jq() { command jq "$@" | tr -d '\r'; }
fi

# Normalize a path coming from an agent's JSON (C:\Users\x on Windows) to this shell's form.
mp_path() {
  if [ "$MP_OS" = windows ] && [ -n "$1" ] && command -v cygpath >/dev/null; then
    cygpath -u "$1"
  else
    printf '%s' "$1"
  fi
}

# shellcheck source=/dev/null
source "$MP_HOME/mindpalace.conf" || exit 0

# Project label for a working directory: "vault", the project folder name, or the basename.
mp_label() {
  local c="$1" p
  case "$c/" in
    "$VAULT"/*) echo vault; return ;;
    "$PROJECTS"/*/*) p=${c#"$PROJECTS"/}; echo "${p%%/*}"; return ;;
  esac
  basename "$c"
}

# Run a command detached from the agent so it never delays exit.
mp_detach() {
  mkdir -p "$STATE"
  if command -v setsid >/dev/null; then
    setsid nohup "$@" >>"$STATE/hook.log" 2>&1 </dev/null &
  else
    nohup "$@" >>"$STATE/hook.log" 2>&1 </dev/null &
  fi
}

# timeout SECONDS CMD...  (GNU timeout is missing on stock macOS)
mp_timeout() {
  local s="$1"; shift
  if command -v timeout >/dev/null; then timeout "$s" "$@"
  elif command -v gtimeout >/dev/null; then gtimeout "$s" "$@"
  else perl -e 'alarm shift; exec @ARGV' "$s" "$@"
  fi
}

# Load an adapter's functions: mp_adapter <agent>
mp_adapter() {
  local f="$MP_HOME/adapters/$1/adapter.sh"
  [ -f "$f" ] || { echo "unknown agent adapter: $1" >&2; return 1; }
  # shellcheck source=/dev/null
  source "$f"
}

# Start a background summary: mp_summarize_bg <agent> <cwd> <transcript> <session_id> <end|compact>
mp_summarize_bg() {
  mp_detach bash "$MP_HOME/core/summarize.sh" "$1" "$(mp_label "$2")" "$3" "$4" "${5:-end}"
}

# Safety net: summarize this agent's recent sessions that never got a session-end
# (window closed, crash). Max 3 per start; idle for 10 min = finished.
# Needs adapter functions: mp_agent_recent_sessions, mp_agent_session_cwd, mp_agent_session_id
mp_catchup() {
  local agent="$1" now="$2" t s c ofs n
  [ -n "$MINDPALACE_DOCTOR" ] && return
  type mp_agent_recent_sessions >/dev/null 2>&1 || return
  mkdir -p "$STATE"
  mp_agent_recent_sessions 2>/dev/null | while read -r t; do
    [ -f "$STATE/.installed" ] && [ ! "$t" -nt "$STATE/.installed" ] && continue   # older than the install
    s=$(mp_agent_session_id "$t"); [ -z "$s" ] || [ "$s" = "$now" ] && continue
    ofs=$(cat "$STATE/$agent-$s.offset" 2>/dev/null || echo 0)
    n=$(mp_agent_messages "$t" 2>/dev/null | grep -c . || true)
    [ "${n:-0}" -gt "$((ofs + 2))" ] || continue
    c=$(mp_agent_session_cwd "$t"); [ -z "$c" ] && continue
    printf '%s|%s|%s\n' "$c" "$t" "$s"
  done | head -3 | while IFS='|' read -r c t s; do
    mp_summarize_bg "$agent" "$c" "$t" "$s" end
  done
}
