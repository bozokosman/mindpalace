# MindPalace

{{USER_NAME}}'s second brain: plain markdown, the whole of life. No code is written here; code lives in `{{PROJECTS}}`.

## Map
- `INDEX.md`: one line per note. Look here first when searching.
- `memory/`: `profile.md` (who {{USER_NAME}} is), `last-session.md`, `open-items.md` (backlog), `mistakes.md`
- `projects/<name>.md`: project summary; the `path:` field points to the code
- `knowledge/`: things learned, reusable patterns
- `toolbox/`: tools, subscriptions, servers (no secrets)
- `inbox/`: raw notes and hook-written note candidates. Sort them into the right place, then remove from inbox.
- `journal/`: session summaries and `time.csv` (written by hooks)
- `archive/`: outdated or cancelled notes
- `{{PRIVATE_DIR}}/`: AI assistants never read this

## Note format
```yaml
---
type: project | knowledge | tool | person | decision | journal
description: one-sentence summary (the same line goes into INDEX.md)
status: active | cancelled | superseded
confidence: verified | hypothesis
date: YYYY-MM-DD
---
```
Link notes with `[[note-name]]`. When a note is added, add its line to INDEX.md too.

## First session
If `memory/profile.md` is still the empty template, start by getting to know {{USER_NAME}}: ask a few questions at a time (work, goals, current projects, tools, how they like to work) and fill in the profile as you go.
