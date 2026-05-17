#!/usr/bin/env bash
# PreToolUse: Block reads of tests/ and other packages/ in dev mode
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
  tests/*)
    echo "[modular-dev] BLOCKED: Dev agent cannot read test files." >&2
    exit 2 ;;
  packages/"$ACTIVE_NODE"/*) exit 0 ;;
  packages/"$ACTIVE_NODE")   exit 0 ;;
  packages/*)
    echo "[modular-dev] BLOCKED: Dev agent for '$ACTIVE_NODE' cannot read other packages." >&2
    exit 2 ;;
esac

exit 0
