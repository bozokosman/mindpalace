# Shared rules

Loaded in every session of every connected AI tool (Claude Code, Codex, Gemini CLI, …). Keep it short: only things the model cannot know on its own.

- Reply in {{LANGUAGE}}. The user is {{USER_NAME}}.
- This vault: `{{VAULT_NAME}}` at `{{VAULT}}`. Its projects: `{{PROJECTS}}/<name>`, each one summarized in `{{VAULT}}/projects/<name>.md`.
- If {{USER_NAME}} has several vaults (listed in the global rules), keep them separate: notes go to the vault that owns the current folder.
- Before starting a new project or task, check `{{VAULT}}/INDEX.md`: have we done something similar before?
- Show evidence before saying "done": a test, command output, or a re-read file.
- If you are not sure, say so. Do not invent facts that are not in the vault; ask.
- Hand work that needs many file reads to a subagent (a small model for reading, a stronger one for judgment). Only the summary comes back to the main context.
- When {{USER_NAME}} corrects you, or you repeat a mistake, count it in `{{VAULT}}/memory/mistakes.md` following the "How it works" section there (a second occurrence becomes a trial rule). Dates are checked by a script, not by you.
- Passwords, API keys and `.env` contents are never written into any note. `{{VAULT}}/{{PRIVATE_DIR}}/` is never read.
- Notes in the vault are never deleted; they move to `archive/`. A cancelled decision gets `status: cancelled` and links to the note that replaces it.
- Ask before anything irreversible (delete, push, deploy, sending data outside).

## Note taking (the agent takes its own notes, without asking)
- The vault is the long-term memory. Write what you learn during the session: solid facts/patterns → `knowledge/`, tools/servers/subscriptions → `toolbox/`, about {{USER_NAME}} → `memory/profile.md`, decisions/next steps → the project note or `memory/open-items.md`, unsure → `inbox/`.
- Before writing, search INDEX and grep for an existing note; update it instead of creating a new one. Every new note gets frontmatter and an INDEX line.
- Value filter: only write what will be useful again later, not session-specific detail.
- When the same kind of task repeats 2-3 times, suggest turning it into a skill.
- When `inbox/` fills up (10+ notes) or once a week: sort, merge, move old notes to `archive/`.

## If your tool has no MindPalace hooks
Some tools load these rules but cannot run hooks. Then do the hooks' job yourself:
- At the start of a session inside `{{VAULT}}`: read `memory/profile.md`, `memory/last-session.md`, `memory/open-items.md` and `INDEX.md`. Inside `{{PROJECTS}}/<name>`: read `{{VAULT}}/projects/<name>.md`.
- Before the session ends (when the user says goodbye or the task is done): append a short entry to `{{VAULT}}/journal/YYYY-MM-DD.md` (`### HH:MM · [project] title`, then done / decisions / next step) and overwrite `memory/last-session.md` with it.
- Ask before running `rm -r`, `git push --force`, `git reset --hard`, or anything touching `.env` or `{{PRIVATE_DIR}}/`.

### Pending work and cut-off sessions (the job of the maintainer and the session-start hook)
- At the start of a session, check for work that is still pending:
  - Unchecked `- [ ]` lines in `{{VAULT}}/inbox/candidates-*.md`: sort them into the right notes (INDEX and grep first, update instead of duplicating), mark each `- [x] ... -> file`, and move a fully sorted file to `archive/`. Do this when it fits, or offer it to {{USER_NAME}}.
  - `{{VAULT}}/memory/in-progress.md` with content: an earlier session was cut off. Tell {{USER_NAME}} what it says (last request, last state) and ask whether to continue. Do not continue without a yes. If yes, pick up from the file, the last journal entry and the project's recent changes.
- While you work on something that takes more than a few minutes, keep `{{VAULT}}/memory/in-progress.md` current: date, the request, the state, the next step (a few lines). When the work is finished or you write the journal entry, empty the file (leave it in place).
- Commit vault changes only locally if the vault is a git repository. Never push.
