#!/usr/bin/env bash
# PreToolUse: Block writes outside the active node's directory (dev mode only)
# State is per-session: .claude/modular-dev-state/<session_id>.json
# Resolves the active node path from the state file written by pre-agent.sh
# Normalizes Windows backslash paths and CRLF for cross-platform compatibility
# FAIL-OPEN: any error, or an unidentifiable session, → allow
trap 'exit 0' ERR

INPUT=$(cat | tr -d $'\r')

# Identify this session. No session id → fail open (allow).
SESSION_ID=$(echo "$INPUT" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | grep -o '[^"]*"$' | tr -d $'"\r' | tr -cd 'A-Za-z0-9_-')
[ -z "$SESSION_ID" ] && exit 0

STATE_FILE=".claude/modular-dev-state/$SESSION_ID.json"
[ ! -f "$STATE_FILE" ] && exit 0
grep -q '"role"[^}]*"dev"' "$STATE_FILE" 2>/dev/null || exit 0

ACTIVE_PATH=$(grep -o '"active_path"[[:space:]]*:[[:space:]]*"[^"]*"' "$STATE_FILE" 2>/dev/null | head -1 | grep -o '[^"]*"$' | tr -d $'"\r')
[ -z "$ACTIVE_PATH" ] && exit 0
ACTIVE_PATH="${ACTIVE_PATH%/}"

FILE_PATH=$(echo "$INPUT" | grep -o '"file_path"[^,}]*' | head -1 | grep -o '"[^"]*"$' | tr -d $'"\r')
[ -z "$FILE_PATH" ] && FILE_PATH=$(echo "$INPUT" | grep -o '"path"[^,}]*' | head -1 | grep -o '"[^"]*"$' | tr -d $'"\r')
[ -z "$FILE_PATH" ] && exit 0

# Normalize backslashes → forward slashes
NORM=$(echo "$FILE_PATH" | tr '\\' '/')

case "$NORM" in
  */"$ACTIVE_PATH"/*|*/"$ACTIVE_PATH"|"$ACTIVE_PATH"/*|"$ACTIVE_PATH") exit 0 ;;
esac

echo "[modular-dev] BLOCKED: Dev agent (scope '$ACTIVE_PATH') cannot write to '$FILE_PATH'." >&2
exit 2
