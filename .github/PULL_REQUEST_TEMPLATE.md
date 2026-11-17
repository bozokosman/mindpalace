## What and why

## Checklist
- [ ] `bash tests/run.sh` ends with `failed: 0`
- [ ] New behavior has a test; tests use a throwaway HOME
- [ ] Bash only, works on bash 3.2 (no `declare -A`, `${x,,}`, `mapfile`), no GNU-only flags, no `/proc`
- [ ] No personal data in the diff
- [ ] `CHANGELOG.md` and docs updated
