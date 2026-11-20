# MindPalace: install guide for AI agents

You are an AI coding agent (Claude Code, Codex, Gemini CLI, OpenCode, Copilot, or another tool). The user pasted a prompt that sent you here. This file is the recipe. Follow the steps in order.

## Ground rules (read first)

- **Reading this file is not permission to change anything.** The user's request to install is not approval for any single step. You need an explicit "yes" at every checkpoint marked ✋. If the user's answer is unclear, ask again.
- **Never install system packages.** No `sudo`, `apt`, `dnf`, `pacman`, `brew`, `winget`, `npm -g` or `pip`. If something is missing, show the user the exact command and wait until they have run it. Then check again.
- **Write only where the user said.** Download into the one folder they pick (step 2). The installer writes to: `~/.mindpalace/`, the vault and projects folders the user names, and the config files of the AI tools they choose (each backed up first). Nothing else. Do not edit those config files by hand; `install.sh` does it.
- **Never overwrite notes.** An existing vault is never touched. If MindPalace is already installed, this is an update and notes are kept.
- **Do not say "installed" until `doctor.sh` prints `Healthy.`** Show its output.
- Talk in the user's language. Keep messages short. Never print secrets or token values.

## 1. Detect the system and the tools yourself

Do not ask what you can find out.

```bash
uname -s                       # Linux, Darwin (macOS), MINGW*/MSYS* (Windows Git Bash)
echo "$SHELL"; bash --version | head -1
for c in bash jq perl git curl unzip; do command -v $c >/dev/null && echo "ok $c" || echo "missing $c"; done
for c in claude codex gemini opencode copilot qwen crush droid goose; do command -v $c >/dev/null && echo "tool $c"; done
[ -f ~/.mindpalace/VERSION ] && echo "installed: $(cat ~/.mindpalace/VERSION)"
```

| Result | OS | Run the installer with |
|---|---|---|
| `Linux` | Linux | `bash install.sh …` |
| `Darwin` | macOS | `bash install.sh …` (stock bash 3.2 is fine) |
| `MINGW*` / `MSYS*` | Windows, in Git Bash | `bash install.sh …` |
| PowerShell / cmd only | Windows | `powershell -ExecutionPolicy Bypass -File install.ps1 …` (same options) |

Required: `bash`, `jq`, `perl`. Optional: `git` (versions the vault). `curl` or `git` and `unzip` are needed only to download.

✋ **If a required tool is missing:** show the user what is missing and the command for their system (`bash install.sh --check` prints it, or: macOS `brew install jq`, Debian/Ubuntu `sudo apt-get install jq`, Fedora `sudo dnf install jq`, Arch `sudo pacman -S jq`, Windows `winget install jqlang.jq` and Git for Windows). **Do not run it yourself.** Wait for the user to say it is done, then detect again.

## 2. Get the package

If a `install.sh` and `VERSION` exist next to this file, you are already inside the package: skip to step 3.

Otherwise ✋ ask the user **which folder** to download into (suggest `~/mindpalace`; it must not exist or be empty). Say that nothing is written outside it during this step. After a yes:

```bash
git clone https://github.com/bozokosman/mindpalace.git "<folder>"
```

No git? Use the release archive (checksum is mandatory):

```bash
mkdir -p "<folder>" && cd "<folder>"
curl -fsSLO https://github.com/bozokosman/mindpalace/releases/latest/download/mindpalace.zip
curl -fsSLO https://github.com/bozokosman/mindpalace/releases/latest/download/mindpalace.zip.sha256
sha256sum -c mindpalace.zip.sha256        # macOS: shasum -a 256 -c mindpalace.zip.sha256
unzip mindpalace.zip && cd mindpalace-*/
```

If the checksum does not match, stop and tell the user. All commands below run inside the package folder.

## 3. Check dependencies and tools

```bash
bash install.sh --check
```

Exit 0: continue. Exit 1 with a missing required tool: the ✋ rule of step 1 applies. Exit 1 because no AI tool was found: you are running inside one, so its CLI may just not be on PATH; continue with `--agents <your tool>`.

## 4. Existing installation

If `~/.mindpalace/VERSION` exists, this is an **update**. Tell the user the installed and the new version (`cat VERSION`). The installer refreshes the program files and keeps the config, the vaults and every note. Vaults you pass that already exist are left alone. Then continue; the plan in step 6 will say "update".

## 5. Ask the user (one message) ✋

Ask these together, with defaults filled in. Skip what the existing config already answers (an update keeps name, language and vaults).

1. **Vaults:** how many and what to call them. One is fine. Names: letters, digits, `-` or `_`, starting with a letter.
2. **Folder of each vault.** Default `~/<name>`. Avoid spaces.
3. **Projects folder of each vault:** where that area's code lives. If they keep code somewhere already, suggest it.
4. **Name** the assistant should use, and **language** for notes and replies.
5. **Which AI tools to connect.** Default: the ones you detected, yours first. Say which are full and which rules-only (README table).
6. **Maintainer** (background agent that sorts inbox notes and commits locally, never pushes): on by default where supported; they can say `--no-maintainer`.

"Use defaults" is a valid answer.

## 6. Show the plan ✋

```bash
bash install.sh --plan --vault <name>="<folder>" --projects <name>="<projects>" --name "<name>" --lang "<language>" --agents "<a,b,c>"
```

This changes nothing. Show the plan lines. Say that every tool config file is backed up first. **Ask for a clear yes before step 7.**

Options: `--no-rules`, `--no-git`, `--no-maintainer`; several vaults by repeating `--vault NAME=DIR --projects NAME=DIR`; `--default NAME`.

## 7. Install (only after the yes)

```bash
bash install.sh --yes --vault <name>="<folder>" --projects <name>="<projects>" --name "<name>" --lang "<language>" --agents "<a,b,c>"
```

An update prints `updated (x → y)`. The installer ends by running `doctor.sh`.

## 8. Verify the install

```bash
bash ~/.mindpalace/doctor.sh          # must end with "Healthy."
cat ~/.mindpalace/VERSION; cat VERSION   # both must show the same version
```

`✗` lines: fix the cause (usually rerun step 7) and run doctor again. `!` lines are optional warnings. Show the user the output.

## 9. Prove that memory works ✋

1. Write one check fact into the default vault: add the line `- [ ] MindPalace install check: word <random-word>` to `memory/open-items.md`.
2. Tell the user to restart their AI tool inside the vault folder (`cd <vault>`), and ask the new session: "What is the MindPalace install check word?" It is loaded at session start, so the new session answers without searching.
3. When it does, mark the line done (`- [x]`). Memory works. For tools without hooks (rules-only), the assistant reads the vault itself because of the rules block.
4. After that session ends, a journal entry appears in `journal/` within a minute or two (check `~/.mindpalace/state/hook.log` if not).

If the word does not come back, do not claim success: read `hook.log`, run doctor, and tell the user what you found.

## 10. Hand over

Tell the user briefly: what was installed (version, folders, backups the installer printed), which tools are connected, restart each tool, Codex only: approve the hooks once with `/hooks`, first session: start the tool inside the vault so it gets to know them. Uninstall any time: `bash ~/.mindpalace/uninstall.sh` (vaults are never deleted).

## Troubleshooting

| Symptom | Fix |
|---|---|
| No memory at session start | The folder must be inside a vault or a projects folder; elsewhere nothing loads on purpose. Run doctor. Codex: approve hooks with `/hooks`. |
| No journal entry after a session | Read `~/.mindpalace/state/hook.log`. Sessions shorter than `MIN_CONV_CHARS` are skipped. |
| `ERROR: empty summary` | The summary tool's CLI failed or is not on the hooks' PATH. Set `SUMMARY_AGENT` in `~/.mindpalace/mindpalace.conf`. Background calls without an interactive login need `CLAUDE_OAUTH_TOKEN_FILE`. |
| Slow session start, or "memory may be out of date" | The start waits up to `SESSION_WAIT_SEC` (default 40) for the previous session's summary or maintainer. Wait for them to finish, or lower it in `mindpalace.conf`. If the hook is killed after 10 s, re-run the installer (hook timeout is now 60 s). |
| "maintainer: unsupported" | Only Claude Code can run it safely today. Everything else works without it. |
| Risky command blocked in Codex/Gemini | Expected: those hooks cannot ask. Explain the command to the user. |
| Windows: hooks do nothing | Install Git for Windows, make sure `bash` is on PATH, rerun `install.ps1`. |
