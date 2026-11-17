#!/bin/bash
# Background recovery, started by the session-start hook. Usage: recover.sh <agent> [current_session_id]
#  1. summarize this agent's recent sessions that never got a session-end (window closed, crash)
#  2. start the maintainer for every vault that has pending work
# Never writes to stdout of the hook: it is detached and logs to state/hook.log.
export MINDPALACE_HOOK=1
source "$(cd "$(dirname "$0")" && pwd)/common.sh"
agent="$1"; now="${2:-}"
mp_adapter "$agent" || exit 0
mkdir -p "$STATE"
mp_lock_acquire "$STATE/recover-$agent.pid" || exit 0     # one recovery per tool at a time
trap 'mp_lock_release "$STATE/recover-$agent.pid"' EXIT
mp_catchup "$agent" "$now"
for n in $VAULTS; do mp_maintain_bg "$n" --if-pending; done
exit 0
