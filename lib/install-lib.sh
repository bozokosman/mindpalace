#!/bin/bash
# Helpers shared by install.sh, uninstall.sh and doctor.sh (and the adapters' install.sh files).
MARK_START="<!-- mindpalace:start -->"; MARK_END="<!-- mindpalace:end -->"
STAMP="${STAMP:-$(date +%Y%m%d-%H%M%S)}"

case "$(uname -s)" in
  Linux*)  OS=linux ;;
  Darwin*) OS=macos ;;
  MINGW*|MSYS*|CYGWIN*) OS=windows ;;
  *) OS=other ;;
esac

say()  { printf '\033[1m%s\033[0m\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$*"; FAIL=1; }

# confirm "question" -> 0 yes / 1 no. Default yes; --yes or no terminal = yes.
confirm() {
  [ "${YES:-0}" = 1 ] && return 0
  [ -t 0 ] || return 0
  local a; read -r -p "  $1 [Y/n]: " a || true
  [[ ! "$a" =~ ^[nN] ]]
}

# Path form written into agent config files (C:/Users/... on Windows works in bash and cmd).
mp_hook_path() {
  if [ "$OS" = windows ] && command -v cygpath >/dev/null; then cygpath -m "$1"; else printf '%s' "$1"; fi
}

# mp_rules_block <file> <body>: add or replace the managed block (backup first).
mp_rules_block() {
  local f="$1" block
  block=$(printf '%s\n# MindPalace (managed by install.sh; edit RULES.md in your vault instead)\n%s\n%s' "$MARK_START" "$2" "$MARK_END")
  mkdir -p "$(dirname "$f")"
  if [ -f "$f" ]; then
    cp "$f" "$f.bak-mindpalace-$STAMP"
    if grep -qF "$MARK_START" "$f"; then
      MP_BLOCK="$block" perl -0pi -e 's/<!-- mindpalace:start -->.*?<!-- mindpalace:end -->/$ENV{MP_BLOCK}/s' "$f"
      return 0
    fi
  fi
  printf '\n%s\n' "$block" >> "$f"
}

# mp_rules_unblock <file>: remove the managed block if present (backup first). 0 = removed.
mp_rules_unblock() {
  local f="$1"
  [ -f "$f" ] && grep -qF "$MARK_START" "$f" || return 1
  cp "$f" "$f.bak-mindpalace-$STAMP"
  perl -0pi -e 's/\n?<!-- mindpalace:start -->.*?<!-- mindpalace:end -->\n?/\n/s' "$f"
}

# Run an adapter function in a subshell: mp_with_adapter <adapters_dir> <agent> <function>
mp_with_adapter() {
  ( # shellcheck source=/dev/null
    source "$1/$2/install.sh" && "$3" )
}

# List adapters in priority order (first present one is the default summarizer).
mp_all_agents() {
  local a; for a in claude codex gemini; do [ -f "$1/$a/install.sh" ] && echo "$a"; done
  for a in "$1"/*/; do a=$(basename "$a"); case " claude codex gemini " in *" $a "*) ;; *) [ -f "$1/$a/install.sh" ] && echo "$a" ;; esac; done
}

# Rules-only adapter (tools that read a global instructions file but cannot run our hooks).
# In an adapter's install.sh:  mp_rules_only "<label>" "<cli>" "<global rules file>" "<url>"
# The block tells the tool to read RULES.md, whose "no hooks" section makes it load memory
# and write the journal itself.
mp_rules_only() {
  _RO_LABEL="$1"; _RO_CLI="$2"; _RO_FILE="$3"; _RO_URL="$4"
  adapter_label() { echo "$_RO_LABEL (rules only)"; }
  adapter_cli()   { echo "$_RO_CLI"; }
  adapter_url()   { echo "$_RO_URL"; }
  adapter_plan()  { echo "  - [$_RO_LABEL] managed block in $_RO_FILE telling it to read \$VAULT/RULES.md (backup first; no hooks: memory works through the rules)"; }
  adapter_install() {
    mp_rules_block "$_RO_FILE" "At the start of every session, read $VAULT/RULES.md and follow it, including its section \"If your tool has no MindPalace hooks\". Vault: $VAULT" \
      && ok "$_RO_LABEL: rules block added to $_RO_FILE"
  }
  adapter_uninstall() { mp_rules_unblock "$_RO_FILE" && ok "$_RO_LABEL: rules block removed from $_RO_FILE"; return 0; }
  adapter_doctor() {
    grep -qF "$MARK_START" "$_RO_FILE" 2>/dev/null && ok "$_RO_LABEL: rules block in $_RO_FILE" || bad "$_RO_LABEL: rules block missing in $_RO_FILE (run install.sh)"
  }
}
