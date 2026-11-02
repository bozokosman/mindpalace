#!/bin/bash
# SessionStart: loads memory into context based on where Claude Code was started (stdout -> context).
#  - inside the vault (or BRAIN_DIRS): profile, last session, open items, INDEX, recent journal
#  - inside $PROJECTS/<name>: only that project's note + its recent journal entries
#  - anywhere else: nothing
[ -n "$MINDPALACE_HOOK" ] && exit 0
source "$(dirname "$0")/common.sh"

input=$(cat)
cwd=$(mp_path "$(jq -r '.cwd // empty' <<<"$input")"); [ -z "$cwd" ] && cwd="$PWD"

body() { [ -f "$1" ] && awk 'NR==1&&/^---$/{f=1;next} f&&/^---$/{f=0;next} !f' "$1"; }  # strip frontmatter
clip() {  # $1 file, $2 chars: never cut silently, say where the rest is
  local t; t=$(body "$1"); [ -z "$t" ] && return
  if [ "${#t}" -gt "$2" ]; then
    printf '%s\n…(truncated: loaded %s of %s characters, read %s for the rest)\n' "${t:0:$2}" "$2" "${#t}" "$1"
  else printf '%s\n' "$t"; fi
}
recent_journal() {  # $1: project filter (empty = all), $2: chars
  local files; files=$(ls -1 "$VAULT"/journal/20*.md 2>/dev/null | sort | tail -2)
  [ -z "$files" ] && return
  if [ -n "$1" ]; then
    # shellcheck disable=SC2086
    awk -v p="[$1]" '/^### /{keep=index($0,p)>0} keep' $files
  else
    for f in $files; do body "$f"; done
  fi | tail -c "$2"
}

# Safety net: if a window was closed without SessionEnd, summarize unsummarized sessions
# from the last 2 days in the background (max 3; idle for 10 min = finished).
sid_now=$(jq -r '.session_id // empty' <<<"$input")
mkdir -p "$STATE"
[ -z "$MINDPALACE_DOCTOR" ] && find "$CLAUDE_DIR/projects" -maxdepth 2 -name '*.jsonl' -mtime -2 -mmin +10 2>/dev/null |
while read -r t; do
  s=$(basename "$t" .jsonl); [ "$s" = "$sid_now" ] && continue
  ofs=$(cat "$STATE/$s.offset" 2>/dev/null || echo 0)
  [ "$(wc -l <"$t")" -gt "$((ofs + 5))" ] || continue      # nothing new
  c=$(mp_path "$(jq -r 'select(.cwd) | .cwd' "$t" 2>/dev/null | tail -1)"); [ -z "$c" ] && continue
  echo "$(mp_label "$c")|$t|$s"
done | head -3 | while IFS='|' read -r p t s; do
  mp_detach bash "$MP_HOME/summarize.sh" "$p" "$t" "$s" end
done

mode=""; project=""
case "$cwd/" in
  "$VAULT"/*) mode=brain ;;
  "$PROJECTS"/*/*) mode=project; project=$(mp_label "$cwd") ;;
esac
for d in $BRAIN_DIRS; do case "$cwd/" in "$d"/*) mode=brain ;; esac; done

case "$mode" in
  brain)
    {
      echo "# MindPalace memory (loaded by the SessionStart hook)"
      echo; clip "$VAULT/memory/profile.md" 1500
      echo; clip "$VAULT/memory/last-session.md" 1500
      echo; clip "$VAULT/memory/open-items.md" 1000
      echo; clip "$VAULT/INDEX.md" 2500
      echo; echo "## Recent journal entries"; recent_journal "" 1500
      n=$(cat "$VAULT"/inbox/*.md 2>/dev/null | grep -c '^- \[ \]')
      [ "${n:-0}" -gt 0 ] && echo && echo "📥 $n note candidates are waiting in inbox/. Remind $USER_NAME to sort them at a good moment."
    } | head -c "$BUDGET_BRAIN"
    ;;
  project)
    {
      echo "# Project memory: $project (loaded by the SessionStart hook)"
      if [ -f "$VAULT/projects/$project.md" ]; then
        echo; body "$VAULT/projects/$project.md" | head -c 2000
      else
        echo; echo "No note yet. Create $VAULT/projects/$project.md (see $VAULT/RULES.md) once the project has a clear goal."
      fi
      echo; echo "## Recent journal entries for this project"; recent_journal "$project" 1200
    } | head -c "$BUDGET_PROJECT"
    ;;
esac
exit 0
