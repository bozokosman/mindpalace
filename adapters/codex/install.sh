#!/bin/bash
# Codex CLI adapter: install/uninstall/doctor. EXPERIMENTAL.
A_CODEX_DIR="${CODEX_HOME:-$HOME/.codex}"
A_CODEX_HOOKS="$A_CODEX_DIR/hooks.json"
A_CODEX_RULES="$A_CODEX_DIR/AGENTS.md"

adapter_label() { echo "Codex CLI (experimental)"; }
adapter_cli()   { echo "codex"; }
adapter_url()   { echo "https://github.com/openai/codex"; }

adapter_plan() {
  echo "  - [Codex] back up $A_CODEX_HOOKS, register hooks: PreToolUse/Bash (guard, denies risky commands), SessionStart, SessionEnd, PreCompact"
  [ "$RULES" = 1 ] && echo "  - [Codex] managed block in $A_CODEX_RULES pointing to \$VAULT/RULES.md (rules are also injected at session start)"
  echo "  - [Codex] after install, the user must approve the new hooks once with /hooks inside Codex"
}

_codex_jq_ours='def ours: (.hooks // []) | any(.command | test("mindpalace[/\\\\]adapters[/\\\\]codex[/\\\\]hooks"));'

adapter_install() {
  local h tmp; h=$(mp_hook_path "$MP_HOME/adapters/codex/hooks")
  mkdir -p "$A_CODEX_DIR"
  [ -f "$A_CODEX_HOOKS" ] || echo '{}' > "$A_CODEX_HOOKS"
  jq empty "$A_CODEX_HOOKS" 2>/dev/null || { bad "$A_CODEX_HOOKS is not valid JSON; fix it and run again"; return 1; }
  cp "$A_CODEX_HOOKS" "$A_CODEX_HOOKS.bak-mindpalace-$STAMP"
  tmp=$(mktemp)
  jq --arg g "bash \"$h/guard.sh\"" --arg s "bash \"$h/session-start.sh\"" \
     --arg e "bash \"$h/session-end.sh\" end" --arg c "bash \"$h/session-end.sh\" compact" "$_codex_jq_ours"'
    def put($ev; $entry): .hooks[$ev] = (((.hooks[$ev] // []) | map(select(ours | not))) + [$entry]);
    .hooks = (.hooks // {})
    | put("PreToolUse";  {matcher:"^Bash$", hooks:[{type:"command", command:$g, timeout:5, statusMessage:"MindPalace guard"}]})
    | put("SessionStart";{hooks:[{type:"command", command:$s, timeout:10, statusMessage:"Loading MindPalace memory"}]})
    | put("SessionEnd";  {hooks:[{type:"command", command:$e, timeout:3}]})
    | put("PreCompact";  {hooks:[{type:"command", command:$c, timeout:10}]})
  ' "$A_CODEX_HOOKS" > "$tmp" && mv "$tmp" "$A_CODEX_HOOKS"
  ok "Codex: hooks registered in $A_CODEX_HOOKS (backup made)"
  warn "Codex: open Codex and approve the MindPalace hooks once with /hooks, otherwise they do not run"
  if [ "$RULES" = 1 ]; then
    mp_rules_block "$A_CODEX_RULES" "Shared rules and memory system: read $VAULT/RULES.md and follow it. Vault: $VAULT" \
      && ok "Codex: rules pointer added to $A_CODEX_RULES"
  fi
  return 0
}

adapter_uninstall() {
  local tmp
  if [ -f "$A_CODEX_HOOKS" ]; then
    cp "$A_CODEX_HOOKS" "$A_CODEX_HOOKS.bak-mindpalace-$STAMP"
    tmp=$(mktemp)
    jq "$_codex_jq_ours"'
      if .hooks then
        .hooks |= (with_entries(.value |= map(select(ours | not))) | with_entries(select(.value | length > 0)))
        | if .hooks == {} then del(.hooks) else . end
      else . end' "$A_CODEX_HOOKS" > "$tmp" && mv "$tmp" "$A_CODEX_HOOKS"
    ok "Codex: hooks removed (backup made)"
  fi
  mp_rules_unblock "$A_CODEX_RULES" && ok "Codex: rules block removed from $A_CODEX_RULES"
  return 0
}

adapter_doctor() {
  local ev n
  if [ -f "$A_CODEX_HOOKS" ] && jq empty "$A_CODEX_HOOKS" 2>/dev/null; then
    for ev in PreToolUse SessionStart SessionEnd PreCompact; do
      n=$(jq --arg ev "$ev" '[.hooks[$ev][]?.hooks[]?.command | select(test("mindpalace[/\\\\]adapters[/\\\\]codex"))] | length' "$A_CODEX_HOOKS")
      [ "$n" -ge 1 ] && ok "Codex hook: $ev" || bad "Codex hook missing: $ev (run install.sh)"
    done
    warn "Codex: hooks only run after you approve them with /hooks (cannot be checked from here)"
  else
    bad "$A_CODEX_HOOKS missing or not valid JSON"
  fi
}
