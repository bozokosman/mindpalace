# MindPalace (product repo)

The shippable, agent-installable version of the second-brain system. Everything here is in English and contains nothing personal. Design notes and research live one level up in `mindpalace-system/` (raw folder, not part of this repo).

## Rules
- Bash only (no Python): hooks must run on Linux, macOS (bash 3.2) and Windows Git Bash. Avoid GNU-only flags (`sed -i`, `sed …/I`, `timeout`, `flock`, `setsid`): use perl or the fallbacks in `hooks/common.sh`.
- Never touch user files without a backup; never write into an existing vault; installs must stay idempotent.
- No personal data (names, paths, vault content) in this repo.
- Run `bash tests/run.sh` before every commit; it must end with `failed: 0`.
- Bump `VERSION` (semver) on release; note changes in `CHANGELOG.md`.

## Layout
- `install.sh` / `install.ps1` / `uninstall.sh` / `doctor.sh`: lifecycle
- `hooks/`: copied to `~/.claude/mindpalace/` by the installer
- `vault-template/`: copied to a new vault; `{{USER_NAME}}`, `{{LANGUAGE}}`, `{{VAULT}}`, `{{PROJECTS}}`, `{{PRIVATE_DIR}}`, `{{DATE}}` are filled in
- `AGENT_INSTALL.md`: the canonical recipe an agent follows; keep it in sync with installer flags
- `tests/run.sh`: offline test suite (throwaway HOME, no model calls)
