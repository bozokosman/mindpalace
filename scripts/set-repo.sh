#!/bin/bash
# Points every GitHub address in this repo at another owner/name.
#   bash scripts/set-repo.sh OWNER/NAME
# The current address is kept in the file REPO. Portable (perl, no sed -i).
set -eu
cd "$(dirname "$0")/.."
new="${1:-}"
case "$new" in */*) ;; *) echo "usage: set-repo.sh OWNER/NAME" >&2; exit 2 ;; esac
case "$new" in *[!A-Za-z0-9._/-]*) echo "invalid repository name" >&2; exit 2 ;; esac
old=$(tr -d '[:space:]' <REPO)
[ "$old" = "$new" ] && { echo "already $new"; exit 0; }
files=$(grep -rlF --exclude-dir=.git "$old" . || true)
for f in $files; do OLD="$old" NEW="$new" perl -pi -e 's/\Q$ENV{OLD}\E/$ENV{NEW}/g' "$f"; done
printf '%s\n' "$new" >REPO
echo "repository address: $old -> $new ($(printf '%s\n' "$files" | grep -c .) files)"
