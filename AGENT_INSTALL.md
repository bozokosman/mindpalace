# MindPalace: install guide for AI agents

You are an AI coding agent (Claude Code, Codex, Gemini CLI, OpenCode, Copilot, or another tool), and the user asked you to install MindPalace.
This file is the canonical recipe. Follow the steps in order. Every command is safe to run again.

The user expects you to do the work. Stop only at the **checkpoints** marked ✋ and wait for the user there. Everywhere else, keep going.

## Ground rules

- **Never install system packages yourself.** No `sudo`, `apt`, `brew` or `winget` unless the user approves that exact command at a checkpoint.
- **Never overwrite user files.** The installer backs up every config file it touches and never writes into an existing vault. Do not work around this.
- **Do not edit the tools' config files by hand** (`settings.json`, `hooks.json`, `GEMINI.md` …). Let `install.sh` do it.
- **Do not say "installed" until `doctor.sh` prints `Healthy.`** Show the user its output.
- Talk to the user in their language. Keep messages short.

## 1. Detect the system

Run `uname -s`, or check your environment info.

| Result | OS | How to run the installer |
|---|---|---|
| `Linux` | Linux | `bash install.sh …` |
| `Darwin` | macOS | `bash install.sh …` (stock bash 3.2 is fine) |
| `MINGW*` / `MSYS*` | Windows, inside Git Bash | `bash install.sh …` |
| PowerShell / cmd | Windows | `powershell -ExecutionPolicy Bypass -File install.ps1 …` (same options) |

All commands below assume you are in the folder that contains this file.

## 2. Check dependencies and AI tools

```bash
bash install.sh --check
```

The output lists the required tools (`bash`, `jq`, `perl`), optional `git`, and every supported AI tool found on this machine.

- **Exit 0:** continue.
- **Exit 1, a required tool is missing:** the output shows the install command for this OS.
  - ✋ **Checkpoint:** show the user the missing tools and the commands. Ask whether they install them, or whether you may run those exact commands. Then run `--check` again.
- **Exit 1, no AI tool found:** you are running inside one, so its CLI may simply not be on PATH. Tell the user which tool you are and continue with `--agents <that tool>`.

## 3. Ask the user (one message) ✋

Ask these in one short message, with the defaults filled in:

1. **Vaults: how many, and what to call them.** The user names them; there is no fixed name. One vault is fine. Suggest two only if they mention separate areas (e.g. `personal` and `work`). Names: letters, digits, `-` or `_`, starting with a letter.
2. **Folder of each vault**, where those notes will live. Default `~/<name>`. Avoid spaces in the path.
3. **Projects folder of each vault**, where that area's code lives. Default `~/Projects` for the first vault and none for the others. If they already keep code somewhere, suggest that (look for a folder with many git repos, e.g. `~/code`, `~/dev`, `~/Desktop/Projects`).
4. **Name** the assistant should call them.
5. **Language** for notes and replies (e.g. English, Turkish, German).
6. **Which AI tools to connect.** Default: every tool `--check` found. Put the tool you are running in first. Say which ones are full and which are rules-only (see the table in README.md).

If the user says "just use defaults", use them without asking again.

## 4. Show the plan ✋

```bash
bash install.sh --plan --vault <name>="<folder>" --projects <name>="<projects>" --name "<name>" --lang "<language>" --agents "<a,b,c>"
```

This changes nothing. Show the user the plan lines and ask for a yes. Mention that each tool's config file is backed up first.

Options the user may want:
- `--no-rules`: do not add the rules block to the tools' global instruction files.
- `--no-git`: do not create a local git repo in the vaults.
- Several vaults: repeat `--vault NAME="<folder>"` and `--projects NAME="<projects>"` for each. The first is the default unless `--default NAME` is given.

## 5. Install

```bash
bash install.sh --yes --vault <name>="<folder>" --projects <name>="<projects>" --name "<name>" --lang "<language>" --agents "<a,b,c>"
```

- If MindPalace is already installed, this is an **update** and the output says `updated (x → y)`. Files are refreshed; existing vaults and settings are kept. Vaults you pass are added, and the agent list is set to what you passed.
- The installer ends by running `doctor.sh`.

## 6. Verify

```bash
bash ~/.mindpalace/doctor.sh
```

Expect `Healthy.` (exit 0).
- **`✗` lines:** fix the cause and run doctor again. Usually rerunning step 5 is enough.
- **`!` lines:** optional warnings.

## 7. Hand over

Tell the user, briefly:
1. **What was installed:** MindPalace in `~/.mindpalace/`, each vault (name and folder; which is the default), and which tools were connected (full or rules-only). Name the backup files the installer printed.
2. **Restart each connected tool.** Hooks and rules load at session start.
3. **Codex only:** open Codex once and approve the MindPalace hooks with `/hooks`. Otherwise they do not run.
4. **First real step:** `cd` into the default vault and start their tool there. The assistant gets to know them and fills `memory/profile.md`.
5. **Memory test:** in that first session, tell the assistant one fact. After the session ends, open a new session in the vault and ask about it; it should appear under "Last session". Only then say memory works across sessions. For rules-only tools, the assistant writes the journal itself before finishing.
6. **Uninstall** any time with `bash ~/.mindpalace/uninstall.sh`. Vaults are never deleted.
7. **More vaults later:** `bash install.sh --vault <name>="<folder>"` adds one; nothing else changes.

## Troubleshooting

| Symptom | Fix |
|---|---|
| No memory at session start | Check that the cwd is inside a vault or inside a project folder of a vault; loading nothing elsewhere is by design. Run doctor. Codex: approve hooks with `/hooks`. |
| No journal entry after a session | Read `~/.mindpalace/state/hook.log`. Sessions shorter than `MIN_CONV_CHARS` are skipped on purpose. |
| `ERROR: empty summary` in the log | The `SUMMARY_AGENT` CLI failed or is not on the hooks' PATH. Set `SUMMARY_AGENT` to another connected full tool in `~/.mindpalace/mindpalace.conf`. |
| A risky command was blocked in Codex/Gemini | Expected: those tools cannot pause and ask. Explain the command to the user and let them run it. |
| Windows: hooks do nothing | Make sure Git for Windows is installed and `bash` is on PATH, then rerun `install.ps1`. |
