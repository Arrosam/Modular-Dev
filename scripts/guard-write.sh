#!/usr/bin/env bash
# PreToolUse: Block writes outside active node's package (dev mode only)
# FAIL-OPEN: any error → allow
trap 'exit 0' ERR

STATE_FILE=".claude/modular-dev-state.json"
[ ! -f "$STATE_FILE" ] && exit 0
grep -q '"role".*"dev"' "$STATE_FILE" 2>/dev/null || exit 0

ACTIVE_NODE=$(grep -o '"active_node".*"[^"]*"' "$STATE_FILE" 2>/dev/null | grep -o '[^"]*"$' | tr -d '"')
[ -z "$ACTIVE_NODE" ] && exit 0

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | grep -o '"file_path"[^,}]*' | head -1 | grep -o '"[^"]*"$' | tr -d '"')
[ -z "$FILE_PATH" ] && FILE_PATH=$(echo "$INPUT" | grep -o '"path"[^,}]*' | head -1 | grep -o '"[^"]*"$' | tr -d '"')
[ -z "$FILE_PATH" ] && exit 0

case "$FILE_PATH" in
  packages/"$ACTIVE_NODE"/*) exit 0 ;;
  packages/"$ACTIVE_NODE")   exit 0 ;;
esac

echo "[modular-dev] BLOCKED: Dev agent for '$ACTIVE_NODE' cannot write to '$FILE_PATH'." >&2
exit 2
