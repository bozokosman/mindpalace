#!/bin/bash
# Agent-agnostic guard rules. Usage (after sourcing common.sh):
#   reason=$(mp_guard_reason "$command")   # empty = allowed, otherwise ask the user
# Each adapter turns a non-empty reason into its own "ask for approval" output.
mp_guard_reason() {
  local cmd="$1" reason="" vname
  check() { [ -z "$reason" ] && grep -qE "$1" <<<"$cmd" && reason="$2"; }

  # Recursive delete (rm -rf, rm -fr, rm -r, rm -R, rm --recursive)
  check '(^|[;&|[:space:]])rm[[:space:]]+([^;&|]*[[:space:]])?-[a-zA-Z]*[rR]|(^|[;&|[:space:]])rm[[:space:]].*--recursive' \
        "Recursive delete (rm -r). Cannot be undone."
  # Windows equivalents
  check '(^|[;&|[:space:]])(rmdir|rd)[[:space:]].*/[sS]|Remove-Item.*-Recurse' "Recursive delete. Cannot be undone."
  # git commands that destroy uncommitted work or history
  check 'git[[:space:]].*reset[[:space:]].*--hard'               "git reset --hard: uncommitted changes are lost."
  check 'git[[:space:]].*clean[[:space:]]+-[a-zA-Z]*f'           "git clean: untracked files are deleted."
  check 'git[[:space:]].*push.*[[:space:]](--force[a-z-]*|-f)([[:space:]]|$)' "git push --force: remote history is overwritten."
  check 'git[[:space:]].*branch[[:space:]]+-D'                   "git branch -D: unmerged branch is deleted."
  check 'git[[:space:]].*(checkout[[:space:]]+--[[:space:]]|restore[[:space:]]+\.)' "Uncommitted changes are discarded."
  # Sensitive files: .env and the vault's private folder
  check '(^|[^a-zA-Z0-9_])\.env([^a-zA-Z0-9_]|$)'                ".env file access (may contain passwords or API keys)."
  vname=$(basename "$VAULT")
  check "($vname|\\\$VAULT)[/\\\\]$PRIVATE_DIR([/\\\\]|[[:space:]]|$)" "The vault's $PRIVATE_DIR/ folder is off limits."

  printf '%s' "$reason"
}
