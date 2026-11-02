#!/bin/bash
# MindPalace installer. Works for Claude Code, Codex CLI and Gemini CLI (one or several).
#   ./install.sh                     interactive
#   ./install.sh --check             check the OS, dependencies and which AI tools are installed
#   ./install.sh --plan [options]    show what would be done, change nothing
#   ./install.sh --yes [options]     no questions; defaults for anything not given
# Options: --agents LIST (e.g. claude,codex; default: every supported tool found)
#          --vault NAME=DIR (repeat for several vaults; adds to existing ones)  --projects NAME=DIR
#          --default NAME  --name YOUR_NAME  --lang LANGUAGE  --no-rules  --no-git
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
vault_args=(); projects_args=(); default_cli=""; name=""; lang=""; agents=""
while [ $# -gt 0 ]; do
  case "$1" in
    --yes|-y) YES=1 ;;
    --check) checkonly=1 ;;
    --plan) plan=1; YES=1 ;;
    --agents) agents="$2"; shift ;;
    --vault) vault_args+=("$2"); shift ;;
    --projects) projects_args+=("$2"); shift ;;
    --default) default_cli="$2"; shift ;;
    --name) name="$2"; shift ;;
    --lang) lang="$2"; shift ;;
    --no-rules) RULES=0 ;;
    --no-git) usegit=0 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
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
valid_name() { [[ "$1" =~ ^[A-Za-z][A-Za-z0-9_-]*$ ]]; }
vkey() { printf '%s' "$1" | tr '-' '_'; }
# Vault table: names in $vnames, folders/projects in vf_<key>, vp_<key>
vnames=""
vset() {  # vset name folder projects
  local k; k=$(vkey "$1")
  case " $vnames " in *" $1 "*) ;; *) vnames="$vnames $1" ;; esac
  [ -n "$2" ] && eval "vf_$k=\$2"
  [ -n "${3+x}" ] && eval "vp_$k=\$3"
  return 0
}
vget() { local k; k=$(vkey "$1"); eval "printf '%s' \"\${v$2_$k:-}\""; }

existing_conf=0
if [ -f "$MP_HOME/mindpalace.conf" ]; then
  existing_conf=1
  ctmp=$(mktemp)
  ( source "$MP_HOME/mindpalace.conf"
    if [ -z "${VAULTS:-}" ] && [ -n "${VAULT:-}" ]; then VAULTS=main; DEFAULT_VAULT=main; VAULT_main="$VAULT"; PROJECTS_main="${PROJECTS:-}"; fi
    printf '%s\n%s\n%s\n%s\n' "$USER_NAME" "$LANGUAGE" "${AGENTS:-}" "${DEFAULT_VAULT:-}"
    for n in $VAULTS; do k=$(printf '%s' "$n" | tr '-' '_'); eval "printf '%s|%s|%s\n' \"\$n\" \"\${VAULT_$k:-}\" \"\${PROJECTS_$k:-}\""; done
  ) > "$ctmp" 2>/dev/null || true
  { read -r cn; read -r cl; read -r ca; read -r cd_; } < "$ctmp" || true
  name="${name:-$cn}"; lang="${lang:-$cl}"; agents="${agents:-$ca}"; default_vault="${default_vault:-$cd_}"
  while IFS='|' read -r n v p; do [ -n "$n" ] && vset "$n" "$v" "$p"; done < <(tail -n +5 "$ctmp")
  rm -f "$ctmp"
  ok "Existing config found and kept: $MP_HOME/mindpalace.conf (vaults:$vnames)"
fi

# Vaults given on the command line: --vault NAME=PATH (or a bare PATH), --projects NAME=PATH (or a bare PATH for the first one)
first_cli=""
for spec in "${vault_args[@]+"${vault_args[@]}"}"; do
  case "$spec" in *=*) n="${spec%%=*}"; v="${spec#*=}" ;; *) v="$spec"; n=$(basename "$v" | tr -cd 'A-Za-z0-9_-'); n="${n:-brain}" ;; esac
  valid_name "$n" || { echo "Invalid vault name '$n': use letters, digits, - or _ (start with a letter)." >&2; exit 2; }
  vset "$n" "$v"; first_cli="${first_cli:-$n}"
done
for spec in "${projects_args[@]+"${projects_args[@]}"}"; do
  case "$spec" in *=*) n="${spec%%=*}"; p="${spec#*=}" ;; *) n="${first_cli:-${default_vault:-$(echo $vnames | cut -d' ' -f1)}}"; p="$spec" ;; esac
  [ -n "$n" ] || { echo "--projects needs a vault: pass --vault first or use NAME=PATH." >&2; exit 2; }
  vset "$n" "" "$p"
done

# Nothing known yet: ask (or use one default vault)
if [ -z "$vnames" ]; then
  ask names "Vault names, space separated (e.g. personal work)" "brain"
  for n in $names; do valid_name "$n" || { echo "Invalid vault name '$n': use letters, digits, - or _ (start with a letter)." >&2; exit 2; }; vset "$n" ""; done
fi
first=""
for n in $vnames; do
  first="${first:-$n}"
  [ -n "$(vget "$n" f)" ] || { ask v "Folder for vault '$n'" "~/$n"; vset "$n" "$v"; }
  if [ -z "$(vget "$n" p)" ] && [ -z "$(k=$(vkey "$n"); eval "printf '%s' \"\${vp_$k+set}\"")" ]; then
    if [ "$n" = "$first" ]; then d="~/Projects"; else d=""; fi
    ask p "Projects folder for vault '$n' (empty = none)" "$d"; vset "$n" "" "$p"
  fi
done
default_vault="${default_vault:-$first}"
[ -n "$default_cli" ] && default_vault="$default_cli"
case " $vnames " in *" $default_vault "*) ;; *) echo "Default vault '$default_vault' is not in the vault list:$vnames" >&2; exit 2 ;; esac

[ -n "$name" ]     || ask name     "Your name" "$(id -un)"
[ -n "$lang" ]     || ask lang     "Language for notes and replies" "English"
[ -n "$agents" ]   || ask agents   "Connect which AI tools (comma separated)" "$(echo $found | tr ' ' ',')"
agents=$(echo "$agents" | tr ',' ' ' | xargs)
[ -n "$agents" ] || { echo "No AI tool selected. Pass --agents (supported: $(mp_all_agents "$ADIR" | xargs))." >&2; exit 2; }
for a in $agents; do
  [ -f "$ADIR/$a/install.sh" ] || { echo "Unknown agent: $a (supported: $(mp_all_agents "$ADIR" | xargs))" >&2; exit 2; }
done
summary_agent=""
for a in $agents; do [ -f "$ADIR/$a/adapter.sh" ] || continue; case " $found " in *" $a "*) summary_agent="$a"; break ;; esac; done
if [ -z "$summary_agent" ]; then for a in $agents; do [ -f "$ADIR/$a/adapter.sh" ] && { summary_agent="$a"; break; }; done; fi

# Final vault list, default first: "name|folder|projects"
MP_VAULT_LIST=""
for n in $default_vault $vnames; do
  case "$MP_VAULT_LIST" in "$n|"*|*$'\n'"$n|"*) continue ;; esac
  v=$(expand "$(vget "$n" f)"); p=$(vget "$n" p); [ -n "$p" ] && p=$(expand "$p")
  vset "$n" "$v" "$p"
  MP_VAULT_LIST="${MP_VAULT_LIST:+$MP_VAULT_LIST$'\n'}$n|$v|$p"
done
VAULT=$(vget "$default_vault" f)
export VAULT MP_HOME MP_VAULT_LIST
while IFS='|' read -r n v p; do
  ok "vault $n: $v${p:+  (projects: $p)}$([ "$n" = "$default_vault" ] && echo '  [default]')"
  case "$v" in *" "*) warn "Vault '$n' path contains spaces. Some tools' @import may not handle it; a path without spaces is recommended." ;; esac
done <<<"$MP_VAULT_LIST"
ok "name=$name  language=$lang"
ok "agents=$agents  (summaries written by: ${summary_agent:-none, rules-only tools write the journal themselves})"
for a in $agents; do case " $found " in *" $a "*) ;; *) warn "$a is not installed yet; its hooks are prepared but only work once it is." ;; esac; done
installed=""; [ -f "$MP_HOME/VERSION" ] && installed=$(cat "$MP_HOME/VERSION")
vault_is_new() { [ ! -d "$1" ] || [ -z "$(ls -A "$1" 2>/dev/null)" ]; }

if [ "$plan" = 1 ]; then
  say "Plan (nothing is changed)"
  if [ -n "$installed" ]; then echo "  - update MindPalace in $MP_HOME ($installed → $VERSION)"; else echo "  - install MindPalace to $MP_HOME (v$VERSION)"; fi
  if [ "$existing_conf" = 1 ]; then echo "  - update config $MP_HOME/mindpalace.conf (vaults and agent list; other settings kept)"; else echo "  - write config $MP_HOME/mindpalace.conf"; fi
  while IFS='|' read -r n v p; do
    if vault_is_new "$v"; then echo "  - create vault '$n' from template: $v (local git: $([ "$usegit" = 1 ] && echo yes || echo no))"
    else echo "  - vault '$n' exists, notes not touched: $v"; fi
  done <<<"$MP_VAULT_LIST"
  for a in $agents; do mp_with_adapter "$ADIR" "$a" adapter_plan | MP_V="$VAULT" perl -pe 's/\$VAULT/$ENV{MP_V}/g'; done
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
q() { printf '%s' "$1" | sed -e 's/["\\$`]/\\&/g'; }   # for "..." in the config
vault_block() {
  printf '# Vaults (managed by install.sh; add one with: install.sh --vault NAME=PATH)\n'
  printf 'VAULTS="%s"\nDEFAULT_VAULT="%s"\n' "$(printf '%s\n' "$MP_VAULT_LIST" | cut -d'|' -f1 | xargs)" "$default_vault"
  while IFS='|' read -r n v p; do
    printf 'VAULT_%s="%s"\nPROJECTS_%s="%s"\n' "$(vkey "$n")" "$(q "$v")" "$(vkey "$n")" "$(q "$p")"
  done <<<"$MP_VAULT_LIST"
}
ctmp=$(mktemp)
if [ "$existing_conf" = 0 ]; then
  sed -e "s|^USER_NAME=.*|USER_NAME=\"$(esc "$name")\"|" \
      -e "s|^LANGUAGE=.*|LANGUAGE=\"$(esc "$lang")\"|" \
      -e "s|^AGENTS=.*|AGENTS=\"$agents\"|" \
      -e "s|^SUMMARY_AGENT=.*|SUMMARY_AGENT=\"$summary_agent\"|" \
      -e "s|^STATE=.*|STATE=\"\${MP_STATE:-$(esc "$MP_HOME")/state}\"|" \
      "$SRC/mindpalace.conf.example" > "$ctmp"
else
  sed -e "s|^AGENTS=.*|AGENTS=\"$agents\"|" "$MP_HOME/mindpalace.conf" > "$ctmp"
  grep -q '^AGENTS=' "$ctmp" || printf '\nAGENTS="%s"\nSUMMARY_AGENT="%s"\n' "$agents" "$summary_agent" >> "$ctmp"
fi
# replace the vault section (and old single-vault VAULT=/PROJECTS= lines)
grep -v -E '^(# Vaults \(managed|VAULTS=|DEFAULT_VAULT=|VAULT_[A-Za-z0-9_]+=|PROJECTS_[A-Za-z0-9_]+=|VAULT=|PROJECTS=)' "$ctmp" > "$ctmp.2"
{ vault_block; echo; cat "$ctmp.2"; } > "$MP_HOME/mindpalace.conf"
rm -f "$ctmp" "$ctmp.2"
ok "config written: $MP_HOME/mindpalace.conf"

# 4. Vaults
say "4/6 Vaults"
new_vaults=""
while IFS='|' read -r n v p; do
  if ! vault_is_new "$v"; then ok "vault '$n' already exists, notes left untouched: $v"; continue; fi
  mkdir -p "$v"; [ -n "$p" ] && mkdir -p "$p"
  cp -R "$SRC/vault-template/." "$v/"
  export MP_R_NAME="$name" MP_R_LANG="$lang" MP_R_VAULT="$v" MP_R_PROJ="${p:-(no projects folder)}" MP_R_DATE="$(date +%F)" MP_R_VNAME="$n"
  find "$v" -type f -name '*.md' -print0 | while IFS= read -r -d '' f; do
    perl -pi -e 's/\{\{USER_NAME\}\}/$ENV{MP_R_NAME}/g; s/\{\{LANGUAGE\}\}/$ENV{MP_R_LANG}/g; s/\{\{VAULT_NAME\}\}/$ENV{MP_R_VNAME}/g; s/\{\{VAULT\}\}/$ENV{MP_R_VAULT}/g; s/\{\{PROJECTS\}\}/$ENV{MP_R_PROJ}/g; s/\{\{PRIVATE_DIR\}\}/private/g; s/\{\{DATE\}\}/$ENV{MP_R_DATE}/g' "$f"
  done
  ok "vault '$n' created: $v"
  new_vaults="$new_vaults|$v"
done <<<"$MP_VAULT_LIST"

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
if [ -n "$new_vaults" ] && [ "$usegit" = 1 ] && command -v git >/dev/null && confirm "Track the new vault(s) with local git (no remote)?"; then
  printf '%s' "${new_vaults#|}" | tr '|' '\n' | while read -r v; do
    { git -C "$v" init -q && git -C "$v" add -A && \
      git -C "$v" -c user.name="MindPalace" -c user.email="mindpalace@localhost" commit -qm "Initial vault"; } && ok "git initialized: $v" || warn "git init failed: $v"
  done
fi

# 6. Verify
say "6/6 Verifying"
bash "$MP_HOME/doctor.sh" || warn "doctor reported problems (see above)"

say "Done."
cat <<EOF
  Restart your AI tool(s) so the hooks and rules load.
  Next:  cd "$VAULT"  and start your AI tool there. In the first session it gets to know you.
  Settings: $MP_HOME/mindpalace.conf   Log: $MP_HOME/state/hook.log
  Check: bash "$MP_HOME/doctor.sh"   Uninstall: bash "$MP_HOME/uninstall.sh"
EOF
