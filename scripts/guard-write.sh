#!/usr/bin/env bash
# PreToolUse: Block writes outside active node's directory (dev mode only)
# Resolves actual node path from graph.json — supports custom layouts
# Normalizes Windows backslash paths for cross-platform compatibility
# FAIL-OPEN: any error → allow
trap 'exit 0' ERR

STATE_FILE=".claude/modular-dev-state.json"
[ ! -f "$STATE_FILE" ] && exit 0
grep -q '"role".*"dev"' "$STATE_FILE" 2>/dev/null || exit 0

ACTIVE_NODE=$(grep -o '"active_node".*"[^"]*"' "$STATE_FILE" 2>/dev/null | grep -o '[^"]*"$' | tr -d '"')
[ -z "$ACTIVE_NODE" ] && exit 0

# Resolve node's actual path from the nodes section of graph.json
NODE_PATH="packages/$ACTIVE_NODE"
if [ -f "graph.json" ]; then
  RESOLVED=$(awk -v node="$ACTIVE_NODE" '
    /"nodes"[[:space:]]*:/ { s=1 }
    /"contracts"[[:space:]]*:/ || /"shared"[[:space:]]*:/ || /"zones"[[:space:]]*:/ { s=0 }
    s && $0 ~ "\"" node "\"[[:space:]]*:" { f=1 }
    f && /"path"/ { sub(/.*"path"[[:space:]]*:[[:space:]]*"/, ""); sub(/".*/, ""); print; exit }
  ' graph.json 2>/dev/null)
  [ -n "$RESOLVED" ] && NODE_PATH="$RESOLVED"
fi

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | grep -o '"file_path"[^,}]*' | head -1 | grep -o '"[^"]*"$' | tr -d '"')
[ -z "$FILE_PATH" ] && FILE_PATH=$(echo "$INPUT" | grep -o '"path"[^,}]*' | head -1 | grep -o '"[^"]*"$' | tr -d '"')
[ -z "$FILE_PATH" ] && exit 0

# Normalize backslashes → forward slashes
NORM=$(echo "$FILE_PATH" | tr '\\' '/')

case "$NORM" in
  */"$NODE_PATH"/*|*/"$NODE_PATH"|"$NODE_PATH"/*|"$NODE_PATH") exit 0 ;;
esac

echo "[modular-dev] BLOCKED: Dev agent for '$ACTIVE_NODE' cannot write to '$FILE_PATH'." >&2
exit 2
