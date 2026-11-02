#!/bin/bash
# Zed agent: rules-only adapter. Global AGENTS.md (zed docs/src/ai/rules.md).
mp_rules_only "Zed agent" "zed" "${XDG_CONFIG_HOME:-$HOME/.config}/zed/AGENTS.md" "https://zed.dev"
