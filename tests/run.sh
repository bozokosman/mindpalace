#!/bin/bash
# Offline test suite: installs into a throwaway HOME, checks hooks, idempotency and uninstall.
# No model call is made. Usage: bash tests/run.sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T=$(mktemp -d); export HOME="$T"; unset CLAUDE_CONFIG_DIR MP_VAULT MP_STATE
pass=0; failn=0
t() { if eval "$2" >/dev/null 2>&1; then echo "  ✓ $1"; pass=$((pass+1)); else echo "  ✗ $1"; failn=$((failn+1)); fi; }

mkdir -p "$T/.claude"
echo '{"hooks":{"PreToolUse":[{"matcher":"Edit","hooks":[{"type":"command","command":"echo mine"}]}]}}' > "$T/.claude/settings.json"
echo "# my rules" > "$T/.claude/CLAUDE.md"
H="$T/.claude/mindpalace"; V="$T/brain"

echo "install"
t "--check passes"            "bash '$ROOT/install.sh' --check"
t "--plan changes nothing"    "bash '$ROOT/install.sh' --plan --vault '$V' && [ ! -e '$H' ] && [ ! -e '$V' ]"
t "install succeeds"          "bash '$ROOT/install.sh' --yes --vault '$V' --projects '$T/code' --name 'A/B & C' --lang English"
t "doctor healthy"            "bash '$H/doctor.sh'"
t "no placeholders left"      "! grep -rq '{{' '$V'"
t "name with / and & kept"    "grep -q 'The user is A/B & C' '$V/RULES.md'"
t "user hook kept"            "jq -e '.hooks.PreToolUse[] | select(.matcher==\"Edit\")' '$T/.claude/settings.json'"
t "rules block added"         "grep -q 'mindpalace:start' '$T/.claude/CLAUDE.md' && grep -q '# my rules' '$T/.claude/CLAUDE.md'"
bash "$ROOT/install.sh" --yes >/dev/null 2>&1
t "rerun: no duplicate hooks" "[ \$(jq '[.hooks[][].hooks[].command | select(test(\"/mindpalace/\"))] | length' '$T/.claude/settings.json') = 4 ]"
t "rerun: one rules block"    "[ \$(grep -c 'mindpalace:start' '$T/.claude/CLAUDE.md') = 1 ]"

echo "session-start"
mkdir -p "$T/code/app/src"
t "vault loads memory"        "echo '{\"cwd\":\"$V\"}' | MINDPALACE_DOCTOR=1 bash '$H/session-start.sh' | grep -q 'MindPalace memory'"
t "project loads project"     "echo '{\"cwd\":\"$T/code/app/src\"}' | MINDPALACE_DOCTOR=1 bash '$H/session-start.sh' | grep -q 'Project memory: app'"
t "elsewhere loads nothing"   "[ -z \"\$(echo '{\"cwd\":\"/\"}' | MINDPALACE_DOCTOR=1 bash '$H/session-start.sh')\" ]"

echo "guard"
g() { jq -n --arg c "$1" '{tool_input:{command:$c}}' | bash "$H/guard.sh"; }
for c in "rm -rf x" "git push --force" "git reset --hard" "cat .env" "ls $V/private/"; do
  t "asks: $c" "g '$c' | grep -q '\"ask\"'"
done
for c in "ls -la" "git status" "rm file.txt" "cat env.txt"; do
  t "allows: $c" "[ -z \"\$(g '$c')\" ]"
done

echo "summarize (no model: short conversation)"
tr="$T/s.jsonl"
echo '{"type":"user","timestamp":"2026-01-01T10:00:00.000Z","message":{"content":"hi"}}' > "$tr"
echo '{"type":"assistant","timestamp":"2026-01-01T10:02:00.000Z","message":{"content":[{"type":"text","text":"hello"}]}}' >> "$tr"
bash "$H/summarize.sh" app "$tr" sid1 end
t "time.csv row written"      "grep -q ',app,2,2,sid1,' '$V/journal/time.csv'"
t "offset saved"              "[ -f '$H/state/sid1.offset' ]"
bash "$H/summarize.sh" app "$tr" sid1 end
t "one csv row per session"   "[ \$(grep -c sid1 '$V/journal/time.csv') = 1 ]"

echo "uninstall"
bash "$ROOT/uninstall.sh" --yes >/dev/null
t "our hooks removed"         "! grep -q '/mindpalace/' '$T/.claude/settings.json'"
t "user hook still there"     "jq -e '.hooks.PreToolUse[] | select(.matcher==\"Edit\")' '$T/.claude/settings.json'"
t "rules block removed"       "! grep -q 'mindpalace' '$T/.claude/CLAUDE.md' && grep -q '# my rules' '$T/.claude/CLAUDE.md'"
t "vault untouched"           "[ -f '$V/INDEX.md' ]"

rm -rf "$T"
echo "passed: $pass  failed: $failn"
[ "$failn" = 0 ]
