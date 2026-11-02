# MindPalace

**A second brain for Claude Code. Plain markdown, a few small bash hooks, no servers.**

Claude Code forgets everything when a session ends. MindPalace gives it a long-term memory that lives in a folder of markdown files on your own computer:

- **It remembers what you did.** When a session ends, a short summary goes into your journal: what was done, what was decided, what comes next.
- **It knows where it is.** Start Claude inside a project and it loads that project's note and recent history. Start it in your vault and it loads your profile, open items and index. Anywhere else, it loads nothing.
- **It takes its own notes.** Facts worth keeping become note candidates in `inbox/`, and Claude sorts them into the right place with you.
- **It asks before it breaks things.** A guard hook stops for confirmation before `rm -r`, `git push --force`, `git reset --hard`, `.env` access and your private folder.

Everything is plain text you can open in any editor or in [Obsidian](https://obsidian.md). No database, no cloud sync, no extra API key.

---

## Install

### Let your agent do it (recommended)

Open Claude Code in the folder where you downloaded MindPalace and say:

> Install MindPalace: read `AGENT_INSTALL.md` and follow it.

The agent checks your system, asks you up to four questions (where your notes and code live, your name, your language), shows you the plan, and installs only after you say yes. It never installs system packages without asking you first.

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
| `--check` | Check the OS and dependencies only |
| `--plan` | Show what would happen, change nothing |
| `--yes` | No questions; use the flags below or defaults |
| `--vault DIR` `--projects DIR` `--name NAME` `--lang LANGUAGE` | Answers in advance |
| `--no-rules` | Don't add the rules import to `~/.claude/CLAUDE.md` |
| `--no-git` | Don't create a local git repo in the vault |

Restart Claude Code afterwards, then check:

```bash
bash ~/.claude/mindpalace/doctor.sh      # should end with "Healthy."
```

### Requirements

| | Linux | macOS | Windows |
|---|---|---|---|
| Claude Code CLI (`claude`) | required | required | required |
| bash | built in | built in (3.2 is fine) | Git for Windows (Claude Code already needs it) |
| jq | `apt/dnf/pacman install jq` | `brew install jq` | `winget install jqlang.jq` |
| perl | built in | built in | comes with Git for Windows |
| git (optional) | for vault history | for vault history | for vault history |

`install.sh --check` tells you exactly what is missing and the command to install it on your system.

> **Status of v1:** tested end to end on Linux (Fedora). macOS and Windows support is built in (path conversion, missing `timeout`/`flock`/`setsid` fallbacks, CRLF handling) but not yet tested on real machines. Please report what you find.

---

## How it works

```
                    ┌─────────────────────────── Claude Code session ───────────────────────────┐
  start             │                                                                            │   end / compact
 ─────────►  session-start.sh                     guard.sh (before every Bash command)    session-end.sh ─────►
             loads memory by location             asks before risky commands                  │
                    │                                                                         ▼
                    │                                                            summarize.sh (background)
                    ▼                                                            your own `claude` CLI, small model
   ┌──────────────────────────── your vault (plain markdown) ────────────────────────────────────┐
   │ INDEX.md  RULES.md  memory/  projects/  knowledge/  toolbox/  inbox/  journal/  archive/    │
   └─────────────────────────────────────────────────────────────────────────────────────────────┘
```

| Hook | Event | What it does |
|---|---|---|
| `session-start.sh` | SessionStart | In the vault: profile, last session, open items, INDEX, recent journal. In `<projects>/<name>`: that project's note plus its journal entries. Elsewhere: nothing. Size-capped, and says when it truncates. Also picks up sessions whose window was closed before they were summarized. |
| `guard.sh` | PreToolUse (Bash) | Returns "ask" for irreversible or sensitive commands. Never blocks; you decide. |
| `session-end.sh` | SessionEnd, PreCompact | Starts `summarize.sh` in the background so Claude Code closes instantly. |
| `summarize.sh` | (background) | Summarizes the part of the conversation not summarized yet, appends it to `journal/YYYY-MM-DD.md`, updates `memory/last-session.md`, puts note candidates into `inbox/`, logs active time to `journal/time.csv`. Secrets are scrubbed before and after the model call. |

The rules in `RULES.md` are imported into every session through a marked block in `~/.claude/CLAUDE.md`. They tell Claude how to use the vault: check INDEX before starting something new, write notes as it learns, never delete (archive instead), ask before irreversible actions.

### Your vault

```
MindPalace/
├── CLAUDE.md       how Claude behaves inside the vault
├── RULES.md        shared rules, loaded in every session
├── INDEX.md        one line per note, so Claude can find things
├── memory/         profile.md, open-items.md, mistakes.md, last-session.md
├── projects/       one note per code project (goal, decisions and why, next steps)
├── knowledge/      things learned, reusable patterns
├── toolbox/        tools, subscriptions, servers (never secrets)
├── inbox/          raw notes and hook-written note candidates
├── journal/        daily session summaries + time.csv
├── archive/        nothing is deleted, it moves here
└── private/        Claude never reads this (git-ignored)
```

Notes use a small frontmatter (`type`, `description`, `status`, `confidence`, `date`) and link to each other with `[[note-name]]`, so the vault works as an Obsidian graph out of the box.

---

## Configuration

Everything lives in `~/.claude/mindpalace/mindpalace.conf`:

| Setting | Default | Meaning |
|---|---|---|
| `VAULT` | `~/MindPalace` | Your notes |
| `PROJECTS` | `~/Projects` | Your code; each subfolder is a project |
| `BRAIN_DIRS` | empty | Extra folders that get the full vault memory |
| `USER_NAME`, `LANGUAGE` | | Used in rules and summaries |
| `PRIVATE_DIR` | `private` | Vault folder the guard protects |
| `BUDGET_BRAIN`, `BUDGET_PROJECT` | 8000, 3000 | Max characters loaded at session start |
| `SUMMARY_MODEL`, `SUMMARY_EFFORT` | `haiku`, `low` | Model used for summaries |
| `MIN_CONV_CHARS` | 400 | Shorter sessions are not summarized |

## Privacy

- Your notes never leave your computer through MindPalace. There is no server and no telemetry.
- Summaries are made by your own `claude` CLI, under your own account, the same way your normal sessions are. API keys, tokens and long secret-looking strings are scrubbed before the conversation is sent and again before anything is written.
- `private/` is git-ignored and guarded.

## Update and uninstall

- **Update:** get the new version and run `install.sh` again. Hooks are refreshed; your config and vault are kept.
- **Uninstall:** `bash uninstall.sh`. It removes the hooks from `settings.json` and the rules block from `CLAUDE.md` (both backed up first). It moves `~/.claude/mindpalace` aside instead of deleting it. **Your vault is never touched.**

## Roadmap

- Tested support for macOS and Windows
- Release archives with checksums, and an update command
- Slash commands (`/brain-save`, `/brain-search`) and an inbox-sorting skill
- Optional statusline
- Weekly review: merge inbox, archive stale notes

---

MindPalace v1.0.0 · © 2026 Osman. All rights reserved.
