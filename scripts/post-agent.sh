#!/usr/bin/env bash
# PostToolUse Agent: Reset this session to bus mode after a subagent completes
# State is per-session: .claude/modular-dev-state/<session_id>.json
# FAIL-OPEN: any error → allow
trap 'exit 0' ERR

INPUT=$(cat | tr -d $'\r')

SESSION_ID=$(echo "$INPUT" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | grep -o '[^"]*"$' | tr -d $'"\r' | tr -cd 'A-Za-z0-9_-')
[ -z "$SESSION_ID" ] && exit 0

STATE_FILE=".claude/modular-dev-state/$SESSION_ID.json"
[ -f "$STATE_FILE" ] || exit 0

echo '{"role":"bus","active_path":null}' > "$STATE_FILE"
exit 0
