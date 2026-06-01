#!/usr/bin/env bash
# PreToolUse: Block git ops and test access via bash in dev mode.
# Dev mode is active while the session's active-path set is non-empty:
#   .claude/modular-dev-state/<session_id>/paths/*.path
# Normalizes Windows backslash paths and CRLF for cross-platform compatibility
# FAIL-OPEN: any error, or an unidentifiable session, → allow
trap 'exit 0' ERR

INPUT=$(cat | tr -d $'\r')

# Identify this session. No session id → fail open (allow).
SESSION_ID=$(echo "$INPUT" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | grep -o '[^"]*"$' | tr -d $'"\r' | tr -cd 'A-Za-z0-9_-')
[ -z "$SESSION_ID" ] && exit 0

PATHS_DIR=".claude/modular-dev-state/$SESSION_ID/paths"
[ -d "$PATHS_DIR" ] || exit 0
ls "$PATHS_DIR"/*.path >/dev/null 2>&1 || exit 0

COMMAND=$(echo "$INPUT" | grep -o '"command"[^}]*' | head -1 | sed 's/^"command"[[:space:]]*:[[:space:]]*"//' | sed 's/"[[:space:]]*$//')
[ -z "$COMMAND" ] && exit 0

# Normalize backslashes for path matching
NORM_CMD=$(echo "$COMMAND" | tr '\\' '/')

# Block git write operations in dev mode
if echo "$NORM_CMD" | grep -qE '^\s*git\s+(commit|push|checkout|reset|merge|rebase|tag|stash)'; then
  echo "[modular-dev] BLOCKED: Dev agent cannot run git operations." >&2
  exit 2
fi

# Block reading tests/ via shell
if echo "$NORM_CMD" | grep -qE '(cat|less|head|tail|more|bat)\s+.*tests/'; then
  echo "[modular-dev] BLOCKED: Dev agent cannot read test files via shell." >&2
  exit 2
fi

if echo "$NORM_CMD" | grep -qE '(ls|find|tree)\s+.*tests(/|$|\s)'; then
  echo "[modular-dev] BLOCKED: Dev agent cannot browse the tests directory." >&2
  exit 2
fi

exit 0
