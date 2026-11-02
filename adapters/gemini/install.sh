#!/bin/bash
# Gemini CLI adapter: install/uninstall/doctor. EXPERIMENTAL.
A_GEMINI_DIR="$HOME/.gemini"
A_GEMINI_SETTINGS="$A_GEMINI_DIR/settings.json"
A_GEMINI_RULES="$A_GEMINI_DIR/GEMINI.md"

adapter_label() { echo "Gemini CLI (experimental)"; }
adapter_cli()   { echo "gemini"; }
adapter_url()   { echo "https://github.com/google-gemini/gemini-cli"; }

adapter_plan() {
  echo "  - [Gemini] back up $A_GEMINI_SETTINGS, register hooks: BeforeTool/shell (guard, denies risky commands), SessionStart, SessionEnd, PreCompress"
  [ "$RULES" = 1 ] && echo "  - [Gemini] managed block importing \$VAULT/RULES.md into $A_GEMINI_RULES (backup first)"
  echo "  - [Gemini] GEMINI.md → @./AGENTS.md in each vault (only if missing)"
}

_gemini_jq_ours='def ours: (.hooks // []) | any(.command | test("mindpalace[/\\\\]adapters[/\\\\]gemini[/\\\\]hooks"));'

adapter_install() {
  local h tmp; h=$(mp_hook_path "$MP_HOME/adapters/gemini/hooks")
  mkdir -p "$A_GEMINI_DIR"
  [ -f "$A_GEMINI_SETTINGS" ] || echo '{}' > "$A_GEMINI_SETTINGS"
  jq empty "$A_GEMINI_SETTINGS" 2>/dev/null || { bad "$A_GEMINI_SETTINGS is not valid JSON; fix it and run again"; return 1; }
  cp "$A_GEMINI_SETTINGS" "$A_GEMINI_SETTINGS.bak-mindpalace-$STAMP"
  tmp=$(mktemp)
  jq --arg g "bash \"$h/guard.sh\"" --arg s "bash \"$h/session-start.sh\"" \
     --arg e "bash \"$h/session-end.sh\" end" --arg c "bash \"$h/session-end.sh\" compact" "$_gemini_jq_ours"'
    def put($ev; $entry): .hooks[$ev] = (((.hooks[$ev] // []) | map(select(ours | not))) + [$entry]);
    .hooks = (.hooks // {})
    | put("BeforeTool";  {matcher:"run_shell_command|shell", hooks:[{type:"command", name:"mindpalace-guard", command:$g, timeout:5000}]})
    | put("SessionStart";{hooks:[{type:"command", name:"mindpalace-memory", command:$s, timeout:10000}]})
    | put("SessionEnd";  {hooks:[{type:"command", name:"mindpalace-summary", command:$e, timeout:10000}]})
    | put("PreCompress"; {hooks:[{type:"command", name:"mindpalace-summary", command:$c, timeout:10000}]})
  ' "$A_GEMINI_SETTINGS" > "$tmp" && mv "$tmp" "$A_GEMINI_SETTINGS"
  ok "Gemini: hooks registered in $A_GEMINI_SETTINGS (backup made)"
  [ "$RULES" = 1 ] && mp_rules_block "$A_GEMINI_RULES" "@$VAULT/RULES.md
$(mp_rules_extra)" && ok "Gemini: rules imported in $A_GEMINI_RULES"
  mp_each_vault_file GEMINI.md '@./AGENTS.md'
  return 0
}

adapter_uninstall() {
  local tmp
  if [ -f "$A_GEMINI_SETTINGS" ]; then
    cp "$A_GEMINI_SETTINGS" "$A_GEMINI_SETTINGS.bak-mindpalace-$STAMP"
    tmp=$(mktemp)
    jq "$_gemini_jq_ours"'
      if .hooks then
        .hooks |= (with_entries(.value |= map(select(ours | not))) | with_entries(select(.value | length > 0)))
        | if .hooks == {} then del(.hooks) else . end
      else . end' "$A_GEMINI_SETTINGS" > "$tmp" && mv "$tmp" "$A_GEMINI_SETTINGS"
    ok "Gemini: hooks removed (backup made)"
  fi
  mp_rules_unblock "$A_GEMINI_RULES" && ok "Gemini: rules block removed from $A_GEMINI_RULES"
  return 0
}

adapter_doctor() {
  local ev n
  if [ -f "$A_GEMINI_SETTINGS" ] && jq empty "$A_GEMINI_SETTINGS" 2>/dev/null; then
    for ev in BeforeTool SessionStart SessionEnd PreCompress; do
      n=$(jq --arg ev "$ev" '[.hooks[$ev][]?.hooks[]?.command | select(test("mindpalace[/\\\\]adapters[/\\\\]gemini"))] | length' "$A_GEMINI_SETTINGS")
      [ "$n" -ge 1 ] && ok "Gemini hook: $ev" || bad "Gemini hook missing: $ev (run install.sh)"
    done
  else
    bad "$A_GEMINI_SETTINGS missing or not valid JSON"
  fi
  grep -qF '<!-- mindpalace:start -->' "$A_GEMINI_RULES" 2>/dev/null && ok "Gemini rules imported" || warn "Gemini rules not imported (optional)"
}
