#!/bin/bash
# Agent-agnostic memory text for session start. Usage (after sourcing common.sh):
#   mp_memory "$cwd"    # prints memory for this location (nothing outside vault/projects)
#  - inside the vault (or BRAIN_DIRS): profile, last session, open items, INDEX, recent journal
#  - inside $PROJECTS/<name>: that project's note + its recent journal entries

mp_body() { [ -f "$1" ] && awk 'NR==1&&/^---$/{f=1;next} f&&/^---$/{f=0;next} !f' "$1"; }  # strip frontmatter

mp_clip() {  # $1 file, $2 chars: never cut silently, say where the rest is
  local t; t=$(mp_body "$1"); [ -z "$t" ] && return
  if [ "${#t}" -gt "$2" ]; then
    printf '%s\n…(truncated: loaded %s of %s characters, read %s for the rest)\n' "${t:0:$2}" "$2" "${#t}" "$1"
  else printf '%s\n' "$t"; fi
}

mp_recent_journal() {  # $1: project filter (empty = all), $2: chars
  local files f; files=$(ls -1 "$VAULT"/journal/20*.md 2>/dev/null | sort | tail -2)
  [ -z "$files" ] && return
  if [ -n "$1" ]; then
    # shellcheck disable=SC2086
    awk -v p="[$1]" '/^### /{keep=index($0,p)>0} keep' $files
  else
    for f in $files; do mp_body "$f"; done
  fi | tail -c "$2"
}

mp_memory() {
  local cwd="$1" mode="" project="" d n
  case "$cwd/" in
    "$VAULT"/*) mode=brain ;;
    "$PROJECTS"/*/*) mode=project; project=$(mp_label "$cwd") ;;
  esac
  for d in $BRAIN_DIRS; do case "$cwd/" in "$d"/*) mode=brain ;; esac; done

  case "$mode" in
    brain)
      {
        echo "# MindPalace memory (loaded at session start)"
        echo; mp_clip "$VAULT/memory/profile.md" 1500
        echo; mp_clip "$VAULT/memory/last-session.md" 1500
        echo; mp_clip "$VAULT/memory/open-items.md" 1000
        echo; mp_clip "$VAULT/INDEX.md" 2500
        echo; echo "## Recent journal entries"; mp_recent_journal "" 1500
        n=$(cat "$VAULT"/inbox/*.md 2>/dev/null | grep -c '^- \[ \]')
        [ "${n:-0}" -gt 0 ] && echo && echo "📥 $n note candidates are waiting in inbox/. Remind $USER_NAME to sort them at a good moment."
      } | head -c "$BUDGET_BRAIN"
      ;;
    project)
      {
        echo "# Project memory: $project (loaded at session start)"
        if [ -f "$VAULT/projects/$project.md" ]; then
          echo; mp_body "$VAULT/projects/$project.md" | head -c 2000
        else
          echo; echo "No note yet. Create $VAULT/projects/$project.md (see $VAULT/RULES.md) once the project has a clear goal."
        fi
        echo; echo "## Recent journal entries for this project"; mp_recent_journal "$project" 1200
      } | head -c "$BUDGET_PROJECT"
      ;;
  esac
}
