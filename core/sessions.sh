#!/bin/bash
# Session start/end bookkeeping, tool-neutral. Source after common.sh (and an adapter for the tool in use).
#  - mp_open_start: records the session as "open"; if an earlier session in the SAME folder was cut off
#    (record without a clean end), prints a short warning block once.
#  - mp_open_end: a real SessionEnd deletes the record. Compaction does not.
#  - mp_session_context: memory + warning + health line, for adapters to wrap in their hook output.
# Record: $STATE/open/<agent>-<session id>, lines: cwd, transcript, start epoch, tool PID, PID start time.
# No /proc: the tool's PID is found by walking parent processes with `ps`; where that is not possible
# (Git Bash) a record counts as dead after OPEN_STALE_SEC without transcript activity.
source "$(dirname "${BASH_SOURCE[0]}")/memory.sh"

mp_open_dir() { printf '%s/open' "$STATE"; }
mp_safe_id()  { case "$1" in ""|*/*|*..*|*\\*) return 1 ;; esac; }

# Find the tool's own process: walk up from this hook. The adapter names it (mp_agent_proc_regex, a grep -E pattern).
mp_find_tool_pid() {
  type mp_agent_proc_regex >/dev/null 2>&1 || return 0
  local re p i c; re=$(mp_agent_proc_regex); p=$PPID
  for i in 1 2 3 4 5 6; do
    [ -n "$p" ] && [ "$p" -gt 1 ] 2>/dev/null || return 0
    c=$(ps -o comm= -p "$p" 2>/dev/null | sed 's#.*[/\\]##; s/\.exe$//')
    if [ -n "$c" ] && printf '%s' "$c" | grep -Eq "$re"; then printf '%s' "$p"; return 0; fi
    p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
  done
}

mp_open_alive() {  # record file -> 0 if its session may still be running
  local f="$1" kc ktr ks kpid kst age
  { IFS= read -r kc; IFS= read -r ktr; IFS= read -r ks; IFS= read -r kpid; IFS= read -r kst; } <"$f"
  if [ -n "$kpid" ]; then mp_pid_alive "$kpid" "$kst"; return; fi
  [ -f "$ktr" ] || return 1
  age=$(( $(mp_now) - $(mp_mtime "$ktr") )); [ "$age" -lt "$OPEN_STALE_SEC" ]
}

mp_line() { local t; t=$(printf '%s' "$1" | tr -s '[:space:]' ' ' | mp_scrub); t=${t# }; t=${t% }; if [ "${#t}" -gt 300 ]; then printf '%s...' "${t:0:300}"; else printf '%s' "$t"; fi; }

# mp_open_start <agent> <cwd> <session id> <transcript> <source: startup|resume|clear|compact>
mp_open_start() {
  local agent="$1" cwd="$2" sid="$3" tr="$4" src="$5" dir f key own found="" found_tr="" found_agent kc ktr pid msgs ask last when hint
  mp_safe_id "$sid" || return 0
  [ "$src" = compact ] && return 0                       # same session continues; nothing changed
  dir=$(mp_open_dir); key="$agent-$sid"; own="$dir/$key"
  mkdir -p "$dir"
  find "$dir" -type f -mtime +7 -exec rm -f {} + 2>/dev/null   # records older than 7 days are dropped
  for f in "$dir"/*; do
    [ -f "$f" ] && [ "$f" != "$own" ] || continue
    { IFS= read -r kc; IFS= read -r ktr; } <"$f"
    [ "$kc" = "$cwd" ] || continue
    mp_open_alive "$f" && continue                       # a parallel session that is still running
    if [ -z "$found_tr" ] || [ "$ktr" -nt "$found_tr" ]; then found_tr="$ktr"; found_agent=$(basename "$f"); found_agent=${found_agent%%-*}; fi
    found="$found $f"
  done
  pid=$(mp_find_tool_pid)
  printf '%s\n%s\n%s\n%s\n%s\n' "$cwd" "$tr" "$(mp_now)" "$pid" "${pid:+$(mp_proc_start "$pid")}" >"$own"
  [ -n "$found" ] || return 0
  rm -f $found                                          # one warning only: consumed now
  [ "$src" = resume ] && return 0                       # the user is already continuing
  [ -f "$found_tr" ] || return 0
  ( mp_adapter "$found_agent" 2>/dev/null && type mp_agent_messages >/dev/null 2>&1 ) || return 0
  msgs=$( mp_adapter "$found_agent"; mp_agent_messages "$found_tr" 2>/dev/null )
  ask=$(printf '%s\n' "$msgs" | jq -r 'select(.role=="user") | .text | gsub("\\s+";" ")' 2>/dev/null | tail -1)
  last=$(printf '%s\n' "$msgs" | jq -r 'select(.role=="assistant") | .text | gsub("\\s+";" ")' 2>/dev/null | tail -1)
  [ -n "$ask" ] || return 0                             # nothing was requested: nothing to resume
  when=$(perl -MPOSIX -e 'print strftime("%F %H:%M", localtime((stat($ARGV[0]))[9]))' "$found_tr")
  echo "## Unfinished session"
  echo "A previous session in this folder did not end cleanly (last activity: $when)."
  echo "- Last request: $(mp_line "$ask")"
  echo "- Last state: $(mp_line "${last:-(no assistant reply found)}")"
  echo "- Transcript: $found_tr"
  echo "Suggest it to the user yourself: \"The previous session was cut off ($when). Shall I continue?\" Do not continue without their approval."
  echo "If they say \"continue\": read the output of \`bash \"$MP_HOME/core/session-digest.sh\" $found_agent \"$found_tr\"\` (the last ~50 messages), then pick up where it stopped."
  hint=$( mp_adapter "$found_agent"; type mp_agent_resume_hint >/dev/null 2>&1 && mp_agent_resume_hint "$found_tr" )
  [ -n "$hint" ] && echo "(Footnote, only if they want the full conversation back: $hint)"
  return 0
}

# mp_open_end <agent> <session id>: call on a real session end only (never on compaction).
mp_open_end() { mp_safe_id "$2" && rm -f "$(mp_open_dir)/$1-$2"; return 0; }

# Fills MP_CTX_MEM (memory), MP_CTX_WARN (unfinished session) and MP_CTX_HEALTH (one line, only when something else is printed).
mp_session_context() {  # <agent> <cwd> <session id> <transcript> <source>
  mp_resolve "$2"
  mp_recover_start "$1" "$3"
  MP_CTX_MEM=$(mp_memory "$2")
  MP_CTX_WARN=$(mp_open_start "$1" "$2" "$3" "$4" "$5")
  MP_CTX_HEALTH=""
  if [ -n "$MP_CTX_MEM$MP_CTX_WARN" ]; then MP_CTX_HEALTH=$(mp_health_line); fi
}
mp_session_text() {  # all parts joined by blank lines
  local out="$MP_CTX_MEM" p
  for p in "$MP_CTX_WARN" "$MP_CTX_HEALTH"; do [ -n "$p" ] && out="${out:+$out
}
$p"; done
  [ -n "$out" ] && printf '%s\n' "$out"; return 0
}
