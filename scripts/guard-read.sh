#!/usr/bin/env bash
# PreToolUse: Block reads of tests/ and other nodes' directories in dev mode
# Resolves actual node paths from graph.json — supports custom layouts
# Normalizes Windows backslash paths for cross-platform compatibility
# FAIL-OPEN: any error → allow
trap 'exit 0' ERR

STATE_FILE=".claude/modular-dev-state.json"
[ ! -f "$STATE_FILE" ] && exit 0
grep -q '"role".*"dev"' "$STATE_FILE" 2>/dev/null || exit 0

# Cross-session safety: if state was set by a different Claude Code process, skip blocking
OWNER_PID=$(grep -o '"owner_pid"[[:space:]]*:[[:space:]]*"[^"]*"' "$STATE_FILE" 2>/dev/null | grep -o '"[^"]*"$' | tr -d $'"\r')
if [ -n "$OWNER_PID" ] && [ -n "$PPID" ] && [ "$OWNER_PID" != "$PPID" ]; then
  exit 0
fi

ACTIVE_NODE=$(grep -o '"active_node".*"[^"]*"' "$STATE_FILE" 2>/dev/null | grep -o '[^"]*"$' | tr -d $'"\r')
[ -z "$ACTIVE_NODE" ] && exit 0

# Resolve node's actual path from the nodes section of graph.json
NODE_PATH="packages/$ACTIVE_NODE"
if [ -f "graph.json" ]; then
  RESOLVED=$(awk -v node="$ACTIVE_NODE" '
    /"nodes"[[:space:]]*:/ { s=1 }
    /"contracts"[[:space:]]*:/ || /"shared"[[:space:]]*:/ || /"zones"[[:space:]]*:/ { s=0 }
    s && $0 ~ "\"" node "\"[[:space:]]*:" { f=1 }
    f && /"path"/ { sub(/.*"path"[[:space:]]*:[[:space:]]*"/, ""); sub(/".*/, ""); gsub(/\r/, ""); print; exit }
  ' graph.json 2>/dev/null)
  [ -n "$RESOLVED" ] && NODE_PATH="$RESOLVED"
fi

INPUT=$(cat | tr -d $'\r')
FILE_PATH=$(echo "$INPUT" | grep -o '"file_path"[^,}]*' | head -1 | grep -o '"[^"]*"$' | tr -d $'"\r')
[ -z "$FILE_PATH" ] && FILE_PATH=$(echo "$INPUT" | grep -o '"path"[^,}]*' | head -1 | grep -o '"[^"]*"$' | tr -d $'"\r')
[ -z "$FILE_PATH" ] && exit 0

# Normalize backslashes → forward slashes
NORM=$(echo "$FILE_PATH" | tr '\\' '/')

# Block test files
case "$NORM" in
  tests/*|*/tests/*)
    echo "[modular-dev] BLOCKED: Dev agent cannot read test files." >&2
    exit 2 ;;
esac

# Allow own node directory
case "$NORM" in
  */"$NODE_PATH"/*|*/"$NODE_PATH"|"$NODE_PATH"/*|"$NODE_PATH") exit 0 ;;
esac

# Block other nodes' directories (only paths from the nodes section)
if [ -f "graph.json" ]; then
  while IFS= read -r P; do
    [ -z "$P" ] || [ "$P" = "$NODE_PATH" ] && continue
    case "$NORM" in
      */"$P"/*|*/"$P"|"$P"/*|"$P")
        echo "[modular-dev] BLOCKED: Dev agent for '$ACTIVE_NODE' cannot read other packages." >&2
        exit 2 ;;
    esac
  done <<< "$(awk '
    /"nodes"[[:space:]]*:/ { s=1 }
    /"contracts"[[:space:]]*:/ || /"shared"[[:space:]]*:/ || /"zones"[[:space:]]*:/ { s=0 }
    s && /"path"/ { sub(/.*"path"[[:space:]]*:[[:space:]]*"/, ""); sub(/".*/, ""); gsub(/\r/, ""); if ($0 != "") print }
  ' graph.json 2>/dev/null)"
fi

exit 0
