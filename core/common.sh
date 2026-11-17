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

# Defaults for settings added after v1.0 (an older config file keeps working).
: "${RETRY_WAIT=20 60}"                  # seconds to wait before each retry of a model call (empty = no retries)
: "${EMPTY_RETRY_MIN_CHARS:=8000}"       # long conversation + empty answer = one more try
: "${MAINTAIN:=on}"                      # background maintainer (on|off)
: "${MAINTAIN_AGENT=}"                   # tool whose CLI edits the vault (empty = none)
: "${AUTO_COMMIT:=on}"                   # maintainer commits to the vault's git repo (never pushes)
: "${MAINTAIN_TIMEOUT:=600}"
: "${RECOVER:=on}"                       # recover unsummarized sessions and pending maintenance at session start
: "${LESSON_TRIAL_DAYS:=30}"             # trial rule without a repeat for this long becomes a rule
: "${LESSON_RETIRE_DAYS:=90}"            # rule without a repeat for this long is archived
: "${LESSON_MAX_RULES:=15}"
: "${OPEN_STALE_SEC:=7200}"              # open-session record without a verifiable PID counts as dead after this idle time
: "${CLAUDE_OAUTH_TOKEN_FILE=}"
: "${CLAUDE_MAINTAIN_MODEL:=haiku}"

# Vaults. The config lists names in VAULTS and, per name, VAULT_<name> (folder) and
# PROJECTS_<name> (code folder, may be empty). "-" in a name becomes "_" in the variable.
mp_vkey() { printf '%s' "$1" | tr '-' '_'; }
mp_vault_select() {  # sets VAULT_NAME, VAULT, PROJECTS
  local k; k=$(mp_vkey "$1")
  VAULT_NAME="$1"; eval "VAULT=\${VAULT_$k:-}"; eval "PROJECTS=\${PROJECTS_$k:-}"
}
if [ -z "${VAULTS:-}" ] && [ -n "${VAULT:-}" ]; then   # single-vault config (v1.0/1.1)
  VAULTS=main; DEFAULT_VAULT=main; VAULT_main="$VAULT"; PROJECTS_main="${PROJECTS:-}"
fi
DEFAULT_VAULT="${DEFAULT_VAULT:-${VAULTS%% *}}"
mp_vault_select "$DEFAULT_VAULT"

# Pick the vault for a working directory. Sets MP_MODE: brain (inside a vault or BRAIN_DIRS),
# project (inside <projects>/<name> of some vault) or empty (elsewhere: default vault selected).
mp_resolve() {
  local c="$1/" n d
  MP_MODE=""
  for n in $VAULTS; do mp_vault_select "$n"; [ -n "$VAULT" ] && case "$c" in "$VAULT"/*) MP_MODE=brain; return ;; esac; done
  for n in $VAULTS; do mp_vault_select "$n"; [ -n "$PROJECTS" ] && case "$c" in "$PROJECTS"/*/*) MP_MODE=project; return ;; esac; done
  mp_vault_select "$DEFAULT_VAULT"
  for d in $BRAIN_DIRS; do case "$c" in "$d"/*) MP_MODE=brain ;; esac; done
}

# Project label for a working directory (after mp_resolve): "vault", the project folder name, or the basename.
mp_label() {
  local c="$1" p
  case "$c/" in "$VAULT"/*) echo vault; return ;; esac
  if [ -n "$PROJECTS" ]; then
    case "$c/" in "$PROJECTS"/*/*) p=${c#"$PROJECTS"/}; echo "${p%%/*}"; return ;; esac
  fi
  basename "$c"
}

# ---- portable helpers (no GNU-only flags, no /proc; perl is a required dependency) ----
mp_today() { printf '%s' "${MP_TODAY:-$(date +%F)}"; }            # MP_TODAY lets tests fake the date
mp_now()   { printf '%s' "${MP_NOW:-$(date +%s)}"; }
mp_epoch() { perl -MTime::Local -e '@p=split /-/,$ARGV[0]; print timegm(0,0,12,$p[2],$p[1]-1,$p[0])' "$1" 2>/dev/null; }
mp_days_between() { local a b; a=$(mp_epoch "$1"); b=$(mp_epoch "$2"); echo $(( (${b:-0} - ${a:-0}) / 86400 )); }
mp_date_ago() { perl -MPOSIX -e 'print strftime("%F", localtime(time - 86400*$ARGV[0]))' "$1"; }
mp_mtime() { perl -e 'print((stat($ARGV[0]))[9])' "$1" 2>/dev/null; }
mp_mode()  { perl -e 'printf "%o", (stat($ARGV[0]))[2] & 07777' "$1" 2>/dev/null; }

# Secret scrubbing (applied to model input and output, and to logged error text)
mp_scrub() {
  perl -pe '
    s/(sk-[A-Za-z0-9_-]{16,}|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{30,}|xox[baprs]-[A-Za-z0-9-]{10,})/[SECRET]/g;
    s/((?:password|passwd|token|secret|api[_-]?key)["\x27 ]*[:=][ "\x27]*)[^ "\x27,;]+/$1\[SECRET]/gi;
    s/[A-Za-z0-9+\/_-]{40,}/[LONG-STRING]/g;
  '
}

mp_log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >&2; }

# ---- PID lock that survives crashes and PID reuse ----
# File content: "<pid> <process start time>". A lock is stale when the process is gone, or when the
# same PID now belongs to a process that started at a different time. Where `ps -o lstart=` does not
# work (Git Bash), the start time is empty and the lock also expires after LOCK_MAX_AGE seconds.
mp_proc_start() { LC_ALL=C ps -o lstart= -p "$1" 2>/dev/null | tr -s ' ' | sed -e 's/^ //' -e 's/ $//'; }
mp_pid_alive() {   # $1 pid, $2 recorded start time (may be empty)
  [ -n "$1" ] || return 1
  kill -0 "$1" 2>/dev/null || ps -p "$1" >/dev/null 2>&1 || return 1
  local cur; cur=$(mp_proc_start "$1")
  [ -z "$2" ] || [ -z "$cur" ] || [ "$cur" = "$2" ]
}
mp_lock_acquire() {   # $1 lock file; 0 = got it, 1 = held by a live process
  local f="$1" i pid st age
  for i in 1 2 3; do
    if ( set -C; printf '%s %s\n' "$$" "$(mp_proc_start "$$")" >"$f" ) 2>/dev/null; then return 0; fi
    pid=""; st=""; IFS=' ' read -r pid st <"$f" 2>/dev/null
    if mp_pid_alive "$pid" "$st"; then
      if [ -z "$st" ]; then   # start time unverifiable: do not trust an old lock
        age=$(( $(mp_now) - $(mp_mtime "$f") ))
        [ "$age" -gt "${LOCK_MAX_AGE:-7200}" ] || return 1
      else
        return 1
      fi
    fi
    mp_log "stale lock $(basename "$f") (pid ${pid:-?} gone or reused), taking over"
    rm -f "$f"
  done
  return 1
}
mp_lock_release() {   # only the owner removes it
  local pid=""; IFS=' ' read -r pid _ <"$1" 2>/dev/null
  [ "$pid" = "$$" ] && rm -f "$1"; return 0
}
mp_lock_wait() {   # $1 lock file, $2 max seconds: wait for a live holder
  local n=0; until mp_lock_acquire "$1"; do n=$((n+1)); [ "$n" -gt "${2:-300}" ] && return 1; sleep 1; done
}

# ---- model calls with retries ----
# Permanent failures (login/auth/missing CLI) are never retried.
mp_permanent_error() {
  printf '%s' "$1" | grep -Eiq 'authenticat|unauthori[sz]ed|\b401\b|\b403\b|invalid.{0,20}(token|api key)|oauth|not logged in|please log ?in|/login|credit balance|permission denied|command not found|no such file or directory|unknown option|unrecognized (option|arguments)'
}
# mp_model_run <adapter function> <needs output 1|0> <agent> <prompt>: one model call with retries.
# Retries use the waits in $RETRY_WAIT (seconds, space separated; tests set "0 0"). A timeout is final.
mp_model_run() {
  local fn="$1" needout="$2" agent="$3" prompt="$4" out err rc i=0 waits w n
  out=$(mktemp); err=$(mktemp)
  # shellcheck disable=SC2086
  set -- $RETRY_WAIT; waits=("$@"); n=${#waits[@]}
  while :; do
    ( mp_adapter "$agent" && printf '%s' "$prompt" | "$fn" ) >"$out" 2>"$err"; rc=$?
    if [ "$rc" = 0 ] && { [ "$needout" = 0 ] || [ -s "$out" ]; }; then cat "$out"; rm -f "$out" "$err"; return 0; fi
    mp_log "model call by '$agent' failed (rc=$rc): $(head -c 300 "$err" | mp_scrub | tr '\n' ' ')"
    if [ "$rc" = 124 ] || [ "$rc" = 142 ]; then mp_log "ERROR: model call timed out, not retrying"; rm -f "$out" "$err"; return 1; fi
    if [ "$rc" = 127 ] || mp_permanent_error "$(head -c 4000 "$out" "$err" 2>/dev/null)"; then
      mp_log "ERROR: permanent-looking failure (auth/setup), not retrying"; rm -f "$out" "$err"; return 1
    fi
    if [ "$i" -ge "$n" ]; then mp_log "ERROR: model call failed after $((i + 1)) attempts"; rm -f "$out" "$err"; return 1; fi
    w=${waits[$i]}; i=$((i + 1))
    mp_log "transient failure, retry $i/$n in ${w}s"
    sleep "$w"
  done
}
mp_llm_run()  { mp_model_run mp_agent_llm 1 "$1" "$2"; }    # <agent> <prompt>: summary text on stdout
mp_edit_run() { mp_model_run mp_agent_edit 0 "$1" "$2"; }   # <agent> <prompt>: the agent edits files in the current folder

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
# The summary goes to the vault that owns <cwd> (default vault otherwise).
mp_summarize_bg() {
  mp_detach bash "$MP_HOME/core/summarize.sh" "$1" "$2" "$3" "$4" "${5:-end}"
}

# Start the background maintainer for a vault (no-op when off or unsupported).
mp_maintain_bg() {  # $1 vault name, extra args passed on (e.g. --if-pending)
  [ "$MAINTAIN" = on ] && [ -n "$MAINTAIN_AGENT" ] || return 0
  local n="$1"; shift
  mp_detach bash "$MP_HOME/core/maintain.sh" "$n" "$@"
}

# Session-start recovery, fully in the background: unsummarized sessions (the safety net below)
# and maintenance that is still pending. Returns immediately and prints nothing.
mp_recover_start() {  # $1 agent, $2 current session id
  [ "$RECOVER" = on ] || return 0
  [ -n "$MINDPALACE_DOCTOR" ] && return 0
  mp_detach bash "$MP_HOME/core/recover.sh" "$1" "${2:-}"
}

# At most one line for the session start: ERROR lines of the last 7 days in the hook log.
mp_health_line() {
  [ -f "$STATE/hook.log" ] || return 0
  local since n; since=$(mp_date_ago 7)
  n=$(awk -v s="$since" '$1 >= s && /ERROR/' "$STATE/hook.log" 2>/dev/null | wc -l | tr -d ' ')
  [ "${n:-0}" -gt 0 ] && printf 'MindPalace health: %s error line(s) in the last 7 days in %s. Mention it to the user once.\n' "$n" "$STATE/hook.log"
  return 0
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
