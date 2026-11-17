#!/bin/bash
# Claude Code adapter: install/uninstall/doctor functions, sourced by install.sh, uninstall.sh, doctor.sh.
# Available from the caller: MP_HOME, VAULT, OS, STAMP, RULES (1/0), ok/warn/bad/confirm, mp_hook_path
A_CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
A_SETTINGS="$A_CLAUDE_DIR/settings.json"
A_RULES_FILE="$A_CLAUDE_DIR/CLAUDE.md"

adapter_label() { echo "Claude Code"; }
adapter_cli()   { echo "claude"; }
adapter_url()   { echo "https://claude.com/claude-code"; }

adapter_plan() {
  echo "  - [Claude Code] back up $A_SETTINGS, register hooks: PreToolUse/Bash (guard), SessionStart, SessionEnd, PreCompact"
  [ "$RULES" = 1 ] && echo "  - [Claude Code] managed block importing \$VAULT/RULES.md into $A_RULES_FILE (backup first)"
  echo "  - [Claude Code] CLAUDE.md → @AGENTS.md in each vault (only if missing)"
}

_claude_jq_ours='def ours: (.hooks // []) | any(.command | test("mindpalace[/\\\\]adapters[/\\\\]claude[/\\\\]hooks"));'

adapter_install() {
  local h; h=$(mp_hook_path "$MP_HOME/adapters/claude/hooks")
  mkdir -p "$A_CLAUDE_DIR"
  [ -f "$A_SETTINGS" ] || echo '{}' > "$A_SETTINGS"
  jq empty "$A_SETTINGS" 2>/dev/null || { bad "$A_SETTINGS is not valid JSON; fix it and run again"; return 1; }
  cp "$A_SETTINGS" "$A_SETTINGS.bak-mindpalace-$STAMP"
  local tmp; tmp=$(mktemp)
  jq --arg g "bash \"$h/guard.sh\"" --arg s "bash \"$h/session-start.sh\"" \
     --arg e "bash \"$h/session-end.sh\" end" --arg c "bash \"$h/session-end.sh\" compact" "$_claude_jq_ours"'
    def put($ev; $entry): .hooks[$ev] = (((.hooks[$ev] // []) | map(select(ours | not))) + [$entry]);
    .hooks = (.hooks // {})
    | put("PreToolUse";  {matcher:"Bash", hooks:[{type:"command", command:$g, timeout:5}]})
    | put("SessionStart";{hooks:[{type:"command", command:$s, timeout:10}]})
    | put("SessionEnd";  {hooks:[{type:"command", command:$e, timeout:10}]})
    | put("PreCompact";  {hooks:[{type:"command", command:$c, timeout:10}]})
  ' "$A_SETTINGS" > "$tmp" && mv "$tmp" "$A_SETTINGS"
  ok "Claude Code: hooks registered (backup: $A_SETTINGS.bak-mindpalace-$STAMP)"
  [ "$RULES" = 1 ] && mp_rules_block "$A_RULES_FILE" "@$VAULT/RULES.md
$(mp_rules_extra)" && ok "Claude Code: rules imported in $A_RULES_FILE"
  mp_each_vault_file CLAUDE.md '@AGENTS.md'
  return 0
}

adapter_uninstall() {
  if [ -f "$A_SETTINGS" ]; then
    cp "$A_SETTINGS" "$A_SETTINGS.bak-mindpalace-$STAMP"
    local tmp; tmp=$(mktemp)
    jq "$_claude_jq_ours"'
      if .hooks then
        .hooks |= (with_entries(.value |= map(select(ours | not))) | with_entries(select(.value | length > 0)))
        | if .hooks == {} then del(.hooks) else . end
      else . end' "$A_SETTINGS" > "$tmp" && mv "$tmp" "$A_SETTINGS"
    ok "Claude Code: hooks removed (backup: $A_SETTINGS.bak-mindpalace-$STAMP)"
  fi
  mp_rules_unblock "$A_RULES_FILE" && ok "Claude Code: rules block removed from $A_RULES_FILE"
  return 0
}

adapter_doctor() {
  local ev n
  if [ -f "$A_SETTINGS" ] && jq empty "$A_SETTINGS" 2>/dev/null; then
    for ev in PreToolUse SessionStart SessionEnd PreCompact; do
      n=$(jq --arg ev "$ev" '[.hooks[$ev][]?.hooks[]?.command | select(test("mindpalace[/\\\\]adapters[/\\\\]claude"))] | length' "$A_SETTINGS")
      [ "$n" -ge 1 ] && ok "Claude Code hook: $ev" || bad "Claude Code hook missing: $ev (run install.sh)"
    done
  else
    bad "$A_SETTINGS missing or not valid JSON"
  fi
  # Long-lived token file (optional): must exist and be readable by you only (mode 600). The value is never printed.
  if [ -n "${CLAUDE_OAUTH_TOKEN_FILE:-}" ]; then
    local tf="${CLAUDE_OAUTH_TOKEN_FILE/#\~/$HOME}" mode
    if [ ! -s "$tf" ]; then warn "Claude Code: CLAUDE_OAUTH_TOKEN_FILE is set but the file is missing or empty: $tf"
    elif [ "$OS" = windows ]; then ok "Claude Code: token file present (permission bits are not checked on Windows)"
    else
      mode=$(perl -e 'printf "%o", (stat($ARGV[0]))[2] & 07777' "$tf" 2>/dev/null)
      [ "$mode" = 600 ] && ok "Claude Code: token file has mode 600" || bad "Claude Code: token file $tf has mode $mode, must be 600 (run: chmod 600 \"$tf\")"
    fi
  fi
  grep -qF '<!-- mindpalace:start -->' "$A_RULES_FILE" 2>/dev/null && ok "Claude Code rules imported" || warn "Claude Code rules not imported in $A_RULES_FILE (optional)"
}
