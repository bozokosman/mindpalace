#!/bin/bash
# Maintainer (optional). Runs in the background after a session summary, or from session-start recovery.
# Usage: maintain.sh <vault_name> [--if-pending] [--dry]
#  1. an AI agent with file-edit rights (adapter function mp_agent_edit) sorts inbox candidates into the vault,
#     updates SUMMARY.md and agent/notes.md, counts corrections in memory/mistakes.md
#  2. core/lessons.sh applies the trial/rule/retire date rules (deterministic, no model)
#  3. fully sorted candidate files move to archive/
#  4. if the vault is a git repo and AUTO_COMMIT=on, the changes are committed. NEVER pushed.
# Settings: MAINTAIN=on|off, MAINTAIN_AGENT, AUTO_COMMIT, MAINTAIN_TIMEOUT. Tools without a safe edit mode are "unsupported".
export MINDPALACE_HOOK=1
source "$(cd "$(dirname "$0")" && pwd)/common.sh"
name="${1:-$DEFAULT_VAULT}"; shift
ifpending=0; dry=0
for a in "$@"; do case "$a" in --if-pending) ifpending=1 ;; --dry) dry=1 ;; esac; done
log() { mp_log "[maintain:$name] $*"; }
[ "$MAINTAIN" = on ] || exit 0
mp_vault_select "$name"
[ -d "$VAULT" ] || { log "ERROR: vault folder missing: $VAULT"; exit 1; }
agent="$MAINTAIN_AGENT"
[ -n "$agent" ] || { log "no MAINTAIN_AGENT configured, skipped"; exit 0; }
mp_adapter "$agent" || exit 1
type mp_agent_edit >/dev/null 2>&1 || { log "unsupported: $agent has no safe file-edit mode, maintainer stays off"; exit 0; }
mkdir -p "$STATE"
lock="$STATE/maintain-$name.pid"; again="$STATE/maintain-$name.again"
if ! mp_lock_acquire "$lock"; then : >"$again"; log "another maintainer is running, will run once more after it"; exit 0; fi
trap 'mp_lock_release "$lock"' EXIT
cd "$VAULT" || exit 1

run_once() {
  local hf="$STATE/maintain-$name.last-session.hash" prev cur n f prompt marker
  prev=$(cat "$hf" 2>/dev/null); cur=$(cksum <memory/last-session.md 2>/dev/null | cut -d' ' -f1,2)
  n=$(cat inbox/candidates-*.md 2>/dev/null | grep -c '^- \[ \]' || true)
  if [ "${n:-0}" -gt 0 ] || [ "$cur" != "$prev" ]; then
    log "starting: ${n:-0} unchecked candidates, last-session $([ "$cur" != "$prev" ] && echo new || echo same)"
    [ "$dry" = 1 ] && return 0
    prompt=$(MP_T="$(mp_today)" MP_S="$(mp_today | cut -c6-)" MP_P="$PRIVATE_DIR" perl -pe 's/\{\{TODAY\}\}/$ENV{MP_T}/g; s/\{\{SHORT\}\}/$ENV{MP_S}/g; s/\{\{PRIVATE_DIR\}\}/$ENV{MP_P}/g' "$MP_HOME/core/prompts/maintain.md")
    marker="$STATE/maintain-$name.marker"; : >"$marker"
    if ! MAINTAIN_TIMEOUT="$MAINTAIN_TIMEOUT" mp_edit_run "$agent" "$prompt" >"$STATE/maintain-$name.out"; then
      log "ERROR: maintainer model call failed, no commit"; return 1
    fi
    log "model output: $(head -c 300 "$STATE/maintain-$name.out" | mp_scrub | tr '\n' ' ')"
    # The private folder must stay untouched; detect it (the agent's tool permissions already forbid it).
    if [ -d "$PRIVATE_DIR" ] && [ -n "$(find "$PRIVATE_DIR" -type f -newer "$marker" 2>/dev/null | head -1)" ]; then
      log "ERROR: files in $PRIVATE_DIR changed during maintenance, no commit; check the agent's permissions"; return 1
    fi
    for f in inbox/candidates-*.md; do   # nothing left to sort: archive (never delete)
      [ -f "$f" ] || continue
      grep -q '^- \[[ ?]\]' "$f" && continue
      grep -q '^- \[x\]' "$f" || continue
      mkdir -p archive; dest="archive/$(basename "$f")"; [ -e "$dest" ] && dest="${dest%.md}-$(date +%H%M%S).md"
      mv "$f" "$dest" && log "archived $(basename "$f")"
    done
    printf '%s\n' "$cur" >"$hf"
  elif [ "$ifpending" = 1 ]; then
    log "nothing pending for the model"
  fi
  [ "$dry" = 1 ] && return 0
  bash "$MP_HOME/core/lessons.sh" "$VAULT" | while read -r l; do log "$l"; done
  commit_vault
}

commit_vault() {
  [ "$AUTO_COMMIT" = on ] || { log "AUTO_COMMIT is off, no commit"; return 0; }
  command -v git >/dev/null || return 0
  local top here; top=$(git rev-parse --show-toplevel 2>/dev/null) || { log "not a git repository, commit skipped"; return 0; }
  here=$(pwd -P); top=$(cd "$top" && pwd -P)
  [ "$top" = "$here" ] || { log "vault is inside another repository ($top), commit skipped"; return 0; }
  git add -A -- . ":!$PRIVATE_DIR" >/dev/null 2>&1
  if git diff --cached --quiet; then log "no changes, nothing to commit"; return 0; fi
  local id=(); [ -n "$(git config user.name)" ] && [ -n "$(git config user.email)" ] || id=(-c user.name=MindPalace -c user.email=mindpalace@localhost)
  if git "${id[@]}" commit -q -m "Maintainer: $(mp_today) session notes"; then log "committed (local only, never pushed)"; else log "ERROR: commit failed"; return 1; fi
}

run_once; rc=$?
if [ "$rc" = 0 ] && [ -e "$again" ]; then rm -f "$again"; run_once; rc=$?; fi
exit "$rc"
