#!/usr/bin/env bash
# PreToolUse: Block reads of tests/ and other nodes' directories in dev mode
# State is per-session: .claude/modular-dev-state/<session_id>.json
# Other node paths are enumerated from graph.json — supports custom layouts
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

# Block test files
case "$NORM" in
  tests/*|*/tests/*)
    echo "[modular-dev] BLOCKED: Dev agent cannot read test files." >&2
    exit 2 ;;
esac

# Allow own node directory
case "$NORM" in
  */"$ACTIVE_PATH"/*|*/"$ACTIVE_PATH"|"$ACTIVE_PATH"/*|"$ACTIVE_PATH") exit 0 ;;
esac

# Block other nodes' directories (only paths from the nodes section of graph.json)
if [ -f "graph.json" ]; then
  while IFS= read -r P; do
    P="${P%/}"
    { [ -z "$P" ] || [ "$P" = "$ACTIVE_PATH" ]; } && continue
    case "$NORM" in
      */"$P"/*|*/"$P"|"$P"/*|"$P")
        echo "[modular-dev] BLOCKED: Dev agent (scope '$ACTIVE_PATH') cannot read other packages." >&2
        exit 2 ;;
    esac
  done <<< "$(awk '
    /"nodes"[[:space:]]*:/ { s=1 }
    /"contracts"[[:space:]]*:/ || /"shared"[[:space:]]*:/ || /"zones"[[:space:]]*:/ { s=0 }
    s && /"path"/ { sub(/.*"path"[[:space:]]*:[[:space:]]*"/, ""); sub(/".*/, ""); gsub(/\r/, ""); if ($0 != "") print }
  ' graph.json 2>/dev/null)"
fi

exit 0
