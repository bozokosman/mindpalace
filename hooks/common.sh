#!/bin/bash
# Shared helpers, sourced by every MindPalace hook. Works on Linux, macOS (bash 3.2+)
# and Windows (Git Bash, which Claude Code on Windows already requires).
MP_HOME="${MP_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

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

# Normalize a path from Claude Code's hook JSON (C:\Users\x on Windows) to this shell's form.
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

# Run a command detached from Claude Code so it never delays exit.
mp_detach() {
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
