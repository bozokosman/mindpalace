#!/bin/bash
# Agent-agnostic summarizer. Runs in the background.
# Usage: summarize.sh <agent> <cwd> <transcript> [session_id] [end|compact]
#  - writes into the vault that owns <cwd> (the default vault otherwise)
#  - <agent>'s adapter turns the transcript into normalized messages
#    ({"role":"user|assistant","text":"...","ts":"ISO-8601"} per line, main conversation only)
#  - the SUMMARY_AGENT adapter's CLI writes the summary (any installed agent can summarize any other's sessions)
#  - appends to journal/YYYY-MM-DD.md, rewrites memory/last-session.md,
#    puts note candidates into inbox/, adds one row per session to journal/time.csv
export MINDPALACE_HOOK=1          # recursion lock: hooks of the child CLI call do nothing
source "$(cd "$(dirname "$0")" && pwd)/common.sh"
agent="$1"; cwd="$2"; tr="$3"; sid="${4:-$(basename "$tr" | sed 's/\.[^.]*$//')}"; mode="${5:-end}"
[ -e "$tr" ] || { echo "no transcript: $tr"; exit 1; }
mp_resolve "$cwd"; project=$(mp_label "$cwd")
mkdir -p "$STATE" "$VAULT/journal" "$VAULT/inbox" "$VAULT/memory"
log() { echo "$(date '+%F %T') [$agent:$sid:$mode] $*"; }
today=$(date +%F)
key="$agent-$sid"

# One run per session at a time
if command -v flock >/dev/null; then
  exec 9>"$STATE/$key.lock"; flock 9
else
  until mkdir "$STATE/$key.lockdir" 2>/dev/null; do sleep 1; done
  trap 'rmdir "$STATE/$key.lockdir"' EXIT
fi

mp_adapter "$agent" || exit 1
msgs=$(mp_agent_messages "$tr" 2>/dev/null)
total=$(printf '%s' "$msgs" | grep -c . || true)
ofs_file="$STATE/$key.offset"
ofs=$(cat "$ofs_file" 2>/dev/null || echo 0)

# Secret scrubbing (applied to model input and output)
scrub() {
  perl -pe '
    s/(sk-[A-Za-z0-9_-]{16,}|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{30,}|xox[baprs]-[A-Za-z0-9-]{10,})/[SECRET]/g;
    s/((?:password|passwd|token|secret|api[_-]?key)["\x27 ]*[:=][ "\x27]*)[^ "\x27,;]+/$1\[SECRET]/gi;
    s/[A-Za-z0-9+\/_-]{40,}/[LONG-STRING]/g;
  '
}

conv=$(printf '%s\n' "$msgs" | tail -n +"$((ofs + 1))" | jq -r '
  select(.text != null and .text != "") |
  (if .role == "user" then "USER: " else "ASSISTANT: " end) + .text[0:1500]' 2>/dev/null | scrub | tail -c "$SUMMARY_INPUT_CHARS")

# time.csv (end of session only, whole session): active time = sum of gaps shorter than 10 min
csv="$VAULT/journal/time.csv"
if [ "$mode" = end ]; then
  [ -f "$csv" ] || echo "date,start,project,active_min,messages,session,title,agent" >"$csv"
  read -r start active count < <(printf '%s\n' "$msgs" | jq -r 'select(.ts != null and .ts != "") | .ts' 2>/dev/null |
    jq -Rrs 'split("\n") | map(select(length>0) | sub("\\.[0-9]+";"") | sub("\\+00:00$";"Z") | (try fromdateiso8601 catch empty)) as $t |
      if ($t|length)==0 then "- 0 0" else
      ([range(1; $t|length) | ($t[.] - $t[.-1]) | select(. >= 0 and . < 600)] | add // 0) as $s |
      "\($t[0] | localtime | strftime("%Y-%m-%dT%H:%M")) \(($s/60)|floor) \($t|length)" end')
fi

if [ "${#conv}" -lt "$MIN_CONV_CHARS" ]; then
  log "short conversation (${#conv} chars), summary skipped"
  summary="EMPTY"
else
  prompt="Below is the transcript of an AI coding assistant session (project: $project). Write a short journal entry for long-term memory, in $LANGUAGE.

Rules:
- If nothing has lasting value (greetings, tests, half questions), write ONLY: EMPTY
- The first line must be exactly: TITLE: <title, at most 8 words>
- Then at most 8 bullet points under these headings (skip empty ones, translate the headings to $LANGUAGE):
  - Done
  - Decisions
  - Open / next step
  - Repeated mistake (only if the same mistake happened 2+ times in this session)
  - Learned about the user (preferences, habits)
- At the end, for each lasting fact that will be useful later (technical knowledge, tool, person, decision), write one line:
  NOTE: <target: knowledge|toolbox|profile|decision> | <one-sentence fact>
  Skip NOTE lines if there are none. Do not repeat the journal. At most 5.
- NEVER write passwords, API keys, tokens or .env contents. Do not invent anything that is not in the transcript.
- Keep file paths and concrete names. No filler. Output plain text only, no preamble.

TRANSCRIPT:
$conv"
  summarizer="${SUMMARY_AGENT:-$agent}"
  ( mp_adapter "$summarizer" && printf '%s' "$prompt" | mp_agent_llm ) >"$STATE/$key.out" 2>>"$STATE/hook.log"
  summary=$(scrub <"$STATE/$key.out"); rm -f "$STATE/$key.out"
  if [ -z "$summary" ]; then
    log "ERROR: empty summary from '$summarizer' (model call failed?), offset not advanced"
    summary="EMPTY"; failed=1
  fi
  mp_adapter "$agent"   # restore transcript adapter functions
fi

title=""
if ! grep -qx 'EMPTY' <<<"$(echo "$summary" | head -1 | tr -d '[:space:]*')"; then
  title=$(grep -m1 '^[*]*TITLE:' <<<"$summary" | sed -E 's/^[*]*TITLE:[*]*[[:space:]]*//')
  [ -z "$title" ] && title="(untitled)"
  notes=$(grep -E '^[-* ]*NOTE:' <<<"$summary" | sed -E 's/^[-* ]*NOTE:[[:space:]]*/- [ ] /')
  text=$(grep -v -E -e '^[*]*TITLE:' -e '^[-* ]*NOTE:' <<<"$summary" | sed '/./,$!d')
  tag=" ($agent)"; [ "$mode" = compact ] && tag=" ($agent, before compact)"
  if [ -n "$notes" ]; then   # note candidates go to the inbox, sorted in a later session
    ib="$VAULT/inbox/candidates-$today.md"
    [ -f "$ib" ] || printf -- '---\ntype: knowledge\ndescription: note candidates from %s sessions (written by hook, to be sorted)\nstatus: active\nconfidence: hypothesis\ndate: %s\n---\n# Note candidates %s\nFormat: target | fact. Once sorted, move to the right note and remove from here.\n' "$today" "$today" "$today" >"$ib"
    printf '\n## %s · [%s] %s\n%s\n' "$(date +%H:%M)" "$project" "$title" "$notes" >>"$ib"
  fi
  day="$VAULT/journal/$today.md"
  [ -f "$day" ] || printf -- '---\ntype: journal\ndescription: %s session summaries\nstatus: active\ndate: %s\n---\n# %s\n' "$today" "$today" "$today" >"$day"
  printf '\n### %s · [%s] %s%s\n%s\n' "$(date +%H:%M)" "$project" "$title" "$tag" "$text" >>"$day"
  printf -- '---\ntype: decision\ndescription: summary of the latest session (written by hook)\nstatus: active\ndate: %s\n---\n# Last session\n\n%s · [%s] %s%s\n\n%s\n' \
    "$today" "$(date '+%F %H:%M')" "$project" "$title" "$tag" "$text" >"$VAULT/memory/last-session.md"
  log "written: $day ($title)"
fi

if [ "$mode" = end ] && ! grep -q ",$sid," "$csv" 2>/dev/null; then   # one row per session
  [ -z "$title" ] && type mp_agent_title >/dev/null 2>&1 && title=$(mp_agent_title "$tr" 2>/dev/null)
  title=${title//\"/\'}
  echo "$today,$start,$project,$active,$count,$sid,\"$title\",$agent" >>"$csv"
fi
[ -z "$failed" ] && echo "$total" >"$ofs_file"
exit 0
