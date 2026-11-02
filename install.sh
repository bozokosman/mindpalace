#!/bin/bash
# MindPalace installer for Claude Code.
#   ./install.sh                     interactive
#   ./install.sh --yes [options]     no questions, defaults for anything not given
#   ./install.sh --check             only check the OS and dependencies (exit 1 if something is missing)
#   ./install.sh --plan [options]    show what would be done, change nothing
# Options: --vault DIR  --projects DIR  --name NAME  --lang LANGUAGE  --no-rules  --no-git
# Windows: run from Git Bash (or use install.ps1, which finds Git Bash for you).
# Safe to run again: hooks are not duplicated, an existing vault or config is never overwritten.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
MP_HOME="$CLAUDE_DIR/mindpalace"
SETTINGS="$CLAUDE_DIR/settings.json"
GLOBAL_MD="$CLAUDE_DIR/CLAUDE.md"
STAMP=$(date +%Y%m%d-%H%M%S)
VERSION=$(cat "$SRC/VERSION")
MARK_START="<!-- mindpalace:start -->"; MARK_END="<!-- mindpalace:end -->"

yes=0; rules=1; usegit=1; checkonly=0; plan=0
vault=""; projects=""; name=""; lang=""
while [ $# -gt 0 ]; do
  case "$1" in
    --yes|-y) yes=1 ;;
    --check) checkonly=1 ;;
    --plan) plan=1; yes=1 ;;
    --vault) vault="$2"; shift ;;
    --projects) projects="$2"; shift ;;
    --name) name="$2"; shift ;;
    --lang) lang="$2"; shift ;;
    --no-rules) rules=0 ;;
    --no-git) usegit=0 ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

say()  { printf '\033[1m%s\033[0m\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
ask() {  # ask VAR "question" default
  local __v="$1" q="$2" d="$3" a=""
  if [ "$yes" = 1 ] || [ ! -t 0 ]; then printf -v "$__v" '%s' "$d"; return; fi
  read -r -p "  $q [$d]: " a || true
  printf -v "$__v" '%s' "${a:-$d}"
}
confirm() {  # confirm "question" -> 0 yes / 1 no (default yes)
  [ "$yes" = 1 ] && return 0
  [ -t 0 ] || return 0
  local a; read -r -p "  $1 [Y/n]: " a || true
  [[ ! "$a" =~ ^[nN] ]]
}
expand() { local p="$1"; p="${p/#\~/$HOME}"; printf '%s' "${p%/}"; }

say "MindPalace installer v$VERSION"

# 1. OS + dependencies
case "$(uname -s)" in
  Linux*)  OS=linux ;;
  Darwin*) OS=macos ;;
  MINGW*|MSYS*|CYGWIN*) OS=windows ;;
  *) OS=other ;;
esac
hint() {  # install command for a missing tool on this OS
  local t="$1"
  [ "$t" = claude ] && { echo "see https://claude.com/claude-code"; return; }
  case "$OS" in
    macos) echo "brew install $t" ;;
    windows) case "$t" in jq) echo "winget install jqlang.jq" ;; perl|bash) echo "install Git for Windows: winget install Git.Git" ;; *) echo "-" ;; esac ;;
    linux)
      if command -v apt-get >/dev/null; then echo "sudo apt-get install $t"
      elif command -v dnf >/dev/null; then echo "sudo dnf install $t"
      elif command -v pacman >/dev/null; then echo "sudo pacman -S $t"
      elif command -v zypper >/dev/null; then echo "sudo zypper install $t"
      else echo "install $t with your package manager"; fi ;;
    *) echo "install $t" ;;
  esac
}
say "1/5 System: $OS ($(uname -sr))"
[ "$OS" = other ] && warn "Untested OS. Linux, macOS and Windows (Git Bash) are supported."
missing=0
for c in bash jq perl claude; do
  if command -v "$c" >/dev/null; then ok "$c"; else warn "$c is missing (required) → $(hint "$c")"; missing=1; fi
done
for c in git; do
  command -v "$c" >/dev/null && ok "$c" || warn "$c not found (optional, used to version the vault) → $(hint "$c")"
done
if [ "$missing" = 1 ]; then
  echo "Install the missing tools and run again." >&2
  exit 1
fi
[ "$checkonly" = 1 ] && { say "All required tools found."; exit 0; }

# 2. Settings
say "2/5 Settings"
existing_conf=0
if [ -f "$MP_HOME/mindpalace.conf" ]; then
  existing_conf=1
  # shellcheck source=/dev/null
  ctmp=$(mktemp)
  ( source "$MP_HOME/mindpalace.conf"; printf '%s\n%s\n%s\n%s\n' "$VAULT" "$PROJECTS" "$USER_NAME" "$LANGUAGE" ) > "$ctmp" 2>/dev/null || true
  cv=""; cp=""; cn=""; cl=""
  { read -r cv; read -r cp; read -r cn; read -r cl; } < "$ctmp" || true
  rm -f "$ctmp"
  vault="${vault:-${cv:-}}"; projects="${projects:-${cp:-}}"; name="${name:-${cn:-}}"; lang="${lang:-${cl:-}}"
  ok "Existing config found, keeping it: $MP_HOME/mindpalace.conf"
fi
[ -n "$vault" ]    || ask vault    "Vault folder (your notes)" "~/MindPalace"
[ -n "$projects" ] || ask projects "Projects folder (your code)" "~/Projects"
[ -n "$name" ]     || ask name     "Your name" "$(id -un)"
[ -n "$lang" ]     || ask lang     "Language for notes and replies" "English"
vault=$(expand "$vault"); projects=$(expand "$projects")
ok "vault=$vault  projects=$projects  name=$name  language=$lang"
case "$vault" in *" "*) warn "The vault path contains spaces. Claude Code's @import may not handle it; a path without spaces is recommended." ;; esac
installed=""; [ -f "$MP_HOME/VERSION" ] && installed=$(cat "$MP_HOME/VERSION")

if [ "$plan" = 1 ]; then
  say "Plan (nothing is changed)"
  if [ -n "$installed" ]; then echo "  - update hooks in $MP_HOME ($installed → $VERSION)"; else echo "  - install hooks to $MP_HOME (v$VERSION)"; fi
  if [ "$existing_conf" = 1 ]; then echo "  - keep existing config $MP_HOME/mindpalace.conf"; else echo "  - write config $MP_HOME/mindpalace.conf"; fi
  if [ -d "$vault" ] && [ -n "$(ls -A "$vault" 2>/dev/null)" ]; then echo "  - vault exists, not touched: $vault"
  else echo "  - create vault from template: $vault (+ local git: $([ "$usegit" = 1 ] && echo yes || echo no))"; fi
  echo "  - back up $SETTINGS, then register 4 hooks (PreToolUse/Bash, SessionStart, SessionEnd, PreCompact); other hooks are kept"
  [ "$rules" = 1 ] && echo "  - add a managed block ($MARK_START … $MARK_END) importing $vault/RULES.md into $GLOBAL_MD (backup first)"
  exit 0
fi

# 3. Hooks + config
say "3/5 Installing hooks to $MP_HOME"
mkdir -p "$MP_HOME/state"
for f in common.sh guard.sh session-start.sh session-end.sh summarize.sh; do
  install -m 0755 "$SRC/hooks/$f" "$MP_HOME/$f"
done
cp "$SRC/VERSION" "$MP_HOME/VERSION"
cp "$SRC/doctor.sh" "$MP_HOME/doctor.sh"; chmod 0755 "$MP_HOME/doctor.sh"
if [ -n "$installed" ]; then ok "hooks updated ($installed → $VERSION)"; else ok "hooks copied (v$VERSION)"; fi
if [ "$existing_conf" = 0 ]; then
  esc() { printf '%s' "$1" | sed -e 's/[\/&|]/\\&/g' -e 's/"/\\"/g'; }
  sed -e "s|^VAULT=.*|VAULT=\"\${MP_VAULT:-$(esc "$vault")}\"|" \
      -e "s|^PROJECTS=.*|PROJECTS=\"$(esc "$projects")\"|" \
      -e "s|^USER_NAME=.*|USER_NAME=\"$(esc "$name")\"|" \
      -e "s|^LANGUAGE=.*|LANGUAGE=\"$(esc "$lang")\"|" \
      -e "s|^STATE=.*|STATE=\"\${MP_STATE:-$(esc "$MP_HOME")/state}\"|" \
      "$SRC/mindpalace.conf.example" > "$MP_HOME/mindpalace.conf"
  ok "config written: $MP_HOME/mindpalace.conf"
fi

# 4. Vault
say "4/5 Vault"
if [ -d "$vault" ] && [ -n "$(ls -A "$vault" 2>/dev/null)" ]; then
  ok "Vault already exists, left untouched: $vault"
else
  mkdir -p "$vault" "$projects"
  cp -R "$SRC/vault-template/." "$vault/"
  today=$(date +%F)
  export MP_R_NAME="$name" MP_R_LANG="$lang" MP_R_VAULT="$vault" MP_R_PROJ="$projects" MP_R_DATE="$today"
  find "$vault" -type f -name '*.md' -print0 | while IFS= read -r -d '' f; do
    perl -pi -e 's/\{\{USER_NAME\}\}/$ENV{MP_R_NAME}/g; s/\{\{LANGUAGE\}\}/$ENV{MP_R_LANG}/g; s/\{\{VAULT\}\}/$ENV{MP_R_VAULT}/g; s/\{\{PROJECTS\}\}/$ENV{MP_R_PROJ}/g; s/\{\{PRIVATE_DIR\}\}/private/g; s/\{\{DATE\}\}/$ENV{MP_R_DATE}/g' "$f"
  done
  ok "Vault created: $vault"
  if [ "$usegit" = 1 ] && command -v git >/dev/null && confirm "Track the vault with local git (no remote)?"; then
    git -C "$vault" init -q && git -C "$vault" add -A && \
      git -C "$vault" -c user.name="MindPalace" -c user.email="mindpalace@localhost" commit -qm "Initial vault" && ok "git initialized" || warn "git init failed, skipped"
  fi
fi

# 5. Claude Code settings
say "5/5 Claude Code settings"
mkdir -p "$CLAUDE_DIR"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
jq empty "$SETTINGS" 2>/dev/null || { echo "$SETTINGS is not valid JSON, fix it and run again." >&2; exit 1; }
if confirm "Add MindPalace hooks to $SETTINGS (a backup is made first)?"; then
  cp "$SETTINGS" "$SETTINGS.bak-mindpalace-$STAMP"
  hp="$MP_HOME"
  [ "$OS" = windows ] && command -v cygpath >/dev/null && hp=$(cygpath -m "$MP_HOME")   # C:/Users/... works in bash and cmd
  tmp=$(mktemp)
  jq --arg g "bash \"$hp/guard.sh\"" --arg s "bash \"$hp/session-start.sh\"" \
     --arg e "bash \"$hp/session-end.sh\" end" --arg c "bash \"$hp/session-end.sh\" compact" '
    def ours: (.hooks // []) | any(.command | test("/mindpalace/(guard|session-start|session-end)\\.sh"));
    def put($ev; $entry): .hooks[$ev] = (((.hooks[$ev] // []) | map(select(ours | not))) + [$entry]);
    .hooks = (.hooks // {})
    | put("PreToolUse";  {matcher:"Bash", hooks:[{type:"command", command:$g, timeout:5}]})
    | put("SessionStart";{hooks:[{type:"command", command:$s, timeout:10}]})
    | put("SessionEnd";  {hooks:[{type:"command", command:$e, timeout:10}]})
    | put("PreCompact";  {hooks:[{type:"command", command:$c, timeout:10}]})
  ' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
  ok "hooks registered (backup: $SETTINGS.bak-mindpalace-$STAMP)"
else
  warn "Skipped. Hooks will not run until they are added to settings.json (see README)."
fi

if [ "$rules" = 1 ]; then
  block=$(printf '%s\n# MindPalace (managed by install.sh, edit RULES.md in your vault instead)\n@%s/RULES.md\n%s' "$MARK_START" "$vault" "$MARK_END")
  if [ -f "$GLOBAL_MD" ] && grep -qF "$MARK_START" "$GLOBAL_MD"; then
    if confirm "Update the MindPalace block in $GLOBAL_MD?"; then
      cp "$GLOBAL_MD" "$GLOBAL_MD.bak-mindpalace-$STAMP"
      MP_BLOCK="$block" perl -0pi -e 's/<!-- mindpalace:start -->.*?<!-- mindpalace:end -->/$ENV{MP_BLOCK}/s' "$GLOBAL_MD"
      ok "rules block updated in $GLOBAL_MD"
    fi
  elif confirm "Import the shared rules into $GLOBAL_MD?"; then
    [ -f "$GLOBAL_MD" ] && cp "$GLOBAL_MD" "$GLOBAL_MD.bak-mindpalace-$STAMP"
    printf '\n%s\n' "$block" >> "$GLOBAL_MD"
    ok "rules imported: @$vault/RULES.md"
  fi
fi

say "Verifying"
bash "$MP_HOME/doctor.sh" || warn "doctor reported problems (see above)"

say "Done."
cat <<EOF
  Next:
    cd "$vault" && claude      # first session: Claude gets to know you and fills memory/profile.md
    mkdir -p "$projects/my-app" && cd "$projects/my-app" && claude   # project mode
  Settings: $MP_HOME/mindpalace.conf   Log: $MP_HOME/state/hook.log
  Check: bash "$MP_HOME/doctor.sh"   Uninstall: $SRC/uninstall.sh
EOF
