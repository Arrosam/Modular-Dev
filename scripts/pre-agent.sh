#!/usr/bin/env bash
# PreToolUse Agent: Set dev isolation state when a dev agent is spawned
# Detects the isolation directive in the prompt and records the active node
# path in a per-session state file: .claude/modular-dev-state/<session_id>.json
# FAIL-OPEN: any error → allow
trap 'exit 0' ERR

INPUT=$(cat | tr -d $'\r')

# Only act on dev-agent spawns — identified by the canonical isolation directive.
echo "$INPUT" | grep -q "create and modify files under" || exit 0

# Identify this session. Without a session id we cannot scope state safely → allow.
SESSION_ID=$(echo "$INPUT" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | grep -o '[^"]*"$' | tr -d $'"\r' | tr -cd 'A-Za-z0-9_-')
[ -z "$SESSION_ID" ] && exit 0

# Normalize any escaped slashes the prompt JSON may contain.
NORM_INPUT=$(echo "$INPUT" | sed 's#\\/#/#g')

# Primary: extract the backtick-quoted path from the directive
#   "...ONLY create and modify files under `<path>/`..."
ACTIVE_PATH=$(echo "$NORM_INPUT" | grep -o 'create and modify files under `[^`]*`' | head -1 | sed 's/.*`\([^`]*\)`/\1/')

# Fallback: legacy packages/<node>/ layout
if [ -z "$ACTIVE_PATH" ]; then
  ACTIVE_PATH=$(echo "$NORM_INPUT" | grep -o 'packages/[a-zA-Z0-9_-]*' | head -1)
fi

[ -z "$ACTIVE_PATH" ] && exit 0
ACTIVE_PATH="${ACTIVE_PATH%/}"

mkdir -p .claude/modular-dev-state 2>/dev/null
printf '{"role":"dev","active_path":"%s"}\n' "$ACTIVE_PATH" > ".claude/modular-dev-state/$SESSION_ID.json"

exit 0
