# MindPalace: install guide for AI agents

You are an AI coding agent (Claude Code or similar) and the user asked you to install MindPalace.
This file is the canonical recipe. Follow the steps in order. Every command is safe to run again.

## Ground rules

- **Never install system packages yourself** (no `sudo`, `apt`, `brew`, `winget` without the user's explicit OK for that exact command). If a dependency is missing, show the user the command `install.sh --check` printed and wait.
- **Never overwrite user files.** The installer backs up `settings.json` and `CLAUDE.md` before touching them and never writes into an existing vault. Do not work around this.
- **Do not edit `~/.claude/settings.json` by hand.** Let `install.sh` do it.
- **Do not say "installed" until `doctor.sh` prints `Healthy.`** Show the user its output.
- Talk to the user in their language. Keep questions short.

## 1. Detect the system

Run `uname -s` (or check your environment info).

| Result | OS | How to run the installer |
|---|---|---|
| `Linux` | Linux | `bash install.sh …` |
| `Darwin` | macOS | `bash install.sh …` (stock bash 3.2 is fine) |
| `MINGW*` / `MSYS*` | Windows, inside Git Bash | `bash install.sh …` |
| PowerShell / cmd | Windows | `powershell -ExecutionPolicy Bypass -File install.ps1 …` (same options) |

All commands below assume you are in the folder that contains this file.

## 2. Check dependencies

```bash
bash install.sh --check
```

- Exit 0: continue.
- Exit 1: it lists each missing tool with the install command for this OS. Show that list to the user, ask them to install (or to let you run that exact command), then run `--check` again.

Required: `bash`, `jq`, `perl`, `claude` (Claude Code CLI). Optional: `git`.

## 3. Ask the user (at most 4 questions, one message)

1. **Vault folder**, where their notes will live. Default `~/MindPalace`. Avoid spaces in the path.
2. **Projects folder**, where their code lives. Default `~/Projects`. If they already keep code somewhere (look for a folder with many git repos, e.g. `~/code`, `~/dev`, `~/Desktop/Projects`), suggest that.
3. **Name** Claude should call them.
4. **Language** for notes and replies (e.g. English, Turkish, German).

If the user says "just use defaults", use them without asking again.

## 4. Show the plan, get a yes

```bash
bash install.sh --plan --vault "<vault>" --projects "<projects>" --name "<name>" --lang "<language>"
```

This changes nothing. Show the user the plan lines and ask for confirmation. Mention that their existing `settings.json` and `CLAUDE.md` are backed up first.

Options the user may want:
- `--no-rules`: do not add the import block to `~/.claude/CLAUDE.md`
- `--no-git`: do not create a local git repo in the vault

## 5. Install

```bash
bash install.sh --yes --vault "<vault>" --projects "<projects>" --name "<name>" --lang "<language>"
```

- If MindPalace is already installed, this is an **update**: hooks are refreshed, the existing config and vault are kept. The output says `hooks updated (x → y)`.
- The installer ends by running `doctor.sh`.

## 6. Verify

```bash
bash ~/.claude/mindpalace/doctor.sh
```

Expect `Healthy.` (exit 0). For each `✗` line, fix the cause (usually: rerun step 5) and run doctor again. `!` lines are optional warnings.

## 7. Hand over

Tell the user, briefly:
1. What was installed: 4 hooks in `~/.claude/mindpalace/`, the vault at `<vault>`, and (if chosen) a rules block in `~/.claude/CLAUDE.md`. Name the backup files the installer printed.
2. **Restart Claude Code.** Hooks and the rules import load at session start.
3. First real step: `cd "<vault>" && claude`. Claude gets to know them and fills `memory/profile.md`.
4. Memory test: in that first session, tell Claude one fact. After the session ends, open a new session in the vault and ask about it. It should show up in "Last session". Only then say memory works across sessions.
5. Uninstall at any time: `bash uninstall.sh` (the vault is never deleted).

## Troubleshooting

| Symptom | Fix |
|---|---|
| No memory at session start | Check that cwd is inside the vault or `<projects>/<name>`. Elsewhere, loading nothing is by design. Run doctor. |
| No journal entry after a session | Read `~/.claude/mindpalace/state/hook.log`. Sessions shorter than `MIN_CONV_CHARS` are skipped on purpose. |
| `claude: command not found` inside hooks | The hook environment has a different PATH. Put the `claude` binary's folder on PATH in your shell profile, then restart Claude Code. |
| Windows: hooks do nothing | Make sure Git for Windows is installed and `bash` is on PATH; rerun `install.ps1`. |
