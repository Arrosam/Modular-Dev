#!/usr/bin/env bash
# PreToolUse: Block reads of tests/ and other nodes' directories in dev mode.
# Supports MULTIPLE concurrent dev agents: the session's active set is a dir of
# marker files at .claude/modular-dev-state/<session_id>/paths/*.path. A read is
# allowed if it falls under ANY active path; other nodes' dirs (from graph.json)
# stay blocked, and tests/ is always blocked.
# Normalizes Windows backslash paths and CRLF for cross-platform compatibility.
# FAIL-OPEN: any error, or an unidentifiable session, → allow
trap 'exit 0' ERR

INPUT=$(cat | tr -d $'\r')

# Identify this session. No session id → fail open (allow).
SESSION_ID=$(echo "$INPUT" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | grep -o '[^"]*"$' | tr -d $'"\r' | tr -cd 'A-Za-z0-9_-')
[ -z "$SESSION_ID" ] && exit 0

PATHS_DIR=".claude/modular-dev-state/$SESSION_ID/paths"
[ -d "$PATHS_DIR" ] || exit 0
ls "$PATHS_DIR"/*.path >/dev/null 2>&1 || exit 0

FILE_PATH=$(echo "$INPUT" | grep -o '"file_path"[^,}]*' | head -1 | grep -o '"[^"]*"$' | tr -d $'"\r')
[ -z "$FILE_PATH" ] && FILE_PATH=$(echo "$INPUT" | grep -o '"path"[^,}]*' | head -1 | grep -o '"[^"]*"$' | tr -d $'"\r')
[ -z "$FILE_PATH" ] && exit 0

# Normalize backslashes → forward slashes
NORM=$(echo "$FILE_PATH" | tr '\\' '/')

# Block test files (always, regardless of active set)
case "$NORM" in
  tests/*|*/tests/*)
    echo "[modular-dev] BLOCKED: Dev agent cannot read test files." >&2
    exit 2 ;;
esac

# Allow if the target falls under ANY active node path.
ACTIVE_LIST=""
for f in "$PATHS_DIR"/*.path; do
  [ -f "$f" ] || continue
  P=$(tr -d $'\r' < "$f")
  P="${P%/}"
  [ -z "$P" ] && continue
  ACTIVE_LIST="$ACTIVE_LIST$P
"
  case "$NORM" in
    */"$P"/*|*/"$P"|"$P"/*|"$P") exit 0 ;;
  esac
done

# Block other nodes' directories (paths from the nodes section of graph.json that
# are NOT in this session's active set).
if [ -f "graph.json" ]; then
  while IFS= read -r NODE_P; do
    NODE_P="${NODE_P%/}"
    [ -z "$NODE_P" ] && continue
    # Skip if this node path is one of our active paths.
    printf '%s\n' "$ACTIVE_LIST" | grep -qxF "$NODE_P" && continue
    case "$NORM" in
      */"$NODE_P"/*|*/"$NODE_P"|"$NODE_P"/*|"$NODE_P")
        echo "[modular-dev] BLOCKED: Dev agent cannot read other packages (scope is the active node set)." >&2
        exit 2 ;;
    esac
  done <<< "$(awk '
    /"nodes"[[:space:]]*:/ { s=1 }
    /"contracts"[[:space:]]*:/ || /"shared"[[:space:]]*:/ || /"zones"[[:space:]]*:/ { s=0 }
    s && /"path"/ { sub(/.*"path"[[:space:]]*:[[:space:]]*"/, ""); sub(/".*/, ""); gsub(/\r/, ""); if ($0 != "") print }
  ' graph.json 2>/dev/null)"
fi

exit 0
