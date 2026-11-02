#!/bin/bash
# MindPalace installer. Works for Claude Code, Codex CLI and Gemini CLI (one or several).
#   ./install.sh                     interactive
#   ./install.sh --check             check the OS, dependencies and which AI tools are installed
#   ./install.sh --plan [options]    show what would be done, change nothing
#   ./install.sh --yes [options]     no questions; defaults for anything not given
# Options: --agents LIST (e.g. claude,codex; default: every supported tool found)
#          --vault DIR  --projects DIR  --name NAME  --lang LANGUAGE  --no-rules  --no-git
# Windows: run from Git Bash, or use install.ps1 (it finds Git Bash for you).
# Safe to run again: nothing is duplicated, an existing vault or config is never overwritten.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/install-lib.sh
source "$SRC/lib/install-lib.sh"
MP_HOME="${MP_HOME:-$HOME/.mindpalace}"
VERSION=$(cat "$SRC/VERSION")
ADIR="$SRC/adapters"

YES=0; RULES=1; usegit=1; checkonly=0; plan=0
vault=""; projects=""; name=""; lang=""; agents=""
while [ $# -gt 0 ]; do
  case "$1" in
    --yes|-y) YES=1 ;;
    --check) checkonly=1 ;;
    --plan) plan=1; YES=1 ;;
    --agents) agents="$2"; shift ;;
    --vault) vault="$2"; shift ;;
    --projects) projects="$2"; shift ;;
    --name) name="$2"; shift ;;
    --lang) lang="$2"; shift ;;
    --no-rules) RULES=0 ;;
    --no-git) usegit=0 ;;
    -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done
export YES RULES

ask() {  # ask VAR "question" default
  local __v="$1" q="$2" d="$3" a=""
  if [ "$YES" = 1 ] || [ ! -t 0 ]; then printf -v "$__v" '%s' "$d"; return; fi
  read -r -p "  $q [$d]: " a || true
  printf -v "$__v" '%s' "${a:-$d}"
}
expand() { local p="$1"; p="${p/#\~/$HOME}"; printf '%s' "${p%/}"; }
hint() {  # install command for a missing tool on this OS
  local t="$1"
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

say "MindPalace installer v$VERSION"

# 1. OS, dependencies, AI tools
say "1/6 System: $OS ($(uname -sr))"
[ "$OS" = other ] && warn "Untested OS. Linux, macOS and Windows (Git Bash) are supported."
missing=0
for c in bash jq perl; do
  if command -v "$c" >/dev/null; then ok "$c"; else warn "$c is missing (required) → $(hint "$c")"; missing=1; fi
done
command -v git >/dev/null && ok "git" || warn "git not found (optional, versions the vault) → $(hint git)"

found=""
for a in $(mp_all_agents "$ADIR"); do
  cli=$(mp_with_adapter "$ADIR" "$a" adapter_cli); label=$(mp_with_adapter "$ADIR" "$a" adapter_label)
  if command -v "$cli" >/dev/null; then ok "AI tool found: $label ($a)"; found="$found $a"
  else echo "    - not found: $label ($cli)"; fi
done
found=$(echo $found)
[ -z "$found" ] && warn "No supported AI tool found. Install one first, or pass --agents to prepare anyway."
if [ "$missing" = 1 ]; then echo "Install the missing tools and run again." >&2; exit 1; fi
if [ "$checkonly" = 1 ]; then
  say "Ready. Supported AI tools found: ${found:-none}"
  [ -n "$found" ] && exit 0 || exit 1
fi

# 2. Settings
say "2/6 Settings"
existing_conf=0
if [ -f "$MP_HOME/mindpalace.conf" ]; then
  existing_conf=1
  ctmp=$(mktemp)
  ( source "$MP_HOME/mindpalace.conf"; printf '%s\n%s\n%s\n%s\n%s\n' "$VAULT" "$PROJECTS" "$USER_NAME" "$LANGUAGE" "${AGENTS:-}" ) > "$ctmp" 2>/dev/null || true
  cv=""; cp_=""; cn=""; cl=""; ca=""
  { read -r cv; read -r cp_; read -r cn; read -r cl; read -r ca; } < "$ctmp" || true
  rm -f "$ctmp"
  vault="${vault:-$cv}"; projects="${projects:-$cp_}"; name="${name:-$cn}"; lang="${lang:-$cl}"; agents="${agents:-$ca}"
  ok "Existing config found and kept: $MP_HOME/mindpalace.conf"
fi
[ -n "$vault" ]    || ask vault    "Vault folder (your notes)" "~/MindPalace"
[ -n "$projects" ] || ask projects "Projects folder (your code)" "~/Projects"
[ -n "$name" ]     || ask name     "Your name" "$(id -un)"
[ -n "$lang" ]     || ask lang     "Language for notes and replies" "English"
[ -n "$agents" ]   || ask agents   "Connect which AI tools (comma separated)" "$(echo $found | tr ' ' ',')"
vault=$(expand "$vault"); projects=$(expand "$projects")
agents=$(echo "$agents" | tr ',' ' ' | xargs)
[ -n "$agents" ] || { echo "No AI tool selected. Pass --agents (supported: $(mp_all_agents "$ADIR" | xargs))." >&2; exit 2; }
for a in $agents; do
  [ -f "$ADIR/$a/install.sh" ] || { echo "Unknown agent: $a (supported: $(mp_all_agents "$ADIR" | xargs))" >&2; exit 2; }
done
summary_agent=""
for a in $agents; do [ -f "$ADIR/$a/adapter.sh" ] || continue; case " $found " in *" $a "*) summary_agent="$a"; break ;; esac; done
if [ -z "$summary_agent" ]; then for a in $agents; do [ -f "$ADIR/$a/adapter.sh" ] && { summary_agent="$a"; break; }; done; fi
ok "vault=$vault  projects=$projects  name=$name  language=$lang"
ok "agents=$agents  (summaries written by: ${summary_agent:-none, rules-only tools write the journal themselves})"
for a in $agents; do case " $found " in *" $a "*) ;; *) warn "$a is not installed yet; its hooks are prepared but only work once it is." ;; esac; done
case "$vault" in *" "*) warn "The vault path contains spaces. Some tools' @import may not handle it; a path without spaces is recommended." ;; esac
installed=""; [ -f "$MP_HOME/VERSION" ] && installed=$(cat "$MP_HOME/VERSION")
VAULT="$vault"; export VAULT MP_HOME

if [ "$plan" = 1 ]; then
  say "Plan (nothing is changed)"
  if [ -n "$installed" ]; then echo "  - update MindPalace in $MP_HOME ($installed → $VERSION)"; else echo "  - install MindPalace to $MP_HOME (v$VERSION)"; fi
  if [ "$existing_conf" = 1 ]; then echo "  - keep config $MP_HOME/mindpalace.conf (agent list set to: $agents)"; else echo "  - write config $MP_HOME/mindpalace.conf"; fi
  if [ -d "$vault" ] && [ -n "$(ls -A "$vault" 2>/dev/null)" ]; then echo "  - vault exists, notes not touched: $vault"
  else echo "  - create vault from template: $vault (local git: $([ "$usegit" = 1 ] && echo yes || echo no))"; fi
  for a in $agents; do mp_with_adapter "$ADIR" "$a" adapter_plan | MP_V="$vault" perl -pe 's/\$VAULT/$ENV{MP_V}/g'; done
  exit 0
fi

# 3. Files + config
say "3/6 Installing to $MP_HOME"
mkdir -p "$MP_HOME/state"
rm -rf "$MP_HOME/core" "$MP_HOME/adapters" "$MP_HOME/lib"
cp -R "$SRC/core" "$SRC/adapters" "$SRC/lib" "$MP_HOME/"
cp "$SRC/VERSION" "$SRC/doctor.sh" "$SRC/uninstall.sh" "$MP_HOME/"
chmod 0755 "$MP_HOME"/*.sh "$MP_HOME"/core/*.sh; chmod 0755 "$MP_HOME"/adapters/*/hooks/*.sh 2>/dev/null || true
[ -f "$MP_HOME/state/.installed" ] || touch "$MP_HOME/state/.installed"
if [ -n "$installed" ]; then ok "updated ($installed → $VERSION)"; else ok "files copied (v$VERSION)"; fi
esc() { printf '%s' "$1" | sed -e 's/[\/&|]/\\&/g' -e 's/"/\\"/g'; }
if [ "$existing_conf" = 0 ]; then
  sed -e "s|^VAULT=.*|VAULT=\"\${MP_VAULT:-$(esc "$vault")}\"|" \
      -e "s|^PROJECTS=.*|PROJECTS=\"$(esc "$projects")\"|" \
      -e "s|^USER_NAME=.*|USER_NAME=\"$(esc "$name")\"|" \
      -e "s|^LANGUAGE=.*|LANGUAGE=\"$(esc "$lang")\"|" \
      -e "s|^AGENTS=.*|AGENTS=\"$agents\"|" \
      -e "s|^SUMMARY_AGENT=.*|SUMMARY_AGENT=\"$summary_agent\"|" \
      -e "s|^STATE=.*|STATE=\"\${MP_STATE:-$(esc "$MP_HOME")/state}\"|" \
      "$SRC/mindpalace.conf.example" > "$MP_HOME/mindpalace.conf"
  ok "config written: $MP_HOME/mindpalace.conf"
else
  ctmp=$(mktemp)
  sed -e "s|^AGENTS=.*|AGENTS=\"$agents\"|" "$MP_HOME/mindpalace.conf" > "$ctmp" && cat "$ctmp" > "$MP_HOME/mindpalace.conf"; rm -f "$ctmp"
  grep -q '^AGENTS=' "$MP_HOME/mindpalace.conf" || printf '\nAGENTS="%s"\nSUMMARY_AGENT="%s"\n' "$agents" "$summary_agent" >> "$MP_HOME/mindpalace.conf"
fi

# 4. Vault
say "4/6 Vault"
newvault=0
if [ -d "$vault" ] && [ -n "$(ls -A "$vault" 2>/dev/null)" ]; then
  ok "Vault already exists, notes left untouched: $vault"
else
  mkdir -p "$vault" "$projects"
  cp -R "$SRC/vault-template/." "$vault/"
  export MP_R_NAME="$name" MP_R_LANG="$lang" MP_R_VAULT="$vault" MP_R_PROJ="$projects" MP_R_DATE="$(date +%F)"
  find "$vault" -type f -name '*.md' -print0 | while IFS= read -r -d '' f; do
    perl -pi -e 's/\{\{USER_NAME\}\}/$ENV{MP_R_NAME}/g; s/\{\{LANGUAGE\}\}/$ENV{MP_R_LANG}/g; s/\{\{VAULT\}\}/$ENV{MP_R_VAULT}/g; s/\{\{PROJECTS\}\}/$ENV{MP_R_PROJ}/g; s/\{\{PRIVATE_DIR\}\}/private/g; s/\{\{DATE\}\}/$ENV{MP_R_DATE}/g' "$f"
  done
  ok "Vault created: $vault"
  newvault=1
fi

# 5. Connect AI tools
say "5/6 Connecting AI tools"
for a in $agents; do
  label=$(mp_with_adapter "$ADIR" "$a" adapter_label)
  if confirm "Connect $label (its config is backed up first)?"; then
    ( source "$MP_HOME/adapters/$a/install.sh" && adapter_install ) || warn "$label: connection failed (see above)"
  else
    warn "$label skipped"
  fi
done
if [ "$newvault" = 1 ] && [ "$usegit" = 1 ] && command -v git >/dev/null && confirm "Track the vault with local git (no remote)?"; then
  { git -C "$vault" init -q && git -C "$vault" add -A && \
    git -C "$vault" -c user.name="MindPalace" -c user.email="mindpalace@localhost" commit -qm "Initial vault"; } && ok "vault git initialized" || warn "git init failed, skipped"
fi

# 6. Verify
say "6/6 Verifying"
bash "$MP_HOME/doctor.sh" || warn "doctor reported problems (see above)"

say "Done."
cat <<EOF
  Restart your AI tool(s) so the hooks and rules load.
  Next:  cd "$vault"  and start your AI tool there. In the first session it gets to know you.
  Settings: $MP_HOME/mindpalace.conf   Log: $MP_HOME/state/hook.log
  Check: bash "$MP_HOME/doctor.sh"   Uninstall: bash "$MP_HOME/uninstall.sh"
EOF
