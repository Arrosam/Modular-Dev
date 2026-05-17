#!/usr/bin/env bash
# PostToolUse Agent: Reset to bus mode after any subagent completes
# FAIL-OPEN: any error → allow
trap 'exit 0' ERR

STATE_FILE=".claude/modular-dev-state.json"
[ ! -f "$STATE_FILE" ] && exit 0

echo '{"role":"bus","active_node":null}' > "$STATE_FILE"
exit 0
