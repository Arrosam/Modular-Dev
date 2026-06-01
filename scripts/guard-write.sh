#!/usr/bin/env bash
# PreToolUse: Block writes outside the active nodes' directories (dev mode only).
# Supports MULTIPLE concurrent dev agents: the session's active set is a dir of
# marker files at .claude/modular-dev-state/<session_id>/paths/*.path (each file
# holds one node path). A write is allowed if it falls under ANY active path.
# Normalizes Windows backslash paths and CRLF for cross-platform compatibility.
# FAIL-OPEN: any error, or an unidentifiable session, → allow
trap 'exit 0' ERR

INPUT=$(cat | tr -d $'\r')

# Identify this session. No session id → fail open (allow).
SESSION_ID=$(echo "$INPUT" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | grep -o '[^"]*"$' | tr -d $'"\r' | tr -cd 'A-Za-z0-9_-')
[ -z "$SESSION_ID" ] && exit 0

PATHS_DIR=".claude/modular-dev-state/$SESSION_ID/paths"
# Dev mode is active only while the set is non-empty.
[ -d "$PATHS_DIR" ] || exit 0
ls "$PATHS_DIR"/*.path >/dev/null 2>&1 || exit 0

FILE_PATH=$(echo "$INPUT" | grep -o '"file_path"[^,}]*' | head -1 | grep -o '"[^"]*"$' | tr -d $'"\r')
[ -z "$FILE_PATH" ] && FILE_PATH=$(echo "$INPUT" | grep -o '"path"[^,}]*' | head -1 | grep -o '"[^"]*"$' | tr -d $'"\r')
[ -z "$FILE_PATH" ] && exit 0

# Normalize backslashes → forward slashes
NORM=$(echo "$FILE_PATH" | tr '\\' '/')

# Allow if the target falls under ANY active node path.
for f in "$PATHS_DIR"/*.path; do
  [ -f "$f" ] || continue
  P=$(tr -d $'\r' < "$f")
  P="${P%/}"
  [ -z "$P" ] && continue
  case "$NORM" in
    */"$P"/*|*/"$P"|"$P"/*|"$P") exit 0 ;;
  esac
done

echo "[modular-dev] BLOCKED: Dev agent cannot write to '$FILE_PATH' — outside all active node scopes." >&2
exit 2
