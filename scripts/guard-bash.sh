#!/usr/bin/env bash
# PreToolUse: Block git ops and test access via bash in dev mode
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

INPUT=$(cat | tr -d $'\r')
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
