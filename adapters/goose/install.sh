#!/bin/bash
# Goose: rules-only adapter. Global .goosehints.
mp_rules_only "Goose" "goose" "${XDG_CONFIG_HOME:-$HOME/.config}/goose/.goosehints" "https://block.github.io/goose"
