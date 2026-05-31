#!/usr/bin/env bash
# PreToolUse: Block git ops and test access via bash in dev mode
# State is per-session: .claude/modular-dev-state/<session_id>.json
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
