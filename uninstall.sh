#!/bin/bash
# Removes MindPalace hooks from Claude Code. Your vault (notes) is never touched.
#   ./uninstall.sh [--yes]
set -euo pipefail
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
MP_HOME="$CLAUDE_DIR/mindpalace"
SETTINGS="$CLAUDE_DIR/settings.json"
GLOBAL_MD="$CLAUDE_DIR/CLAUDE.md"
STAMP=$(date +%Y%m%d-%H%M%S)
yes=0; [ "${1:-}" = "--yes" ] || [ "${1:-}" = "-y" ] && yes=1

confirm() { [ "$yes" = 1 ] && return 0; local a; read -r -p "$1 [y/N]: " a || true; [[ "$a" =~ ^[yY] ]]; }

confirm "Remove MindPalace hooks from $SETTINGS and delete $MP_HOME? (vault stays)" || { echo "Cancelled."; exit 0; }

if [ -f "$SETTINGS" ]; then
  cp "$SETTINGS" "$SETTINGS.bak-mindpalace-$STAMP"
  tmp=$(mktemp)
  jq '
    def ours: (.hooks // []) | any(.command | test("/mindpalace/(guard|session-start|session-end)\\.sh"));
    if .hooks then
      .hooks |= (with_entries(.value |= map(select(ours | not))) | with_entries(select(.value | length > 0)))
      | if .hooks == {} then del(.hooks) else . end
    else . end
  ' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
  echo "✓ hooks removed (backup: $SETTINGS.bak-mindpalace-$STAMP)"
fi

if [ -f "$GLOBAL_MD" ] && grep -qF '<!-- mindpalace:start -->' "$GLOBAL_MD"; then
  cp "$GLOBAL_MD" "$GLOBAL_MD.bak-mindpalace-$STAMP"
  perl -0pi -e 's/\n?<!-- mindpalace:start -->.*?<!-- mindpalace:end -->\n?/\n/s' "$GLOBAL_MD"
  echo "✓ rules block removed from $GLOBAL_MD"
fi

[ -d "$MP_HOME" ] && mv "$MP_HOME" "$MP_HOME.removed-$STAMP" && echo "✓ $MP_HOME moved to $MP_HOME.removed-$STAMP"
echo "Done. Your vault was not touched."
