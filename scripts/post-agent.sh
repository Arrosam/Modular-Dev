#!/usr/bin/env bash
# PostToolUse Agent: Remove the finished dev agent's node path from the active
# set. With concurrent dev agents, we must clear ONLY the path of the agent that
# just returned — not the whole set — or a sibling agent still running would lose
# its isolation. We recover that path from the completed Agent call's prompt
# (tool_input), the same directive pre-agent.sh keyed on.
#   State: .claude/modular-dev-state/<session_id>/paths/<sanitized>.path
# FAIL-OPEN: any error → allow
trap 'exit 0' ERR

INPUT=$(cat | tr -d $'\r')

SESSION_ID=$(echo "$INPUT" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | grep -o '[^"]*"$' | tr -d $'"\r' | tr -cd 'A-Za-z0-9_-')
[ -z "$SESSION_ID" ] && exit 0

PATHS_DIR=".claude/modular-dev-state/$SESSION_ID/paths"
[ -d "$PATHS_DIR" ] || exit 0

# Recover the finished agent's node path from the completion payload (the same
# canonical directive). The PostToolUse[Agent] payload exposing the prompt is not
# guaranteed across versions, so this is best-effort.
NORM_INPUT=$(echo "$INPUT" | sed 's#\\/#/#g')
DONE_PATH=$(echo "$NORM_INPUT" | grep -o 'create and modify files under `[^`]*`' | head -1 | sed 's/.*`\([^`]*\)`/\1/')
[ -z "$DONE_PATH" ] && DONE_PATH=$(echo "$NORM_INPUT" | grep -o 'packages/[a-zA-Z0-9_-]*' | head -1)
DONE_PATH="${DONE_PATH%/}"

if [ -n "$DONE_PATH" ]; then
  # Remove just this agent's marker.
  SAN=$(echo "$DONE_PATH" | sed 's#[^A-Za-z0-9._-]#_#g')
  rm -f "$PATHS_DIR/$SAN.path" 2>/dev/null
else
  # Could not identify which agent finished. If exactly one is active, it must be
  # this one — safe to clear. If several are active we cannot tell which returned,
  # so leave the set intact (a SessionStart sweep / explicit clear will reset it)
  # rather than wrongly unlocking a still-running sibling.
  COUNT=$(find "$PATHS_DIR" -maxdepth 1 -name '*.path' -type f 2>/dev/null | wc -l | tr -d ' ')
  [ "$COUNT" = "1" ] && rm -f "$PATHS_DIR"/*.path 2>/dev/null
fi

# If the active set is now empty, remove the dir so guards see plain bus mode.
rmdir "$PATHS_DIR" 2>/dev/null || true

exit 0
