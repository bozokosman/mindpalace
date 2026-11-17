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
t "--plan changes nothing"     "bash '$ROOT/install.sh' --plan --vault brain='$V' --agents claude,codex,gemini && [ ! -e '$H' ] && [ ! -e '$V' ]"
t "unknown agent rejected"     "! bash '$ROOT/install.sh' --yes --vault brain='$V' --agents foo"
t "invalid vault name rejected" "! bash '$ROOT/install.sh' --plan --vault '9bad=$T/x' --agents claude"
t "install succeeds"           "bash '$ROOT/install.sh' --yes --vault brain='$V' --projects brain='$T/code' --name 'A/B & C' --lang English --agents claude,codex,gemini"
t "doctor healthy"             "bash '$H/doctor.sh'"
t "vault named by the user"    "head -1 '$V/AGENTS.md' | grep -qx '# brain'"
t "config has vault section"   "grep -qx 'VAULTS=\"brain\"' '$H/mindpalace.conf' && grep -q '^VAULT_brain=' '$H/mindpalace.conf'"
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

sed -i.bak "s|^RETRY_WAIT=.*|RETRY_WAIT=\"0 0\"|" "$H/mindpalace.conf"
sed -i.bak "s|^MAINTAIN=.*|MAINTAIN=\"off\"|" "$H/mindpalace.conf"
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
  MP_HOME="$H" bash "$H/core/summarize.sh" "$a" "$T/code/app" "$f" "s-$a" end >/dev/null 2>&1
  t "$a: journal entry"        "grep -q 'Stripe checkout ($a)' '$V/journal/'\$(date +%F).md"
  t "$a: time.csv row"         "grep -qE ',app,[45],3,s-$a,.*,$a\$' '$V/journal/time.csv'"
  t "$a: inbox candidate"      "grep -q 'prices in integer cents' '$V/inbox/candidates-'\$(date +%F).md"
done
MP_HOME="$H" bash "$H/core/summarize.sh" claude "$T/code/app" "$FX/claude.jsonl" s-claude end >/dev/null 2>&1
t "re-run: nothing new, one csv row" "[ \$(grep -c 's-claude' '$V/journal/time.csv') = 1 ]"
MP_HOME="$H" bash "$H/core/summarize.sh" codex "$T/code/xproj" "$FX/codex.jsonl" s-cross end >/dev/null 2>&1   # SUMMARY_AGENT is gemini now
t "cross-tool: codex session summarized by gemini" "grep -qF '[xproj] Stripe checkout (gemini) (codex)' '$V/journal/'\$(date +%F).md"

echo "resilience: retries"
cat > "$T/bin/claude-flaky" <<'X'
#!/bin/bash
cat >/dev/null
n=$(cat "$FLAKY_DIR/count" 2>/dev/null || echo 0); echo $((n+1)) >"$FLAKY_DIR/count"
if [ "$n" -lt "$FLAKY_FAILS" ]; then echo "${FLAKY_MSG:-529 overloaded_error}" >&2; exit 1; fi
printf 'TITLE: Flaky ok\n- Done: it worked\n'
X
chmod +x "$T/bin/claude-flaky"
mkdir -p "$T/flaky"
rl() { # run mp_llm_run with the flaky CLI as claude's model call; echo "rc|attempts"
  rm -f "$T/flaky/count"
  out=$(FLAKY_DIR="$T/flaky" FLAKY_FAILS="$1" FLAKY_MSG="${2:-}" MP_HOME="$H" TEST_RW="${3-0 0}" bash -c '
    source "$MP_HOME/core/common.sh"; RETRY_WAIT="$TEST_RW"
    mp_agent_llm() { claude-flaky; }
    mp_adapter() { :; }
    mp_llm_run claude "prompt" >/dev/null 2>&1; echo "$?"' )
  echo "$out|$(cat "$T/flaky/count" 2>/dev/null || echo 0)"
}
t "transient error: 2 failures then success"  "[ \"\$(rl 2)\" = '0|3' ]"
t "transient error: gives up after 2 retries" "[ \"\$(rl 5)\" = '1|3' ]"
t "no retries when RETRY_WAIT is empty"       "[ \"\$(rl 1 '' '')\" = '1|1' ]"
for m in "401 Unauthorized" "Error: 403 forbidden" "Not logged in. Run /login" "authentication_error" "claude: command not found"; do
  t "permanent error not retried: $m"          "[ \"\$(rl 5 '$m')\" = '1|1' ]"
done

echo "resilience: lock"
LK="$T/lock.pid"; rm -f "$LK"
lk() { MP_HOME="$H" bash -c 'source "$MP_HOME/core/common.sh"; '"$1" _ "$LK"; }
sleep 300 & LIVE=$!
( sleep 0 ) & DEAD=$!; wait $DEAD 2>/dev/null
LIVE_START=$(MP_HOME="$H" bash -c 'source "$MP_HOME/core/common.sh"; mp_proc_start '"$LIVE")
t "free lock is acquired"                     "lk 'mp_lock_acquire \"\$1\"' && grep -q . '$LK'"
t "lock held by a live process is respected"  "printf '%s %s\n' $LIVE '$LIVE_START' >'$LK'; ! lk 'mp_lock_acquire \"\$1\"'"
t "stale lock (dead PID) is taken over"       "printf '%s %s\n' $DEAD 'Mon Jan  1 00:00:00 2024' >'$LK'; lk 'mp_lock_acquire \"\$1\"'"
if [ -n "$LIVE_START" ]; then
  t "PID reuse: live PID, other start time = stale" "printf '%s %s\n' $LIVE 'Mon Jan  1 00:00:00 2001' >'$LK'; lk 'mp_lock_acquire \"\$1\"'"
else echo "  - skipped: PID reuse check (ps -o lstart= unavailable on this platform; falls back to lock age)"; fi
t "only the owner releases"                   "printf '%s x\n' $LIVE >'$LK'; lk 'mp_lock_release \"\$1\"'; [ -f '$LK' ]"
t "an unverifiable old lock expires"          "printf '%s\n' $LIVE >'$LK'; perl -e 'utime(1,1,\$ARGV[0])' '$LK'; lk 'mp_lock_acquire \"\$1\"'"
kill $LIVE 2>/dev/null; rm -f "$LK"

echo "resilience: summarize with retries and empty retry"
cat > "$T/bin/claude-seq" <<'X'
#!/bin/bash
cat >/dev/null
n=$(cat "$FLAKY_DIR/count" 2>/dev/null || echo 0); echo $((n+1)) >"$FLAKY_DIR/count"
if [ "$n" -lt 1 ]; then echo EMPTY; else printf 'TITLE: Second try\n- Done: x\n'; fi
X
chmod +x "$T/bin/claude-seq"
sed -i.bak "s|^SUMMARY_AGENT=.*|SUMMARY_AGENT=\"claude\"|; s|^RETRY_WAIT=.*|RETRY_WAIT=\"0 0\"|" "$H/mindpalace.conf"
mkdir -p "$T/seq"; rm -f "$T/seq/count"
cp "$T/bin/claude" "$T/bin/claude.orig"
cp "$T/bin/claude-seq" "$T/bin/claude"
sed -i.bak "s|^EMPTY_RETRY_MIN_CHARS=.*|EMPTY_RETRY_MIN_CHARS=10|" "$H/mindpalace.conf"
FLAKY_DIR="$T/seq" MP_HOME="$H" bash "$H/core/summarize.sh" claude "$T/code/app" "$FX/claude.jsonl" s-empty end >/dev/null 2>&1
t "EMPTY on a long conversation: one more try" "[ \"\$(cat '$T/seq/count')\" = 2 ] && grep -q 'Second try' '$V/journal/'\$(date +%F).md"
rm -f "$T/seq/count"
sed -i.bak "s|^EMPTY_RETRY_MIN_CHARS=.*|EMPTY_RETRY_MIN_CHARS=999999|" "$H/mindpalace.conf"
FLAKY_DIR="$T/seq" MP_HOME="$H" bash "$H/core/summarize.sh" claude "$T/code/app" "$FX/claude.jsonl" s-empty2 end >/dev/null 2>&1
t "EMPTY on a short conversation: no retry"    "[ \"\$(cat '$T/seq/count')\" = 1 ]"
cp "$T/bin/claude.orig" "$T/bin/claude"; rm -f "$T/bin/claude.orig"

echo "resilience: recovery at session start (background)"
hr() { perl -MTime::HiRes=time -e 'printf "%.3f", time'; }
mkdir -p "$T/.claude/projects/p1"
cp "$FX/claude.jsonl" "$T/.claude/projects/p1/lost1.jsonl"
perl -e 'my $o=time-3600; utime($o,$o,$ARGV[0])' "$T/.claude/projects/p1/lost1.jsonl"
perl -e 'my $o=time-86400; utime($o,$o,$ARGV[0])' "$H/state/.installed"
sed -i.bak "s|^SUMMARY_AGENT=.*|SUMMARY_AGENT=\"claude\"|" "$H/mindpalace.conf"
t0=$(hr)
rec_out=$(echo "{\"cwd\":\"$V\",\"session_id\":\"cur\"}" | bash "$H/adapters/claude/hooks/session-start.sh")
t1=$(hr)
t "session start returns fast with recovery on" "perl -e 'exit(($t1 - $t0) < 1.0 ? 0 : 1)'"
t "recovery adds at most 1 line to stdout"      "[ \$(printf '%s\n' \"\$rec_out\" | grep -c '^MindPalace health') -le 1 ]"
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do grep -qF '[x]' "$V/journal/$(date +%F).md" 2>/dev/null && break; sleep 0.5; done
t "unsummarized session recovered in background" "grep -q '\[x\] Stripe checkout' '$V/journal/'\$(date +%F).md"
t "recovery does nothing when RECOVER=off"       "sed -i.bak 's|^RECOVER=.*|RECOVER=\"off\"|' '$H/mindpalace.conf'; MP_HOME='$H' bash -c 'source \"\$MP_HOME/core/common.sh\"; mp_recover_start claude x; echo done' | grep -qx done; sed -i.bak 's|^RECOVER=.*|RECOVER=\"on\"|' '$H/mindpalace.conf'"
rm -rf "$T/.claude/projects/p1"

echo "maintainer"
cat > "$T/bin/claude-maint" <<'X'
#!/bin/bash
# Fake claude. With the maintainer's flags it plays the maintainer: checks off candidate lines and writes a note.
cat >/dev/null
if [[ "$*" == *"--permission-mode acceptEdits"* ]]; then
  echo "$*" >"$FAKE_ARGS"; echo "cwd=$PWD" >>"$FAKE_ARGS"
  [ -n "$FAKE_EDIT_FAIL" ] && { echo "529 overloaded" >&2; exit 1; }
  for f in inbox/candidates-*.md; do [ -f "$f" ] && perl -pi -e 's/^- \[ \]/- [x]/' "$f"; done
  mkdir -p knowledge; echo "# Prices in cents" >knowledge/prices.md
  [ -n "$FAKE_TOUCH_PRIVATE" ] && echo x >private/leak.md
  echo "processed 1 line"; exit 0
fi
printf 'TITLE: Stripe checkout (fake)\n- Done: x\n'
X
chmod +x "$T/bin/claude-maint"; cp "$T/bin/claude" "$T/bin/claude.keep"; cp "$T/bin/claude-maint" "$T/bin/claude"
export FAKE_ARGS="$T/maint-args"
sed -i.bak "s|^MAINTAIN=.*|MAINTAIN=\"on\"|; s|^MAINTAIN_AGENT=.*|MAINTAIN_AGENT=\"claude\"|" "$H/mindpalace.conf"
git init -q --bare "$T/remote.git"; git -C "$V" remote add origin "$T/remote.git"
ml() { MP_HOME="$H" bash "$H/core/maintain.sh" "$@" 2>&1; }
# fresh candidates for the test
mkdir -p "$V/inbox"; printf -- '---\ntype: knowledge\n---\n- [ ] knowledge | prices in integer cents\n' >"$V/inbox/candidates-2026-01-01.md"
head_before=$(git -C "$V" rev-parse HEAD)
ml brain >"$T/ml.out"
t "config enables maintainer for claude"   "grep -qx 'MAINTAIN_AGENT=\"claude\"' '$H/mindpalace.conf'"
t "maintainer wrote the note"              "[ -f '$V/knowledge/prices.md' ]"
t "sorted candidate file archived"         "[ ! -f '$V/inbox/candidates-2026-01-01.md' ] && [ -f '$V/archive/candidates-2026-01-01.md' ]"
t "committed locally, tree clean"          "[ \"\$(git -C '$V' rev-parse HEAD)\" != '$head_before' ] && git -C '$V' log -1 --format=%s | grep -q '^Maintainer: ' && [ -z \"\$(git -C '$V' status --porcelain)\" ]"
t "never pushed (remote stays empty)"      "[ -z \"\$(git -C '$T/remote.git' rev-list --all 2>/dev/null)\" ]"
t "no push command anywhere in core"       "! grep -rnE 'git +(-C +[^ ]+ +)?push( |$)' '$H/core/maintain.sh' '$H/core/recover.sh' '$H/core/summarize.sh' '$H/core/common.sh' '$H/core/lessons.sh'"
t "agent: file tools only, no Bash"        "grep -q -- '--tools Read,Edit,Write,Glob,Grep' '$FAKE_ARGS' && ! grep -q 'Bash' '$FAKE_ARGS'"
t "agent: runs inside the vault"           "grep -qx 'cwd=$V' '$FAKE_ARGS'"
t "agent: private folder forbidden"        "grep -q 'Read(./private/\*\*)' '$FAKE_ARGS' && grep -q 'Edit(./private/\*\*)' '$FAKE_ARGS'"
# private touched -> no commit
printf -- '- [ ] knowledge | another\n' >"$V/inbox/candidates-2026-01-02.md"; head_before=$(git -C "$V" rev-parse HEAD)
FAKE_TOUCH_PRIVATE=1 ml brain >"$T/ml.out"
t "private folder touched: error, no commit" "grep -q 'ERROR: files in private changed' '$T/ml.out' && [ \"\$(git -C '$V' rev-parse HEAD)\" = '$head_before' ]"
rm -f "$V/private/leak.md"
# model failure: no commit, retried
printf -- '- [ ] knowledge | third\n' >"$V/inbox/candidates-2026-01-03.md"; head_before=$(git -C "$V" rev-parse HEAD)
FAKE_EDIT_FAIL=1 ml brain >"$T/ml.out"
t "model failure: retried, then no commit"   "grep -q 'retry 2/2' '$T/ml.out' && grep -q 'ERROR: maintainer model call failed' '$T/ml.out' && [ \"\$(git -C '$V' rev-parse HEAD)\" = '$head_before' ]"
# AUTO_COMMIT off
sed -i.bak 's|^AUTO_COMMIT=.*|AUTO_COMMIT="off"|' "$H/mindpalace.conf"
ml brain >"$T/ml.out"
t "AUTO_COMMIT=off: files change, no commit" "grep -q 'AUTO_COMMIT is off' '$T/ml.out' && [ \"\$(git -C '$V' rev-parse HEAD)\" = '$head_before' ] && [ -n \"\$(git -C '$V' status --porcelain)\" ]"
git -C "$V" add -A >/dev/null; git -C "$V" -c user.name=t -c user.email=t@t commit -qm "test: settle" ; sed -i.bak 's|^AUTO_COMMIT=.*|AUTO_COMMIT="on"|' "$H/mindpalace.conf"
# not a git repo
mv "$V/.git" "$T/git.keep"; printf -- '- [ ] knowledge | fourth\n' >"$V/inbox/candidates-2026-01-04.md"
ml brain >"$T/ml.out"
t "vault without git: works, commit skipped" "grep -q 'not a git repository' '$T/ml.out' && [ -f '$V/archive/candidates-2026-01-04.md' ]"
mv "$T/git.keep" "$V/.git"
# off, unsupported, locked
sed -i.bak 's|^MAINTAIN=.*|MAINTAIN="off"|' "$H/mindpalace.conf"; printf -- '- [ ] knowledge | fifth\n' >"$V/inbox/candidates-2026-01-05.md"
ml brain >/dev/null
t "MAINTAIN=off: nothing happens"            "grep -q '^- \[ \]' '$V/inbox/candidates-2026-01-05.md'"
sed -i.bak 's|^MAINTAIN=.*|MAINTAIN="on"|; s|^MAINTAIN_AGENT=.*|MAINTAIN_AGENT="codex"|' "$H/mindpalace.conf"
ml brain >"$T/ml.out"
t "codex: unsupported, stays off"            "grep -q 'unsupported: codex' '$T/ml.out' && grep -q '^- \[ \]' '$V/inbox/candidates-2026-01-05.md'"
t "gemini: unsupported too"                  "! grep -q '^mp_agent_edit()' '$H/adapters/gemini/adapter.sh' '$H/adapters/codex/adapter.sh'"
sed -i.bak 's|^MAINTAIN_AGENT=.*|MAINTAIN_AGENT="claude"|' "$H/mindpalace.conf"
sleep 300 & LV=$!; LVS=$(MP_HOME="$H" bash -c 'source "$MP_HOME/core/common.sh"; mp_proc_start '"$LV")
printf '%s %s\n' "$LV" "$LVS" >"$H/state/maintain-brain.pid"
ml brain >"$T/ml.out"
t "second maintainer waits for the running one" "grep -q 'another maintainer is running' '$T/ml.out' && [ -e '$H/state/maintain-brain.again' ] && grep -q '^- \[ \]' '$V/inbox/candidates-2026-01-05.md'"
kill $LV 2>/dev/null; rm -f "$H/state/maintain-brain.pid" "$H/state/maintain-brain.again"
printf '999999 Mon Jan  1 00:00:00 2001\n' >"$H/state/maintain-brain.pid"
ml brain >"$T/ml.out"
t "stale maintainer lock is taken over"      "grep -q 'stale lock' '$T/ml.out' && [ -f '$V/archive/candidates-2026-01-05.md' ]"
# a finished summary starts the maintainer by itself
printf -- '- [ ] knowledge | sixth\n' >"$V/inbox/candidates-2026-01-06.md"
MP_HOME="$H" bash "$H/core/summarize.sh" claude "$T/code/app" "$FX/claude.jsonl" s-trigger end >/dev/null 2>&1
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do [ -f "$V/archive/candidates-2026-01-06.md" ] && break; sleep 0.5; done
t "summary end triggers the maintainer"      "[ -f '$V/archive/candidates-2026-01-06.md' ]"
cp "$T/bin/claude.keep" "$T/bin/claude"; rm -f "$T/bin/claude.keep"
sed -i.bak "s|^MAINTAIN=.*|MAINTAIN=\"off\"|" "$H/mindpalace.conf"

echo "lessons cycle (fake dates)"
LV="$T/lessons-vault"; mkdir -p "$LV/memory"; cp "$V/memory/mistakes.md" "$LV/memory/mistakes.md"
perl -0pi -e 's/(## Active rules\n<!--[^\n]*-->\n)/$1- [c-trial] (trial) Always run the tests before saying done.\n- [d-rule] (rule) Never edit generated files.\n/; s/(## Records\n<!--[^\n]*-->\n)/$1### a-observed\n1 · observed · 2026-02-01\n- 2026-02-01: once\n\n### b-second\n2 · observed · 2026-02-01\n- 2026-02-01: twice\n\n### c-trial\n2 · trial · 2026-01-01\n- 2026-01-01: x\n\n### d-rule\n3 · rule · 2026-01-01\n- 2026-01-01: y\n/' "$LV/memory/mistakes.md"
lz() { MP_HOME="$H" MP_TODAY="$1" bash "$H/core/lessons.sh" "$LV"; }
lz 2026-02-05 >"$T/lz.out"
t "count 2 becomes trial + rule line"        "grep -q '^2 · trial · 2026-02-01' '$LV/memory/mistakes.md' && grep -q '^- \[b-second\] (trial)' '$LV/memory/mistakes.md'"
t "observed (count 1) stays observed"        "grep -q '^1 · observed · 2026-02-01' '$LV/memory/mistakes.md'"
t "trial 35 days without repeat becomes rule" "grep -q '^2 · rule · 2026-01-01' '$LV/memory/mistakes.md' && grep -q '^- \[c-trial\] (rule)' '$LV/memory/mistakes.md'"
t "trial under 30 days is kept"              "grep -q '^- \[b-second\] (trial)' '$LV/memory/mistakes.md'"
t "rule under 90 days is kept"               "grep -q '^### d-rule' '$LV/memory/mistakes.md' && [ ! -f '$LV/archive/mistakes-retired.md' ]"
sum1=$(cksum <"$LV/memory/mistakes.md"); lz 2026-02-05 >"$T/lz.out"
t "second run on the same day changes nothing" "[ \"\$(cksum <'$LV/memory/mistakes.md')\" = '$sum1' ] && grep -q '0 promoted, 0 retired' '$T/lz.out'"
lz 2026-04-10 >"$T/lz.out"
t "rule 99 days without repeat is retired"   "grep -q '^### d-rule' '$LV/archive/mistakes-retired.md' && ! grep -q 'd-rule' '$LV/memory/mistakes.md'"
t "retired rule keeps its text in the archive" "grep -q 'Rule was: Never edit generated files' '$LV/archive/mistakes-retired.md'"
t "promoted rule can retire in the same run"   "grep -q '^### c-trial' '$LV/archive/mistakes-retired.md' && grep -q '^2 · rule · 2026-02-01' '$LV/memory/mistakes.md'"
t "retired file has frontmatter"             "head -1 '$LV/archive/mistakes-retired.md' | grep -qx -- '---'"
# cap on active rules
cat >>"$LV/memory/mistakes.md" <<'X'

### e-new
2 · trial · 2026-04-01
- 2026-04-01: e

### f-newer
2 · trial · 2026-04-05
- 2026-04-05: f
X
perl -0pi -e 's/(## Active rules\n<!--[^\n]*-->\n)/$1- [e-new] (trial) Rule E.\n- [f-newer] (trial) Rule F.\n/' "$LV/memory/mistakes.md"
sed -i.bak 's|^LESSON_MAX_RULES=.*|LESSON_MAX_RULES=2|' "$H/mindpalace.conf"
lz 2026-04-10 >"$T/lz.out"
t "more than the cap: unused longest is retired" "grep -q '^### b-second' '$LV/archive/mistakes-retired.md' && grep -q '^### e-new' '$LV/memory/mistakes.md' && grep -q '^### f-newer' '$LV/memory/mistakes.md'"
sed -i.bak 's|^LESSON_MAX_RULES=.*|LESSON_MAX_RULES=15|' "$H/mindpalace.conf"
t "dates work without GNU date"              "[ \"\$(MP_HOME='$H' bash -c 'source \"\$MP_HOME/core/common.sh\"; mp_days_between 2026-01-01 2026-03-01')\" = 59 ]"

echo "rules-only tools (zed, qwen)"
mkdir -p "$T/.qwen"; echo "# my qwen notes" > "$T/.qwen/QWEN.md"
bash "$ROOT/install.sh" --yes --agents claude,codex,gemini,zed,qwen >/dev/null 2>&1
t "zed: rules block created"   "grep -q 'read $V/RULES.md' '$T/.config/zed/AGENTS.md'"
t "qwen: block appended, notes kept" "grep -q mindpalace:start '$T/.qwen/QWEN.md' && grep -q '# my qwen notes' '$T/.qwen/QWEN.md'"
t "doctor healthy with 5 tools" "bash '$H/doctor.sh'"
t "summarizer still a full adapter" "grep -qE '^SUMMARY_AGENT=\"(claude|codex|gemini)\"' '$H/mindpalace.conf'"
t "plan lists rules-only tools" "bash '$ROOT/install.sh' --plan --agents zed | grep -q 'Zed agent.*RULES.md'"

echo "multiple vaults"
bash "$ROOT/install.sh" --yes --vault work="$T/WorkBrain" --projects work="$T/work-code" >/dev/null 2>&1
W="$T/WorkBrain"; mkdir -p "$T/work-code/api/src"
t "second vault added, first kept" "grep -qx 'VAULTS=\"brain work\"' '$H/mindpalace.conf' && grep -qx 'DEFAULT_VAULT=\"brain\"' '$H/mindpalace.conf' && [ -f '$V/journal/time.csv' ]"
t "new vault created + named"  "head -1 '$W/AGENTS.md' | grep -qx '# work' && grep -q 'This vault: .work. at' '$W/RULES.md'"
t "pointer files in new vault" "grep -qx '@AGENTS.md' '$W/CLAUDE.md' && grep -qx '@./AGENTS.md' '$W/GEMINI.md'"
t "rules block lists vaults"   "grep -q 'work = $W (projects: $T/work-code)' '$T/.claude/CLAUDE.md' && [ \$(grep -c mindpalace:start '$T/.claude/CLAUDE.md') = 1 ]"
t "memory: work vault"         "echo '{\"cwd\":\"$W\"}' | MINDPALACE_DOCTOR=1 bash '$H/adapters/claude/hooks/session-start.sh' | grep -q 'vault \"work\"'"
t "memory: work project"       "echo '{\"cwd\":\"$T/work-code/api/src\"}' | MINDPALACE_DOCTOR=1 bash '$H/adapters/claude/hooks/session-start.sh' | grep -q 'Project memory: api (vault \"work\"'"
t "memory: brain still brain"  "echo '{\"cwd\":\"$V\"}' | MINDPALACE_DOCTOR=1 bash '$H/adapters/claude/hooks/session-start.sh' | grep -q 'vault \"brain\"'"
MP_HOME="$H" bash "$H/core/summarize.sh" claude "$T/work-code/api" "$FX/claude.jsonl" s-work end >/dev/null 2>&1
t "work session → work journal" "grep -q '\[api\]' '$W/journal/'\$(date +%F).md && ! grep -q 's-work' '$V/journal/time.csv'"
t "guard: private of 2nd vault" "jq -n --arg c 'cat $W/private/x' '{tool_input:{command:\$c}}' | bash '$H/adapters/claude/hooks/guard.sh' | jq -e '.hookSpecificOutput.permissionDecisionReason | test(\"vault .work.\")'"
t "doctor: both vaults"        "bash '$H/doctor.sh' | grep -q \"vault 'work'\""
t "--default switches default" "bash '$ROOT/install.sh' --yes --default work >/dev/null 2>&1 && grep -qx 'DEFAULT_VAULT=\"work\"' '$H/mindpalace.conf'"

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
