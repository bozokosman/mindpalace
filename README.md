# MindPalace

**Your AI coding assistant forgets everything when a session ends. MindPalace gives it a memory: plain markdown on your own computer, a few bash scripts, no servers.**

Works with **Claude Code, Codex CLI and Gemini CLI**, and through their instruction files with OpenCode, GitHub Copilot CLI, Zed, Crush, Factory Droid, Qwen Code and Goose. One tool or several, they share one brain.

**[Install in 3 steps](#install-in-3-steps)** · [Manual install](#manual-install) · [First 5 minutes](#first-5-minutes) · [Supported tools](#supported-tools) · [FAQ](#faq)

Linux · macOS · Windows (Git Bash) &nbsp;|&nbsp; bash, jq, perl &nbsp;|&nbsp; [MIT license](LICENSE)

## What it does

| You want | MindPalace does |
|---|---|
| Pick up where you left off | At session start it loads your profile, the last session and open items. At the end it writes a short journal entry. |
| The assistant knows the project | Start inside a project folder and it loads that project's note and recent history. |
| No lost work after a crash | A session that was cut off (window closed, crash) is noticed at the next start in that folder. The assistant offers to continue and does not do so without your yes. |
| Notes that sort themselves | Facts worth keeping become candidates in `inbox/`. An optional background maintainer files them into the right notes and commits locally. It never pushes. |
| Fewer repeated mistakes | Corrections are counted. A mistake that repeats becomes a trial rule, a rule that holds for 30 days becomes permanent, one that is never needed again for 90 days is archived. |
| Safety | A guard asks before `rm -r`, `git push --force`, `git reset --hard`, `.env` access and your private folder. |
| Several tools, one memory | A Codex session shows up in tomorrow's Claude session and the other way round. |

Everything is plain text you can open in any editor or in [Obsidian](https://obsidian.md). You name your vaults (for example `personal` and `work`). No database, no cloud sync, no extra API key.

```
 AI tool session (Claude Code / Codex / Gemini ...)
   start ─► session-start hook      shell command ─► guard      end ─► session-end hook
                │  adapters/<tool>/  (only the tool-specific glue)         │
                ▼                                                          ▼
          core/memory.sh                                    core/summarize.sh  (background, retries)
          what to load, by folder                           core/maintain.sh   (optional maintainer)
                │                                                          │
        ┌───────▼──────────────── your vault (plain markdown) ─────────────▼───────┐
        │ INDEX  RULES  SUMMARY  memory/  projects/  knowledge/  toolbox/  inbox/  │
        │ journal/  agent/  archive/  private/ (never read by assistants)          │
        └───────────────────────────────────────────────────────────────────────────┘
```

## Install in 3 steps

1. **Pick a folder** for the download, for example `~/mindpalace` (new or empty). Nothing is written outside it during the download.
2. **Open your AI tool** (Claude Code, Codex, Gemini CLI, ...) in that folder.
3. **Paste this one prompt:**

```text
Read https://raw.githubusercontent.com/bozokosman/mindpalace/main/AGENT_INSTALL.md and install MindPalace by following it step by step. Detect my system and my AI tools yourself. Do not install system packages: if something is missing, give me the command and wait. Run the installer with --plan first and ask me before you install. If MindPalace is already installed, update it and keep my notes. At the end run doctor and help me check it with one test fact in a new session.
```

The assistant detects your system and tools, shows you what is missing, asks a few short questions (vault names and folders, your name, language, which tools), shows the plan, and installs only after your yes. Every config file it touches is backed up first.

## Manual install

**With git:**

```bash
git clone https://github.com/bozokosman/mindpalace.git
cd mindpalace
./install.sh               # asks a few questions; use --plan first to see what would happen
```

**With the release archive and checksum:**

```bash
curl -fsSLO https://github.com/bozokosman/mindpalace/releases/latest/download/mindpalace.zip
curl -fsSLO https://github.com/bozokosman/mindpalace/releases/latest/download/mindpalace.zip.sha256
sha256sum -c mindpalace.zip.sha256          # macOS: shasum -a 256 -c mindpalace.zip.sha256
unzip mindpalace.zip && cd mindpalace-*/ && ./install.sh
```

Windows without Git Bash: `powershell -ExecutionPolicy Bypass -File install.ps1`.

| Flag | What it does |
|---|---|
| `--check` | Check the OS, dependencies and which AI tools are installed |
| `--plan` | Show what would happen, change nothing |
| `--yes` | No questions; use the flags below or defaults |
| `--agents claude,codex,...` | Which tools to connect (default: every supported tool found) |
| `--vault NAME=DIR` | A vault named by you. Repeat for several; on a later run it adds one |
| `--projects NAME=DIR` | That vault's code folder (each subfolder is a project) |
| `--default NAME` | Vault used outside every vault and projects folder |
| `--name NAME` `--lang LANGUAGE` | Answers in advance |
| `--no-rules` | Don't add the rules block to the tools' global instruction files |
| `--no-git` | Don't create a local git repo in new vaults |
| `--no-maintainer` | Turn the background maintainer off |

Restart your AI tool afterwards and run `bash ~/.mindpalace/doctor.sh`; it should end with `Healthy.`

### Requirements

| | Linux | macOS | Windows |
|---|---|---|---|
| An AI tool from the list below | yes | yes | yes |
| bash | built in | built in (3.2 is fine) | Git for Windows |
| jq | `apt/dnf/pacman install jq` | `brew install jq` | `winget install jqlang.jq` |
| perl | built in | built in | comes with Git for Windows |
| git (optional) | vault history | vault history | vault history |

`./install.sh --check` tells you what is missing and the command for your system.

## First 5 minutes

1. `cd` into your vault and start your AI tool. In the first session it asks a few questions and fills `memory/profile.md`.
2. Work on something, then end the session normally. A journal entry appears in `journal/` after a minute or so.
3. Start a new session in a project folder. It already knows the project and where you stopped.
4. Look at `inbox/`: facts the assistant wants to keep. With the maintainer on they are filed for you; otherwise ask the assistant to sort them.
5. Run `bash ~/.mindpalace/doctor.sh` whenever something seems off, and read `~/.mindpalace/state/hook.log`.

## Supported tools

| Tool | Level | Memory at start | Journal at end | Command guard | Maintainer | Unfinished-session notice |
|---|---|---|---|---|---|---|
| **Claude Code** | full | hook | hook + summary | asks you | supported | yes |
| **Codex CLI** | full, experimental | hook | hook + summary | blocks and explains ¹ | unsupported ² | yes |
| **Gemini CLI** | full, experimental | hook | hook + summary | blocks and explains ¹ | unsupported ² | yes |
| OpenCode, Copilot CLI, Zed, Crush, Droid, Qwen Code, Goose | rules only | via rules | via rules | via rules | via another tool | via rules ³ |

- **Experimental:** checked against the tool's source code, not yet run on a real install. Please report what you find.
- **Rules only:** the tool reads `RULES.md` through its global instruction file; a section there tells it to load memory, write the journal, finish pending inbox work and check for a cut-off session. It depends on the model following instructions.
- ¹ These hooks cannot pause and ask. A risky command is blocked and the assistant explains it. Codex also needs a one-time `/hooks` approval.
- ² The maintainer needs an agent mode that can edit files only inside the vault and never read `private/`. Codex's sandbox and Gemini's approval modes cannot guarantee that, so the feature stays off for them. If Claude Code is also connected, it does the maintenance for all tools' sessions.
- ³ Without hooks the assistant keeps `memory/in-progress.md` during work; if it finds one at the start, the last session was cut off.

Platform status: the offline test suite runs on Linux, macOS and Windows (Git Bash) in CI. Real-world use so far: Linux with Claude Code. macOS and Windows are covered by tests and fallbacks (no `/proc`, no GNU-only flags, no `setsid`/`flock`/`timeout` needed) but have less field use. Your tool isn't listed? A rules-only adapter is three lines (see `adapters/zed/install.sh`).

## The optional maintainer

After each session summary, a background agent (Claude Code, a small model, file tools only, no shell, edits confined to the vault, `private/` forbidden):

- files the `inbox/` candidates into the right notes and archives sorted inbox files
- updates `SUMMARY.md` (recent work, agent notes, next up) and the assistant's own notes in `agent/notes.md`
- counts corrections in `memory/mistakes.md`; a script (not the model) applies the dates: a second occurrence makes a **trial** rule, 30 days without a repeat makes it a **rule**, 90 more days without a repeat **retires** it to `archive/`
- commits to the vault's git repo if `AUTO_COMMIT=on`. **It never pushes**, and nothing leaves your machine.

Off switch: `MAINTAIN="off"` in `~/.mindpalace/mindpalace.conf` or `--no-maintainer` at install.

## Resilience

- Failed model calls are retried twice for temporary errors (overload, network); login or setup errors are never retried. A long conversation that comes back empty is tried once more.
- Locks carry the process id and start time, so a crashed run never blocks the next one and a reused process id is not mistaken for a live one.
- At session start, unsummarized sessions and pending maintenance are recovered in the background, without slowing the start.
- For unattended runs on Claude Code, set `CLAUDE_OAUTH_TOKEN_FILE` to a file with a long-lived token (`claude setup-token`); keep it at mode 600. The value is never logged.

## Configuration

Everything lives in `~/.mindpalace/mindpalace.conf` (see `mindpalace.conf.example`, every key is commented):

| Setting | Default | Meaning |
|---|---|---|
| `VAULTS`, `VAULT_<name>`, `PROJECTS_<name>` | your choice | Vaults, their folders and code folders |
| `AGENTS`, `SUMMARY_AGENT` | detected | Connected tools; whose CLI writes the summaries |
| `MAINTAIN`, `MAINTAIN_AGENT`, `AUTO_COMMIT` | on, claude, on | Maintainer and local commits |
| `RETRY_WAIT`, `EMPTY_RETRY_MIN_CHARS` | `20 60`, 8000 | Retry waits (seconds); empty-answer retry threshold |
| `RECOVER` | on | Background recovery at session start |
| `LESSON_TRIAL_DAYS`, `LESSON_RETIRE_DAYS`, `LESSON_MAX_RULES` | 30, 90, 15 | Lessons cycle |
| `CLAUDE_OAUTH_TOKEN_FILE` | empty | Long-lived Claude token file |
| `BUDGET_BRAIN`, `BUDGET_PROJECT`, `MIN_CONV_CHARS` | 8000, 3000, 400 | Context budgets, shortest session worth summarizing |

## Update and uninstall

- **Update:** pull or download the new version and run `./install.sh` again, or ask your assistant to follow `AGENT_INSTALL.md`. Program files are refreshed; config, vaults and notes are kept.
- **Uninstall:** `bash ~/.mindpalace/uninstall.sh`. It removes hooks and rules blocks (each config file backed up first) and moves `~/.mindpalace` aside. **Your vaults are never touched.**

## FAQ

**Does it send my notes anywhere?** No. There is no server and no telemetry. Summaries and the maintainer are made by an AI tool you already use, under your own account.

**Do I need an API key?** No. It uses the CLI you already have. For unattended background runs on Claude Code you may want a long-lived token file.

**Will it overwrite my existing notes or config?** No. An existing vault is never written into, and every config file is backed up before it is changed.

**Why is the maintainer off for Codex and Gemini?** There is no way to confine them to the vault and keep `private/` unreadable. Rather than guess at flags, it stays off for them.

**Can it push to GitHub?** No. MindPalace never runs `git push`.

**A session crashed. What now?** Start your tool in the same folder. It shows a short notice (last request, last state, transcript) and the assistant offers to continue. Nothing happens without your yes.

**It says "Healthy" but nothing is written.** Read `~/.mindpalace/state/hook.log`. Sessions shorter than `MIN_CONV_CHARS` are skipped on purpose; login problems show as `ERROR` lines.

## Privacy

- Your notes never leave your computer through MindPalace.
- Before conversation text reaches a model, and again before anything is written, API keys, tokens and long secret-looking strings are scrubbed (best effort).
- `private/` is git-ignored, guarded, and forbidden to the maintainer.
- Token files are read at run time, never logged, and checked for mode 600 by `doctor.sh`.

## Roadmap

- Full hook adapters for Copilot CLI, Qwen Code, Factory Droid and Cursor
- Real-install tests for Codex and Gemini, more field use on macOS and Windows
- Slash commands / skills: save, search, sort the inbox
- Weekly review: merge inbox, archive stale notes

## Contributing, security, license

See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md). Changes are listed in [CHANGELOG.md](CHANGELOG.md). Released under the [MIT License](LICENSE).

Created by Osman Bozok. MindPalace v1.2.0 · MIT License · Copyright (c) 2026 Osman Bozok.
