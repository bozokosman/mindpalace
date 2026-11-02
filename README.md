# MindPalace

**A second brain for AI coding assistants. Plain markdown, a few small bash scripts, no servers.**

Works with **Claude Code, Codex CLI and Gemini CLI**, and through their instruction files with **OpenCode, GitHub Copilot CLI, Zed, Crush, Factory Droid, Qwen Code and Goose**. Use one tool or several: they all share the same memory.

AI assistants forget everything when a session ends. MindPalace gives them a long-term memory that lives in a folder of markdown files on your own computer:

- **It remembers what you did.** When a session ends, a short summary goes into your journal: what was done, what was decided, what comes next.
- **It knows where it is.** Start your assistant inside a project and it loads that project's note and recent history. Start it in your vault and it loads your profile, open items and index. Anywhere else, it loads nothing.
- **It takes its own notes.** Facts worth keeping become note candidates in `inbox/`, and the assistant sorts them into the right place with you.
- **It stops before it breaks things.** A guard checks every shell command for `rm -r`, `git push --force`, `git reset --hard`, `.env` access and your private folder.
- **Your tools share one brain.** A session in Codex shows up in tomorrow's Claude session, and the other way round.

Everything is plain text you can open in any editor or in [Obsidian](https://obsidian.md). No database, no cloud sync, no extra API key.

---

## Install

### Let your assistant do it (recommended)

Open your AI assistant in the folder where you downloaded MindPalace and say:

> Install MindPalace: read `AGENT_INSTALL.md` and follow it.

The assistant then works through these steps:
1. Checks your system and finds which AI tools you have.
2. Asks you a few short questions: where your notes and code live, your name, your language, and which tools to connect.
3. Shows you the plan and installs only after you say yes.

It never installs system packages without asking you first, and it backs up every config file before touching it.

### Or do it yourself

```bash
bash install.sh            # Linux, macOS, Windows (Git Bash)
```
```powershell
powershell -ExecutionPolicy Bypass -File install.ps1    # Windows PowerShell
```

The installer asks the same questions. Useful flags:

| Flag | What it does |
|---|---|
| `--check` | Check the OS, dependencies, and which AI tools are installed |
| `--plan` | Show what would happen, change nothing |
| `--yes` | No questions; use the flags below or defaults |
| `--agents claude,codex,…` | Which tools to connect (default: every supported tool found) |
| `--vault DIR` `--projects DIR` `--name NAME` `--lang LANGUAGE` | Answers in advance |
| `--no-rules` | Don't add the rules block to the tools' global instruction files |
| `--no-git` | Don't create a local git repo in the vault |

Restart your AI tool(s) afterwards, then check:

```bash
bash ~/.mindpalace/doctor.sh      # should end with "Healthy."
```

Added a new AI tool later? Run the installer again with `--agents`. Your vault and settings are kept.

---

## Supported tools

| Tool | Level | Memory at start | Journal at end | Command guard | Rules file |
|---|---|---|---|---|---|
| **Claude Code** | full | hook | hook + summary | asks you | `~/.claude/CLAUDE.md` |
| **Codex CLI** | full · experimental | hook | hook + summary | blocks and explains ¹ | `~/.codex/AGENTS.md` |
| **Gemini CLI** | full · experimental | hook | hook + summary | blocks and explains ¹ | `~/.gemini/GEMINI.md` |
| OpenCode | rules only | via rules | via rules | via rules | `~/.config/opencode/AGENTS.md` |
| GitHub Copilot CLI | rules only ² | via rules | via rules | via rules | `~/.copilot/copilot-instructions.md` |
| Zed agent | rules only | via rules | via rules | via rules | `~/.config/zed/AGENTS.md` |
| Crush | rules only | via rules | via rules | via rules | `~/.config/crush/CRUSH.md` |
| Factory Droid | rules only ² | via rules | via rules | via rules | `~/.factory/AGENTS.md` |
| Qwen Code | rules only ² | via rules | via rules | via rules | `~/.qwen/QWEN.md` |
| Goose | rules only | via rules | via rules | via rules | `~/.config/goose/.goosehints` |

- **Full:** hooks load memory, write the journal and check commands automatically.
- **Experimental:** the adapter was checked against the tool's source code but not yet run on a real install. Please report what you find.
- **Rules only:** the tool reads `RULES.md` through its global instruction file. A section in `RULES.md` tells it to load memory and write the journal itself. This works, but it depends on the model following instructions.
- ¹ Codex and Gemini hooks cannot pause and ask, so a risky command is blocked and the assistant is told to explain it and let you run it. Codex also asks you to approve new hooks once with `/hooks`.
- ² These tools have hook systems too. Full adapters are planned.

Your tool isn't listed? If it reads a global instructions file, a rules-only adapter is three lines (see `adapters/zed/install.sh`).

### Requirements

| | Linux | macOS | Windows |
|---|---|---|---|
| An AI tool from the list above | ✓ | ✓ | ✓ |
| bash | built in | built in (3.2 is fine) | Git for Windows |
| jq | `apt/dnf/pacman install jq` | `brew install jq` | `winget install jqlang.jq` |
| perl | built in | built in | comes with Git for Windows |
| git (optional) | for vault history | for vault history | for vault history |

`install.sh --check` tells you exactly what is missing and the command to install it on your system.

> **Status:** tested end to end on Linux (Fedora) with Claude Code, including a real summary call. Codex and Gemini adapters pass the offline test suite with transcripts shaped after their source code. macOS and Windows support is built in (path conversion, fallbacks for missing `timeout`/`flock`/`setsid`, CRLF handling) but not yet tested on real machines.

---

## How it works

```
   AI tool session (Claude Code / Codex / Gemini …)
   ┌──────────────────────────────────────────────────────────────────────────┐
   │ start ─► session-start hook      shell command ─► guard     end ─► session-end hook
   └──────────────┬───────────────────────────────────────────────────────┬───┘
                  │ adapters/<tool>/   (only the tool-specific glue)      │
                  ▼                                                       ▼
            core/memory.sh                                       core/summarize.sh (background)
            what to load, by location                            any connected tool's CLI, small model
                  │                                                       │
   ┌──────────────▼───────────── your vault (plain markdown) ─────────────▼──────┐
   │ INDEX.md  RULES.md  AGENTS.md  memory/  projects/  knowledge/  toolbox/      │
   │ inbox/  journal/  archive/  private/                                        │
   └──────────────────────────────────────────────────────────────────────────────┘
```

- **`core/`** holds all the logic and knows nothing about specific tools: what memory to load where, the guard rules, the summarizer and the catch-up for sessions closed without an end event.
- **`adapters/<tool>/`** holds only what differs: the tool's hook format, how to read its transcript files, which CLI command summarizes, and where its config lives.
- **The summarizer is shared.** Any connected tool can summarize any other tool's sessions (set `SUMMARY_AGENT`). Secrets are scrubbed before and after the model call.
- **Session start is size-capped**, and says when it truncates something.

### Your vault

```
MindPalace/
├── AGENTS.md       how assistants behave inside the vault (CLAUDE.md / GEMINI.md point here)
├── RULES.md        shared rules, loaded in every session of every connected tool
├── INDEX.md        one line per note, so the assistant can find things
├── memory/         profile.md, open-items.md, mistakes.md, last-session.md
├── projects/       one note per code project (goal, decisions and why, next steps)
├── knowledge/      things learned, reusable patterns
├── toolbox/        tools, subscriptions, servers (never secrets)
├── inbox/          raw notes and hook-written note candidates
├── journal/        daily session summaries + time.csv (which tool, how long)
├── archive/        nothing is deleted, it moves here
└── private/        assistants never read this (git-ignored)
```

Notes use a small frontmatter (`type`, `description`, `status`, `confidence`, `date`) and link to each other with `[[note-name]]`, so the vault works as an Obsidian graph out of the box.

---

## Configuration

Everything lives in `~/.mindpalace/mindpalace.conf`:

| Setting | Default | Meaning |
|---|---|---|
| `VAULT` | `~/MindPalace` | Your notes |
| `PROJECTS` | `~/Projects` | Your code; each subfolder is a project |
| `AGENTS` | detected | Connected tools |
| `SUMMARY_AGENT` | first full tool found | Whose CLI writes the summaries |
| `CLAUDE_SUMMARY_MODEL`, `CODEX_SUMMARY_MODEL`, `GEMINI_SUMMARY_MODEL` | `haiku`, tool default, `flash-lite` | Small models for summaries |
| `BRAIN_DIRS` | empty | Extra folders that get the full vault memory |
| `USER_NAME`, `LANGUAGE` | | Used in rules and summaries |
| `PRIVATE_DIR` | `private` | Vault folder the guard protects |
| `BUDGET_BRAIN`, `BUDGET_PROJECT` | 8000, 3000 | Max characters loaded at session start |
| `MIN_CONV_CHARS` | 400 | Shorter sessions are not summarized |

## Privacy

- Your notes never leave your computer through MindPalace. There is no server and no telemetry.
- Summaries are made by an AI tool you already use, under your own account, the same way your normal sessions are. API keys, tokens and long secret-looking strings are scrubbed before the conversation is sent and again before anything is written.
- `private/` is git-ignored and guarded.

## Update and uninstall

- **Update:** get the new version and run `install.sh` again. Files are refreshed; your config and vault are kept.
- **Uninstall:** `bash ~/.mindpalace/uninstall.sh`.
  - It disconnects every tool: hooks and rules blocks are removed, and each config file is backed up first.
  - It moves `~/.mindpalace` aside instead of deleting it.
  - **Your vault is never touched.**

## Roadmap

- Full hook adapters for Copilot CLI, Qwen Code, Factory Droid and Cursor
- Tested support for macOS and Windows; real-install tests for Codex and Gemini
- Release archives with checksums, and an update command
- Slash commands / skills: save, search, sort the inbox
- Weekly review: merge inbox, archive stale notes

---

MindPalace v1.1.0 · © 2026 Osman. All rights reserved.
