#!/bin/bash
# Offline test suite. Installs into a throwaway HOME with fake claude/codex/gemini CLIs,
# then checks every adapter: transcript parsing, hooks, summaries, guard, idempotency, uninstall.
# No real model is called.  Usage: bash tests/run.sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FX="$ROOT/tests/fixtures"
T=$(mktemp -d); export HOME="$T"; unset CLAUDE_CONFIG_DIR CODEX_HOME COPILOT_HOME MP_VAULT MP_STATE MP_HOME
export XDG_CONFIG_HOME="$T/.config"   # never write into the real ~/.config
# Safety: refuse to run if any tool path still points outside the throwaway HOME
case "$XDG_CONFIG_HOME" in "$T"/*) ;; *) echo "unsafe test env" >&2; exit 1 ;; esac
pass=0; failn=0
t() { if eval "$2" >/dev/null 2>&1; then echo "  ✓ $1"; pass=$((pass+1)); else echo "  ✗ $1"; failn=$((failn+1)); fi; }

# Fake AI CLIs: read the prompt from stdin, answer with a canned summary.
mkdir -p "$T/bin"
for c in claude codex gemini; do
  cat > "$T/bin/$c" <<EOF
#!/bin/bash
cat >/dev/null
printf 'TITLE: Stripe checkout ($c)\n- Done: created src/checkout.ts\nNOTE: knowledge | prices in integer cents\n'
EOF
  chmod +x "$T/bin/$c"
done
export PATH="$T/bin:$PATH"

mkdir -p "$T/.claude" "$T/.codex" "$T/.gemini"
echo '{"hooks":{"PreToolUse":[{"matcher":"Edit","hooks":[{"type":"command","command":"echo mine"}]}]}}' > "$T/.claude/settings.json"
echo '{"theme":"dark"}' > "$T/.gemini/settings.json"
echo "# my rules" > "$T/.claude/CLAUDE.md"
H="$T/.mindpalace"; V="$T/brain"

echo "install"
t "--check finds all 3 tools"  "bash '$ROOT/install.sh' --check | grep -q 'found: claude codex gemini'"
t "--plan changes nothing"     "bash '$ROOT/install.sh' --plan --vault '$V' --agents claude,codex,gemini && [ ! -e '$H' ] && [ ! -e '$V' ]"
t "unknown agent rejected"     "! bash '$ROOT/install.sh' --yes --vault '$V' --agents foo"
t "install succeeds"           "bash '$ROOT/install.sh' --yes --vault '$V' --projects '$T/code' --name 'A/B & C' --lang English --agents claude,codex,gemini"
t "doctor healthy"             "bash '$H/doctor.sh'"
t "no placeholders left"       "! grep -rq '{{' '$V'"
t "name with / and & kept"     "grep -q 'The user is A/B & C' '$V/RULES.md'"
t "vault CLAUDE.md → AGENTS"   "grep -qx '@AGENTS.md' '$V/CLAUDE.md'"
t "vault GEMINI.md → AGENTS"   "grep -qx '@./AGENTS.md' '$V/GEMINI.md'"
t "claude: user hook kept"     "jq -e '.hooks.PreToolUse[] | select(.matcher==\"Edit\")' '$T/.claude/settings.json'"
t "gemini: other settings kept" "jq -e '.theme==\"dark\"' '$T/.gemini/settings.json'"
t "codex: 4 hooks"             "[ \$(jq '[.hooks[][].hooks[].command] | length' '$T/.codex/hooks.json') = 4 ]"
t "gemini: 4 hooks"            "[ \$(jq '[.hooks[][].hooks[].command | select(test(\"mindpalace\"))] | length' '$T/.gemini/settings.json') = 4 ]"
t "rules blocks (3 tools)"     "grep -q mindpalace:start '$T/.claude/CLAUDE.md' && grep -q mindpalace:start '$T/.codex/AGENTS.md' && grep -q mindpalace:start '$T/.gemini/GEMINI.md'"
bash "$ROOT/install.sh" --yes >/dev/null 2>&1
t "rerun: no duplicate hooks"  "[ \$(jq '[.hooks[][].hooks[].command | select(test(\"mindpalace\"))] | length' '$T/.claude/settings.json') = 4 ] && [ \$(jq '[.hooks[][].hooks[].command] | length' '$T/.codex/hooks.json') = 4 ]"
t "rerun: one rules block"     "[ \$(grep -c 'mindpalace:start' '$T/.claude/CLAUDE.md') = 1 ]"

echo "transcript parsing (normalized messages)"
for a in claude codex gemini; do
  f="$FX/$a.jsonl"; [ "$a" = gemini ] && f="$FX/gemini.json"
  out=$(MP_HOME="$H" bash -c "source '$H/core/common.sh'; mp_adapter $a; mp_agent_messages '$f'")
  t "$a: 3 real messages"          "[ \$(printf '%s\n' \"\$out\" | grep -c .) = 3 ]"
  t "$a: injected text filtered"   "! grep -qE 'injected|environment_context|subagent noise|system stuff|tool output|some info' <<<\"\$out\""
  t "$a: roles + timestamps"       "printf '%s\n' \"\$out\" | jq -se '.[0].role==\"user\" and .[1].role==\"assistant\" and (.[0].ts|length)>0'"
done
out=$(MP_HOME="$H" bash -c "source '$H/core/common.sh'; mp_adapter gemini; mp_agent_messages '$FX/gemini.jsonl'")
t "gemini .jsonl format too"     "[ \$(printf '%s\n' \"\$out\" | grep -c .) = 3 ]"

echo "session start (memory by location)"
mkdir -p "$T/code/app/src"
for a in claude codex gemini; do
  t "$a: vault loads memory"     "echo '{\"cwd\":\"$V\"}' | MINDPALACE_DOCTOR=1 bash '$H/adapters/$a/hooks/session-start.sh' | grep -q 'MindPalace memory'"
  t "$a: project loads project"  "echo '{\"cwd\":\"$T/code/app/src\"}' | MINDPALACE_DOCTOR=1 bash '$H/adapters/$a/hooks/session-start.sh' | grep -q 'Project memory: app'"
done
t "claude: elsewhere = nothing" "[ -z \"\$(echo '{\"cwd\":\"/\"}' | MINDPALACE_DOCTOR=1 bash '$H/adapters/claude/hooks/session-start.sh')\" ]"
t "codex: JSON with RULES + memory" "echo '{\"cwd\":\"$V\"}' | MINDPALACE_DOCTOR=1 bash '$H/adapters/codex/hooks/session-start.sh' | jq -e '.hookSpecificOutput.additionalContext | test(\"Shared rules\") and test(\"MindPalace memory\") and length < 9001'"
t "gemini: valid JSON context" "echo '{\"cwd\":\"$V\"}' | MINDPALACE_DOCTOR=1 bash '$H/adapters/gemini/hooks/session-start.sh' | jq -e '.hookSpecificOutput.additionalContext | test(\"MindPalace memory\")'"
t "gemini: elsewhere = nothing" "[ -z \"\$(echo '{\"cwd\":\"/\"}' | MINDPALACE_DOCTOR=1 bash '$H/adapters/gemini/hooks/session-start.sh')\" ]"

echo "guard"
for c in "rm -rf x" "git push --force" "git reset --hard" "cat .env" "ls $V/private/" "Remove-Item x -Recurse"; do
  t "claude asks: $c"  "jq -n --arg c '$c' '{tool_input:{command:\$c}}' | bash '$H/adapters/claude/hooks/guard.sh' | jq -e '.hookSpecificOutput.permissionDecision==\"ask\"'"
done
t "codex denies: rm -rf"       "jq -n '{tool_input:{command:\"rm -rf x\"}}' | bash '$H/adapters/codex/hooks/guard.sh' | jq -e '.hookSpecificOutput.permissionDecision==\"deny\"'"
t "codex: array command"       "jq -n '{tool_input:{command:[\"bash\",\"-lc\",\"rm -rf x\"]}}' | bash '$H/adapters/codex/hooks/guard.sh' | jq -e '.hookSpecificOutput.permissionDecision==\"deny\"'"
t "gemini denies: rm -rf"      "jq -n '{tool_input:{command:\"rm -rf x\"}}' | bash '$H/adapters/gemini/hooks/guard.sh' | jq -e '.decision==\"deny\"'"
for c in "ls -la" "git status" "rm file.txt" "cat env.txt"; do
  for a in claude codex gemini; do
    t "$a allows: $c" "[ -z \"\$(jq -n --arg c '$c' '{tool_input:{command:\$c}}' | bash '$H/adapters/$a/hooks/guard.sh')\" ]"
  done
done

echo "summaries (fake CLIs)"
sed -i.bak "s|^MIN_CONV_CHARS=.*|MIN_CONV_CHARS=50|" "$H/mindpalace.conf"
for a in claude codex gemini; do
  f="$FX/$a.jsonl"; [ "$a" = gemini ] && f="$FX/gemini.json"
  sed -i.bak "s|^SUMMARY_AGENT=.*|SUMMARY_AGENT=\"$a\"|" "$H/mindpalace.conf"
  MP_HOME="$H" bash "$H/core/summarize.sh" "$a" app "$f" "s-$a" end >/dev/null 2>&1
  t "$a: journal entry"        "grep -q 'Stripe checkout ($a)' '$V/journal/'\$(date +%F).md"
  t "$a: time.csv row"         "grep -qE ',app,[45],3,s-$a,.*,$a\$' '$V/journal/time.csv'"
  t "$a: inbox candidate"      "grep -q 'prices in integer cents' '$V/inbox/candidates-'\$(date +%F).md"
done
MP_HOME="$H" bash "$H/core/summarize.sh" claude app "$FX/claude.jsonl" s-claude end >/dev/null 2>&1
t "re-run: nothing new, one csv row" "[ \$(grep -c 's-claude' '$V/journal/time.csv') = 1 ]"
MP_HOME="$H" bash "$H/core/summarize.sh" codex xproj "$FX/codex.jsonl" s-cross end >/dev/null 2>&1   # SUMMARY_AGENT is gemini now
t "cross-tool: codex session summarized by gemini" "grep -qF '[xproj] Stripe checkout (gemini) (codex)' '$V/journal/'\$(date +%F).md"

echo "rules-only tools (zed, qwen)"
mkdir -p "$T/.qwen"; echo "# my qwen notes" > "$T/.qwen/QWEN.md"
bash "$ROOT/install.sh" --yes --agents claude,codex,gemini,zed,qwen >/dev/null 2>&1
t "zed: rules block created"   "grep -q 'read $V/RULES.md' '$T/.config/zed/AGENTS.md'"
t "qwen: block appended, notes kept" "grep -q mindpalace:start '$T/.qwen/QWEN.md' && grep -q '# my qwen notes' '$T/.qwen/QWEN.md'"
t "doctor healthy with 5 tools" "bash '$H/doctor.sh'"
t "summarizer still a full adapter" "grep -qE '^SUMMARY_AGENT=\"(claude|codex|gemini)\"' '$H/mindpalace.conf'"
t "plan lists rules-only tools" "bash '$ROOT/install.sh' --plan --agents zed | grep -q 'Zed agent.*RULES.md'"

echo "uninstall"
bash "$H/uninstall.sh" --yes >/dev/null
t "claude hooks removed, user hook kept" "! grep -q mindpalace '$T/.claude/settings.json' && jq -e '.hooks.PreToolUse[0].matcher==\"Edit\"' '$T/.claude/settings.json'"
t "codex hooks removed"        "! grep -q mindpalace '$T/.codex/hooks.json'"
t "gemini hooks removed, settings kept" "! grep -q mindpalace '$T/.gemini/settings.json' && jq -e '.theme==\"dark\"' '$T/.gemini/settings.json'"
t "rules blocks removed"       "! grep -q mindpalace '$T/.claude/CLAUDE.md' '$T/.codex/AGENTS.md' '$T/.gemini/GEMINI.md' && grep -q '# my rules' '$T/.claude/CLAUDE.md'"
t "rules-only blocks removed" "! grep -q mindpalace '$T/.config/zed/AGENTS.md' '$T/.qwen/QWEN.md' && grep -q '# my qwen notes' '$T/.qwen/QWEN.md'"
t "vault untouched"            "[ -f '$V/INDEX.md' ] && [ -f '$V/journal/time.csv' ]"

rm -rf "$T"
echo "passed: $pass  failed: $failn"
[ "$failn" = 0 ]
