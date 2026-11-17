# Contributing

Thanks for helping. MindPalace is small on purpose: bash scripts and markdown, no servers.

## Ground rules
- **Bash only.** No Python or other runtimes. Scripts must run on Linux, macOS (bash 3.2) and Windows Git Bash.
- No GNU-only flags (`sed -i`, `timeout`, `flock`, `setsid`, `date -d`). Use the helpers in `core/common.sh` or perl.
- No `declare -A`, `${var,,}`, `mapfile` or `readarray` (not in bash 3.2).
- Never write personal data (names, paths, vault content) into the repo.
- Never touch user files without a backup; installs must stay idempotent.

## Workflow
1. Fork, create a branch, make a focused change.
2. Add or update tests in `tests/run.sh`. Tests run in a throwaway `HOME` and must never touch the real one.
3. Run `bash tests/run.sh`; it must end with `failed: 0`. Run `shellcheck` on changed scripts if you have it.
4. Update `CHANGELOG.md` (and `VERSION` for releases) and any docs your change affects.
5. Open a pull request using the template.

## Adding a tool
See "Adding a tool" in `CLAUDE.md`. Verify file formats against the tool's own documentation or source, not memory.

## Reporting bugs
Open an issue with your OS, bash version (`bash --version`), the tool you use, and the relevant lines of `~/.mindpalace/state/hook.log` (remove anything private first).
