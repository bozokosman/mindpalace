# MindPalace (product repo)

The shippable, agent-installable, tool-neutral version of the second-brain system (Claude Code, Codex, Gemini CLI and more). Everything here is in English and contains nothing personal. Design notes and research live one level up in `mindpalace-system/` (raw folder, not part of this repo).

## Rules
- Bash only (no Python): hooks must run on Linux, macOS (bash 3.2) and Windows Git Bash. Avoid GNU-only flags (`sed -i`, `sed …/I`, `timeout`, `flock`, `setsid`): use perl or the fallbacks in `core/common.sh`.
- Never touch user files without a backup; never write into an existing vault; installs must stay idempotent.
- No personal data (names, paths, vault content) in this repo.
- Run `bash tests/run.sh` before every commit; it must end with `failed: 0`.
- Bump `VERSION` (semver) on release; note changes in `CHANGELOG.md`.
- Portability: no `/proc`, `date -d`, `stat -c`, `readlink -f`, `sed -i` without a suffix, `declare -A`, `${x,,}` or `mapfile`; dates and file times go through perl helpers in `core/common.sh`. Background work is started with `mp_detach` (setsid or nohup).
- Tool-specific code lives only in `adapters/<tool>/` (e.g. `mp_agent_edit` for the maintainer, `mp_agent_proc_regex` and `mp_agent_resume_hint` for cut-off sessions). A tool without a safe file-edit mode has no `mp_agent_edit`, and the maintainer reports "unsupported" for it.
- The maintainer and MindPalace as a whole never run `git push`; a test checks it.

## Layout
- `install.sh` / `install.ps1` / `uninstall.sh` / `doctor.sh`: lifecycle; everything installs to `~/.mindpalace/`
- `core/`: tool-neutral logic: `common.sh` (helpers, retries, PID locks, portable date/stat via perl), `memory.sh`, `guard-rules.sh`, `summarize.sh`, `recover.sh` (session-start recovery), `sessions.sh` + `session-digest.sh` (cut-off session detection), `maintain.sh` + `lessons.sh` + `prompts/maintain.md` (optional maintainer). Never put tool-specific code here. Multiple vaults: always call `mp_resolve <cwd>` before using `$VAULT`/`$PROJECTS`.
- `adapters/<tool>/`: `install.sh` (adapter_label/cli/plan/install/uninstall/doctor) for every tool; full tools also have `adapter.sh` (mp_agent_messages, mp_agent_llm, session helpers) and `hooks/`. Rules-only tools are one `mp_rules_only` line.
- `lib/install-lib.sh`: helpers shared by the installer, doctor, uninstaller and adapters
- `vault-template/`: copied to each new vault; `{{VAULT_NAME}}`, `{{USER_NAME}}`, `{{LANGUAGE}}`, `{{VAULT}}`, `{{PROJECTS}}`, `{{PRIVATE_DIR}}`, `{{DATE}}` are filled in
- `AGENT_INSTALL.md`: the canonical recipe an agent follows; keep it in sync with installer flags
- `REPO` + `scripts/set-repo.sh`: the GitHub address (owner/name) lives in one place; the script rewrites it everywhere
- `.github/`: CI matrix (ubuntu, macos, windows), draft release workflow (tag `v*` must equal `VERSION`), templates
- `tests/run.sh`: offline test suite (throwaway HOME and XDG_CONFIG_HOME, fake AI CLIs, `tests/fixtures/` transcripts). Tests must never touch the real home.

## Adding a tool
1. Rules-only: `adapters/<tool>/install.sh` with one `mp_rules_only` line. Verify the global rules path from the tool's docs or source first.
2. Full: copy `adapters/claude/`, adapt the hook JSON, the transcript parser (normalized `{role,text,ts}`) and the CLI call; add a fixture and tests. Verify formats against the tool's source code, not memory.
