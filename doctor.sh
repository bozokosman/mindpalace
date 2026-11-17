#!/bin/bash
# MindPalace health check. Exit 0 = healthy, 1 = something needs fixing.
#   bash ~/.mindpalace/doctor.sh
D="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MP_HOME="${MP_HOME:-$HOME/.mindpalace}"
[ -f "$D/lib/install-lib.sh" ] && LIB="$D/lib/install-lib.sh" || LIB="$MP_HOME/lib/install-lib.sh"
# shellcheck source=lib/install-lib.sh
source "$LIB"
FAIL=0

echo "MindPalace doctor"
for c in bash jq perl; do command -v "$c" >/dev/null && ok "$c found" || bad "$c missing"; done
[ -f "$MP_HOME/VERSION" ] && ok "installed version $(cat "$MP_HOME/VERSION") in $MP_HOME" || { bad "not installed in $MP_HOME (run install.sh)"; exit 1; }
for f in core/common.sh core/memory.sh core/guard-rules.sh core/summarize.sh core/recover.sh; do [ -f "$MP_HOME/$f" ] || bad "missing $MP_HOME/$f"; done
[ -f "$MP_HOME/mindpalace.conf" ] || { bad "config missing: $MP_HOME/mindpalace.conf"; exit 1; }
# shellcheck source=/dev/null
source "$MP_HOME/mindpalace.conf"; ok "config $MP_HOME/mindpalace.conf"
_k=$(printf '%s' "${DEFAULT_VAULT:-${VAULTS%% *}}" | tr '-' '_'); eval "VAULT=\${VAULT_$_k:-\${VAULT:-}}"; export VAULT MP_HOME

for a in $AGENTS; do
  f="$MP_HOME/adapters/$a/install.sh"
  [ -f "$f" ] || { bad "unknown agent in config: $a"; continue; }
  ( source "$f"
    command -v "$(adapter_cli)" >/dev/null && ok "$(adapter_label): $(adapter_cli) found" || warn "$(adapter_label): $(adapter_cli) not installed"
    FAIL=0; adapter_doctor; exit $FAIL ) || FAIL=1
done
[ -n "${SUMMARY_AGENT:-}" ] && [ -f "$MP_HOME/adapters/$SUMMARY_AGENT/adapter.sh" ] && { command -v "$(source "$MP_HOME/adapters/$SUMMARY_AGENT/install.sh"; adapter_cli)" >/dev/null \
  && ok "summaries written by: $SUMMARY_AGENT" || bad "SUMMARY_AGENT=$SUMMARY_AGENT is not installed; set another one in the config"; }

if [ "${MAINTAIN:-on}" = off ]; then ok "maintainer: off"
elif [ -z "${MAINTAIN_AGENT:-}" ]; then warn "maintainer: no connected tool supports it safely (needs Claude Code); it stays off"
elif ! grep -q '^mp_agent_edit()' "$MP_HOME/adapters/$MAINTAIN_AGENT/adapter.sh" 2>/dev/null; then warn "maintainer: unsupported for $MAINTAIN_AGENT (no safe file-edit mode); it stays off"
else ok "maintainer: on, run by $MAINTAIN_AGENT (AUTO_COMMIT=${AUTO_COMMIT:-on}, never pushes)"; fi
for f in core/maintain.sh core/lessons.sh core/prompts/maintain.md; do [ -f "$MP_HOME/$f" ] || bad "missing $MP_HOME/$f"; done

if [ -z "${VAULTS:-}" ] && [ -n "${VAULT:-}" ]; then VAULTS=main; DEFAULT_VAULT=main; VAULT_main="$VAULT"; PROJECTS_main="${PROJECTS:-}"; fi
[ -n "${VAULTS:-}" ] || bad "no vaults in the config"
for n in $VAULTS; do
  k=$(printf '%s' "$n" | tr '-' '_'); eval "v=\${VAULT_$k:-}"; eval "p=\${PROJECTS_$k:-}"
  if [ -d "$v" ]; then
    ok "vault '$n'$([ "$n" = "${DEFAULT_VAULT:-}" ] && echo ' [default]'): $v${p:+  (projects: $p)}"
    for d in inbox projects knowledge toolbox memory journal archive; do [ -d "$v/$d" ] || warn "vault '$n': folder missing: $d/"; done
    for f in INDEX.md RULES.md AGENTS.md memory/profile.md; do [ -f "$v/$f" ] || warn "vault '$n': file missing: $f"; done
    [ -n "$p" ] && [ ! -d "$p" ] && warn "vault '$n': projects folder does not exist yet: $p"
    out=$(MP_HOME="$MP_HOME" MINDPALACE_DOCTOR=1 bash -c 'source "$MP_HOME/core/common.sh"; source "$MP_HOME/core/memory.sh"; mp_memory "$1"' _ "$v" 2>&1)
    grep -q "vault \"$n\"" <<<"$out" && ok "vault '$n': memory loads (${#out} chars)" || bad "vault '$n': memory produced no output"
  else
    bad "vault '$n' not found: $v"
  fi
done
mkdir -p "$STATE" 2>/dev/null && [ -w "$STATE" ] && ok "state dir writable" || bad "state dir not writable: $STATE"
if [ -f "$STATE/hook.log" ]; then
  errs=$(grep -c 'ERROR' "$STATE/hook.log" 2>/dev/null || true)
  [ "${errs:-0}" -gt 0 ] && warn "$errs ERROR lines in $STATE/hook.log (last: $(grep 'ERROR' "$STATE/hook.log" | tail -1))"
fi

[ "$FAIL" = 0 ] && echo "Healthy." || echo "Problems found."
exit "$FAIL"
