#!/bin/bash
# Standalone summarizer (can also be wired to other AI tools' hooks).
# Usage: summarize.sh <project> <transcript.jsonl> [session_id] [end|compact]
#  - summarizes the part of the transcript not summarized yet, using the claude CLI
#  - appends to journal/YYYY-MM-DD.md and rewrites memory/last-session.md
#  - puts note candidates into inbox/candidates-YYYY-MM-DD.md
#  - on end, adds one row to journal/time.csv (no model needed)
export MINDPALACE_HOOK=1          # recursion lock: hooks of the child claude do not run
source "$(dirname "$0")/common.sh"
project="$1"; tr="$2"; sid="${3:-$(basename "$tr" .jsonl)}"; mode="${4:-end}"
[ -f "$tr" ] || { echo "no transcript: $tr"; exit 1; }
mkdir -p "$STATE" "$VAULT/journal" "$VAULT/inbox" "$VAULT/memory"
log() { echo "$(date '+%F %T') [$sid:$mode] $*"; }
today=$(date +%F)

# One run per session at a time
if command -v flock >/dev/null; then
  exec 9>"$STATE/$sid.lock"; flock 9
else
  until mkdir "$STATE/$sid.lockdir" 2>/dev/null; do sleep 1; done
  trap 'rmdir "$STATE/$sid.lockdir"' EXIT
fi

ofs_file="$STATE/$sid.offset"
ofs=$(cat "$ofs_file" 2>/dev/null || echo 0)
total=$(wc -l <"$tr")

# Secret scrubbing (applied to model input and output)
scrub() {
  perl -pe '
    s/(sk-[A-Za-z0-9_-]{16,}|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,})/[SECRET]/g;
    s/((?:password|passwd|token|secret|api[_-]?key)["\x27 ]*[:=][ "\x27]*)[^ "\x27,;]+/$1\[SECRET]/gi;
    s/[A-Za-z0-9+\/_-]{40,}/[LONG-STRING]/g;
  '
}

# Conversation text: user messages + assistant text (tool output, thinking, system notes excluded)
conv=$(tail -n +"$((ofs + 1))" "$tr" | jq -r '
  select((.isSidechain // false) == false) |
  if .type == "user" and (.message.content | type) == "string" then
    select(.message.content | startswith("<") | not) | "USER: " + .message.content[0:1500]
  elif .type == "user" then
    (.message.content[]? | select(.type == "text") | .text | select(startswith("<") | not) | "USER: " + .[0:1500])
  elif .type == "assistant" then
    (.message.content[]? | select(.type == "text") | "CLAUDE: " + .text[0:1500])
  else empty end' 2>/dev/null | scrub | tail -c "$SUMMARY_INPUT_CHARS")

# time.csv (end of session only, whole transcript): active time = sum of gaps shorter than 10 min
csv="$VAULT/journal/time.csv"
if [ "$mode" = end ]; then
  [ -f "$csv" ] || echo "date,start,project,active_min,messages,session,title" >"$csv"
  read -r start active msgs < <(jq -r 'select((.type=="user" or .type=="assistant") and (.isSidechain//false)==false and .timestamp) | .timestamp' "$tr" |
    jq -Rrs 'split("\n") | map(select(length>0) | sub("\\.[0-9]+Z$";"Z") | fromdateiso8601) as $t |
      if ($t|length)==0 then "- 0 0" else
      ([range(1; $t|length) | ($t[.] - $t[.-1]) | select(. < 600)] | add // 0) as $s |
      "\($t[0] | localtime | strftime("%Y-%m-%dT%H:%M")) \(($s/60)|floor) \($t|length)" end')
fi

if [ "${#conv}" -lt "$MIN_CONV_CHARS" ]; then
  log "short conversation (${#conv} chars), summary skipped"
  summary="EMPTY"
else
  prompt="Below is the transcript of a Claude Code session (project: $project). Write a short journal entry for long-term memory, in $LANGUAGE.

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
- Keep file paths and concrete names. No filler.

TRANSCRIPT:
$conv"
  summary=$(printf '%s' "$prompt" | mp_timeout 180 claude -p --model "$SUMMARY_MODEL" --effort "$SUMMARY_EFFORT" \
           --tools "" --no-session-persistence 2>>"$STATE/hook.log" | scrub)
  if [ -z "$summary" ]; then
    log "ERROR: empty summary (model call failed?), offset not advanced"
    summary="EMPTY"; failed=1
  fi
fi

title=""
if ! grep -qx 'EMPTY' <<<"$(echo "$summary" | head -1 | tr -d '[:space:]*')"; then
  title=$(grep -m1 '^TITLE:' <<<"$summary" | sed 's/^TITLE:[[:space:]]*//')
  [ -z "$title" ] && title="(untitled)"
  notes=$(grep -E '^[-* ]*NOTE:' <<<"$summary" | sed -E 's/^[-* ]*NOTE:[[:space:]]*/- [ ] /')
  text=$(grep -v -E -e '^TITLE:' -e '^[-* ]*NOTE:' <<<"$summary" | sed '/./,$!d')
  if [ -n "$notes" ]; then   # note candidates go to the inbox, sorted in a later session
    ib="$VAULT/inbox/candidates-$today.md"
    [ -f "$ib" ] || printf -- '---\ntype: knowledge\ndescription: note candidates from %s sessions (written by hook, to be sorted)\nstatus: active\nconfidence: hypothesis\ndate: %s\n---\n# Note candidates %s\nFormat: target | fact. Once sorted, move to the right note and remove from here.\n' "$today" "$today" "$today" >"$ib"
    printf '\n## %s · [%s] %s\n%s\n' "$(date +%H:%M)" "$project" "$title" "$notes" >>"$ib"
  fi
  day="$VAULT/journal/$today.md"
  [ -f "$day" ] || printf -- '---\ntype: journal\ndescription: %s session summaries\nstatus: active\ndate: %s\n---\n# %s\n' "$today" "$today" "$today" >"$day"
  tag=""; [ "$mode" = compact ] && tag=" (before compact)"
  printf '\n### %s · [%s] %s%s\n%s\n' "$(date +%H:%M)" "$project" "$title" "$tag" "$text" >>"$day"
  printf -- '---\ntype: decision\ndescription: summary of the latest session (written by hook)\nstatus: active\ndate: %s\n---\n# Last session\n\n%s · [%s] %s%s\n\n%s\n' \
    "$today" "$(date '+%F %H:%M')" "$project" "$title" "$tag" "$text" >"$VAULT/memory/last-session.md"
  log "written: $day ($title)"
fi

if [ "$mode" = end ] && ! grep -q ",$sid," "$csv" 2>/dev/null; then   # one row per session
  [ -z "$title" ] && title=$(jq -r 'select(.type=="ai-title") | .aiTitle' "$tr" 2>/dev/null | tail -1)
  title=${title//\"/\'}
  echo "$today,$start,$project,$active,$msgs,$sid,\"$title\"" >>"$csv"
fi
[ -z "$failed" ] && echo "$total" >"$ofs_file"
exit 0
