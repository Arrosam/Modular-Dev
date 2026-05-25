#!/usr/bin/env bash
# PostToolUse Agent: Reset to bus mode after any subagent completes
# Only resets if currently in dev mode — avoids blindly overwriting state
# that another concurrent session may have set
# FAIL-OPEN: any error → allow
trap 'exit 0' ERR

STATE_FILE=".claude/modular-dev-state.json"
[ ! -f "$STATE_FILE" ] && exit 0

# Only reset if currently in dev mode (this session's dev agent just finished)
grep -q '"role".*"dev"' "$STATE_FILE" 2>/dev/null || exit 0

echo '{"role":"bus","active_node":null,"since":null}' > "$STATE_FILE"
exit 0
