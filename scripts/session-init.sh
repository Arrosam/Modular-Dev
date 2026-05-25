#!/usr/bin/env bash
# SessionStart: Load modular-dev project context
# FAIL-OPEN: any error → exit silently
trap 'exit 0' ERR

GRAPH_FILE="graph.json"
[ ! -f "$GRAPH_FILE" ] && exit 0

mkdir -p .claude 2>/dev/null

# Only reset state to bus mode if no dev agent is currently active
# (another session might be running a dev agent — don't break its isolation)
SHOULD_RESET=1
if [ -f ".claude/modular-dev-state.json" ]; then
  if grep -q '"role".*"dev"' .claude/modular-dev-state.json 2>/dev/null; then
    # Check if the dev lock is stale (older than 30 minutes)
    SINCE=$(grep -o '"since"[[:space:]]*:[[:space:]]*"[^"]*"' .claude/modular-dev-state.json 2>/dev/null | grep -o '"[^"]*"$' | tr -d '"')
    if [ -n "$SINCE" ]; then
      SINCE_EPOCH=$(date -d "$SINCE" +%s 2>/dev/null || date -jf "%Y-%m-%dT%H:%M:%S" "$SINCE" +%s 2>/dev/null || echo "0")
      NOW_EPOCH=$(date +%s 2>/dev/null || echo "0")
      DIFF=$((NOW_EPOCH - SINCE_EPOCH))
      if [ "$DIFF" -lt 1800 ]; then
        SHOULD_RESET=0
      fi
    else
      # No timestamp — could be stale legacy state, but be safe
      SHOULD_RESET=0
    fi
  fi
fi

if [ "$SHOULD_RESET" -eq 1 ]; then
  echo '{"role":"bus","active_node":null,"since":null}' > .claude/modular-dev-state.json
fi

# Extract project name (simple grep, no python3)
PROJECT_NAME=$(grep -o '"name"[[:space:]]*:[[:space:]]*"[^"]*"' "$GRAPH_FILE" | head -1 | grep -o '"[^"]*"$' | tr -d '"')
[ -z "$PROJECT_NAME" ] && PROJECT_NAME="unknown"

# Count nodes by status
TOTAL_NODES=$(grep -c '"status"' "$GRAPH_FILE" 2>/dev/null || echo "0")
DONE_NODES=$(grep -c '"done"' "$GRAPH_FILE" 2>/dev/null || echo "0")

# Queue status — scan all session-specific queue files
QUEUE_MSG="No active queue"
TOTAL_PENDING=0
QUEUE_COUNT=0
for f in .claude/modular-dev-queue-*.json .claude/modular-dev-queue.json; do
  [ -f "$f" ] || continue
  P=$(grep -c '"pending"' "$f" 2>/dev/null || echo "0")
  TOTAL_PENDING=$((TOTAL_PENDING + P))
  QUEUE_COUNT=$((QUEUE_COUNT + 1))
done
if [ "$QUEUE_COUNT" -gt 0 ]; then
  QUEUE_MSG="${TOTAL_PENDING} items pending across ${QUEUE_COUNT} queue(s)"
fi

# Warn if another dev agent is active
DEV_WARN=""
if [ "$SHOULD_RESET" -eq 0 ]; then
  ACTIVE=$(grep -o '"active_node"[[:space:]]*:[[:space:]]*"[^"]*"' .claude/modular-dev-state.json 2>/dev/null | grep -o '"[^"]*"$' | tr -d '"')
  DEV_WARN=" WARNING: another session has a dev agent active for node ${ACTIVE}."
fi

# Output must be valid JSON - use simple safe string
printf '{"additionalContext":"[modular-dev] Bus agent active. Project: %s. Nodes: %s/%s done. Queue: %s.%s Follow the workflow in CLAUDE.md automatically."}\n' \
  "$PROJECT_NAME" "$DONE_NODES" "$TOTAL_NODES" "$QUEUE_MSG" "$DEV_WARN"

exit 0
