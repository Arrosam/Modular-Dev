#!/usr/bin/env bash
# PreToolUse Agent: Add this dev agent's node path to the session's active set.
# Supports MULTIPLE dev agents running concurrently in one bus session: the
# active set is a directory of marker files (one per node path), so concurrent
# pre-agent hooks never race on a shared cell.
#   State: .claude/modular-dev-state/<session_id>/paths/<sanitized>.path
#          (file content = the raw node path; a non-empty dir means dev mode)
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

# Add a marker file for this path. Sanitized filename keeps it unique per path;
# the file content carries the true path. Distinct filenames → no cross-agent race.
PATHS_DIR=".claude/modular-dev-state/$SESSION_ID/paths"
SAN=$(echo "$ACTIVE_PATH" | sed 's#[^A-Za-z0-9._-]#_#g')
mkdir -p "$PATHS_DIR" 2>/dev/null
printf '%s\n' "$ACTIVE_PATH" > "$PATHS_DIR/$SAN.path"

exit 0
