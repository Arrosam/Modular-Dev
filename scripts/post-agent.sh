#!/usr/bin/env bash
# PostToolUse Agent: Reset to bus mode after any subagent completes
# Only resets if currently in dev mode AND owned by this session (owner_pid matches)
# FAIL-OPEN: any error → allow
trap 'exit 0' ERR

STATE_FILE=".claude/modular-dev-state.json"
[ ! -f "$STATE_FILE" ] && exit 0

# Only reset if currently in dev mode
grep -q '"role".*"dev"' "$STATE_FILE" 2>/dev/null || exit 0

# Only reset if this session owns the state (or no owner_pid set — legacy)
OWNER_PID=$(grep -o '"owner_pid"[[:space:]]*:[[:space:]]*"[^"]*"' "$STATE_FILE" 2>/dev/null | grep -o '"[^"]*"$' | tr -d $'"\r')
if [ -n "$OWNER_PID" ] && [ -n "$PPID" ] && [ "$OWNER_PID" != "$PPID" ]; then
  exit 0  # Not our lock — don't touch it
fi

echo '{"role":"bus","active_node":null,"owner_pid":null,"since":null}' > "$STATE_FILE"
exit 0
