#!/bin/bash
# OpenCode: rules-only adapter. Global AGENTS.md (opencode.ai/docs/rules).
mp_rules_only "OpenCode" "opencode" "${XDG_CONFIG_HOME:-$HOME/.config}/opencode/AGENTS.md" "https://opencode.ai"
