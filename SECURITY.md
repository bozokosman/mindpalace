# Security policy

## Supported versions
The latest release receives security fixes.

## Reporting a vulnerability
Please do not open a public issue. Use GitHub's "Report a vulnerability" button on the Security tab of this repository (private advisory).
Include what you found, how to reproduce it, and the version (`cat ~/.mindpalace/VERSION`). You can expect an answer within a week.

## Scope and design notes
- MindPalace has no server and no telemetry. Notes stay on your machine.
- Conversation text is scrubbed of common secret patterns before it reaches a model and again before it is written; scrubbing is best effort, not a guarantee.
- The command guard asks or blocks on risky shell commands; it is a safety net, not a sandbox.
- The optional maintainer runs an AI tool with file-edit permissions inside your vault only. It never pushes to a remote.
- Token files (`CLAUDE_OAUTH_TOKEN_FILE`) are read at run time, never logged, and `doctor.sh` checks they are mode 600.
