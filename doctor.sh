#!/bin/bash
# MindPalace health check. Exit 0 = healthy, 1 = something needs fixing.
#   bash ~/.claude/mindpalace/doctor.sh
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
MP_HOME="${MP_HOME:-$CLAUDE_DIR/mindpalace}"
SETTINGS="$CLAUDE_DIR/settings.json"
GLOBAL_MD="$CLAUDE_DIR/CLAUDE.md"
fail=0
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$*"; fail=1; }
note() { printf '  \033[33m!\033[0m %s\n' "$*"; }

echo "MindPalace doctor"
for c in bash jq perl claude; do command -v "$c" >/dev/null && ok "$c found" || bad "$c missing"; done

[ -f "$MP_HOME/VERSION" ] && ok "installed version $(cat "$MP_HOME/VERSION")" || bad "not installed in $MP_HOME (run install.sh)"
for f in common.sh guard.sh session-start.sh session-end.sh summarize.sh; do
  [ -f "$MP_HOME/$f" ] || bad "missing hook file $MP_HOME/$f"
done

if [ -f "$MP_HOME/mindpalace.conf" ]; then
  # shellcheck source=/dev/null
  source "$MP_HOME/mindpalace.conf"; ok "config $MP_HOME/mindpalace.conf"
else
  bad "config missing: $MP_HOME/mindpalace.conf"; exit 1
fi

if [ -f "$SETTINGS" ] && jq empty "$SETTINGS" 2>/dev/null; then
  for ev in PreToolUse SessionStart SessionEnd PreCompact; do
    n=$(jq --arg ev "$ev" '[.hooks[$ev][]?.hooks[]?.command | select(test("/mindpalace/"))] | length' "$SETTINGS")
    [ "$n" -ge 1 ] && ok "hook registered: $ev" || bad "hook not registered: $ev (run install.sh)"
  done
else
  bad "$SETTINGS missing or not valid JSON"
fi

if [ -d "$VAULT" ]; then
  ok "vault $VAULT"
  for d in inbox projects knowledge toolbox memory journal archive; do [ -d "$VAULT/$d" ] || note "vault folder missing: $d/"; done
  for f in INDEX.md RULES.md CLAUDE.md memory/profile.md; do [ -f "$VAULT/$f" ] || note "vault file missing: $f"; done
else
  bad "vault not found: $VAULT"
fi
grep -qF '<!-- mindpalace:start -->' "$GLOBAL_MD" 2>/dev/null && ok "rules imported in $GLOBAL_MD" || note "rules not imported in $GLOBAL_MD (optional)"

mkdir -p "$STATE" 2>/dev/null && [ -w "$STATE" ] && ok "state dir writable" || bad "state dir not writable: $STATE"

if [ -d "$VAULT" ]; then
  out=$(jq -n --arg c "$VAULT" '{cwd:$c,session_id:"doctor"}' | MINDPALACE_DOCTOR=1 bash "$MP_HOME/session-start.sh" 2>&1)
  grep -q "MindPalace memory" <<<"$out" && ok "SessionStart loads memory in the vault (${#out} chars)" || bad "SessionStart produced no memory output"
fi

if [ -f "$STATE/hook.log" ]; then
  errs=$(grep -c 'ERROR' "$STATE/hook.log" 2>/dev/null || true)
  [ "${errs:-0}" -gt 0 ] && note "$errs ERROR lines in $STATE/hook.log (last: $(grep 'ERROR' "$STATE/hook.log" | tail -1))"
fi

[ "$fail" = 0 ] && echo "Healthy." || echo "Problems found."
exit "$fail"
