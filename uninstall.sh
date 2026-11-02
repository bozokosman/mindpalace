#!/bin/bash
# Disconnects MindPalace from every AI tool it was connected to. Your vault (notes) is never touched.
#   bash ~/.mindpalace/uninstall.sh [--yes]
set -euo pipefail
MP_HOME="${MP_HOME:-$HOME/.mindpalace}"
D="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$D/lib/install-lib.sh" ] && LIB="$D/lib/install-lib.sh" || LIB="$MP_HOME/lib/install-lib.sh"
# shellcheck source=lib/install-lib.sh
source "$LIB"
YES=0; [ "${1:-}" = "--yes" ] || [ "${1:-}" = "-y" ] && YES=1

[ -f "$MP_HOME/mindpalace.conf" ] || { echo "MindPalace is not installed in $MP_HOME."; exit 0; }
# shellcheck source=/dev/null
VAULT=""; AGENTS=""; source "$MP_HOME/mindpalace.conf"; export VAULT MP_HOME YES

if [ "$YES" != 1 ]; then
  read -r -p "Disconnect MindPalace from: $AGENTS, and move $MP_HOME aside? Your vault stays. [y/N]: " a || true
  [[ "$a" =~ ^[yY] ]] || { echo "Cancelled."; exit 0; }
fi
for a in $AGENTS; do
  f="$MP_HOME/adapters/$a/install.sh"
  [ -f "$f" ] && ( source "$f" && adapter_uninstall ) || warn "$a: nothing to remove"
done
dest="$MP_HOME.removed-$STAMP"
mv "$MP_HOME" "$dest" && ok "$MP_HOME moved to $dest (delete it when you are sure)"
echo "Done. Your vault was not touched: $VAULT"
