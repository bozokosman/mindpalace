---
type: decision
description: repeated mistakes and the rules they became (counted by the maintainer)
status: active
date: {{DATE}}
---
# Mistakes and lessons

## How it works
- A correction from {{USER_NAME}} or a repeated mistake is counted under "Records", one `###` entry per topic (short kebab-case name).
- The counter line is `COUNT · STATUS · LAST-DATE`. A first occurrence is `1 · observed · YYYY-MM-DD`.
- On the second occurrence the topic becomes `trial` and gets a one-line rule under "Active rules".
- A trial rule that does not repeat for 30 days becomes a `rule`. A rule that does not repeat for 90 days is retired to `archive/mistakes-retired.md`.
- At most 15 active rules; the one unused longest is retired first.
- The dates are checked by a script (`lessons.sh`), not by the model. Only the maintainer edits this file.

## Active rules
<!-- format: - [topic] (trial|rule) one-sentence rule -->

## Records
<!-- format: ### topic, then the counter line, then dated bullets -->
