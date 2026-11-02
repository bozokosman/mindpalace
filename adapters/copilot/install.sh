#!/bin/bash
# GitHub Copilot CLI: rules-only adapter. Has Claude-style hooks too; full adapter planned for v1.2.
mp_rules_only "GitHub Copilot CLI" "copilot" "${COPILOT_HOME:-$HOME/.copilot}/copilot-instructions.md" "https://github.com/github/copilot-cli"
