# Changelog

## 1.1.0 — 2026-11-02
Works with more than Claude Code. Everything is tool-neutral now.
- Agent-agnostic `core/` plus per-tool `adapters/`; installs to `~/.mindpalace`
- Full adapters: Claude Code; Codex CLI and Gemini CLI (experimental, checked against their source code)
- Rules-only adapters: OpenCode, GitHub Copilot CLI, Zed, Crush, Factory Droid, Qwen Code, Goose
- `--agents` option, auto-detection of installed AI tools, `SUMMARY_AGENT` (any tool can summarize any other's sessions)
- Vault template uses `AGENTS.md`; `CLAUDE.md` / `GEMINI.md` pointers are created per tool; RULES.md has a fallback for tools without hooks
- `time.csv` gains an `agent` column; journal entries show which tool the session ran in
- Guard also catches Windows recursive deletes; Codex/Gemini guard blocks with an explanation (their hooks cannot ask)
- Test suite: 79 offline checks with fake CLIs and per-tool transcript fixtures

## 1.0.0 — 2026-11-02
First release.
- Hooks: session-start (location-aware memory), guard (asks before risky commands), session-end + summarize (journal, last session, inbox candidates, time.csv, secret scrubbing)
- Installer with `--check`, `--plan`, `--yes`; idempotent, backs up settings.json and CLAUDE.md, managed rules block
- `doctor.sh` health check, `uninstall.sh`, Windows `install.ps1` wrapper
- Agent install guide (`AGENT_INSTALL.md`), English vault template
