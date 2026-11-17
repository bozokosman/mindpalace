# Changelog

## 1.2.0 — 2026-11-17
Resilience, an optional maintainer, cut-off session detection, and a public GitHub release flow.
- **Retries:** model calls retry twice on temporary errors (waits in `RETRY_WAIT`), never on login/auth/missing-CLI errors; a long conversation answered with EMPTY is tried once more (`EMPTY_RETRY_MIN_CHARS`)
- **Locks:** PID locks that record the process start time (`ps -o lstart=`), so stale locks are taken over and reused PIDs are not mistaken for live ones; no `/proc`; falls back to lock age where `ps` cannot report start times (Git Bash)
- **Recovery:** at session start, unsummarized recent sessions and pending maintenance are recovered in a detached background process; the hook prints at most one health line
- **Maintainer (optional, `MAINTAIN=on|off`):** `core/maintain.sh` sorts inbox candidates, updates `SUMMARY.md` and `agent/notes.md`, archives sorted inbox files and commits locally when `AUTO_COMMIT=on` (never pushes). Supported where the tool has a safe file-edit mode (Claude Code); Codex and Gemini are unsupported and the feature stays off for them
- **Lessons cycle:** `core/lessons.sh` applies the date rules deterministically: count 2 = trial, 30 days without a repeat = rule, 90 days = retired into `archive/mistakes-retired.md`, cap of 15 active rules
- **Cut-off sessions:** every folder; open-session records are written at session start and deleted at a real session end (compaction keeps them); the next start in the same folder shows a one-time warning (last request, last state, transcript, digest command) and the assistant must ask before continuing. `core/session-digest.sh` makes the digest with bash and jq. Rules-only tools get the same through `RULES.md` and `memory/in-progress.md`
- **Claude Code:** `CLAUDE_OAUTH_TOKEN_FILE` for unattended runs; whitespace stripped, value never logged (redacted from stderr), `doctor.sh` checks mode 600
- **Install experience:** new README with a one-prompt install, release zip + sha256 instructions, FAQ; `AGENT_INSTALL.md` rewritten (agent detects system and tools, never installs system packages, `--plan` before install, explicit approval at every checkpoint, doctor + version check + memory proof); the repository address lives in `REPO` (`scripts/set-repo.sh` changes it everywhere); `--no-maintainer`
- **GitHub:** MIT license, CI on Linux, macOS and Windows (Git Bash), draft release workflow with zip and checksum, issue/PR templates, `CONTRIBUTING.md`, `SECURITY.md`, `.gitattributes`
- **Fixes:** new vaults now really get their local git repo (the loop skipped the last vault when the list had no trailing newline); Codex injects the rules of the vault that owns the folder
- Test suite: 195 offline checks (was 93)

## 1.1.0 — 2026-11-02
Works with more than Claude Code. Everything is tool-neutral now.
- Agent-agnostic `core/` plus per-tool `adapters/`; installs to `~/.mindpalace`
- Full adapters: Claude Code; Codex CLI and Gemini CLI (experimental, checked against their source code)
- Rules-only adapters: OpenCode, GitHub Copilot CLI, Zed, Crush, Factory Droid, Qwen Code, Goose
- `--agents` option, auto-detection of installed AI tools, `SUMMARY_AGENT` (any tool can summarize any other's sessions)
- Vault template uses `AGENTS.md`; `CLAUDE.md` / `GEMINI.md` pointers are created per tool; RULES.md has a fallback for tools without hooks
- `time.csv` gains an `agent` column; journal entries show which tool the session ran in
- Guard also catches Windows recursive deletes; Codex/Gemini guard blocks with an explanation (their hooks cannot ask)
- Vaults are named by the user, and there can be several (e.g. `personal`, `work`), each with its own projects folder. Sessions use the vault that owns the current folder; `--vault NAME=DIR` adds a vault later, `--default NAME` picks the default
- Test suite: 93 offline checks with fake CLIs and per-tool transcript fixtures

## 1.0.0 — 2026-11-02
First release.
- Hooks: session-start (location-aware memory), guard (asks before risky commands), session-end + summarize (journal, last session, inbox candidates, time.csv, secret scrubbing)
- Installer with `--check`, `--plan`, `--yes`; idempotent, backs up settings.json and CLAUDE.md, managed rules block
- `doctor.sh` health check, `uninstall.sh`, Windows `install.ps1` wrapper
- Agent install guide (`AGENT_INSTALL.md`), English vault template
