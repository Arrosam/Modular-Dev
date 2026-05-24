#!/usr/bin/env bash
# SessionStart: Load modular-dev project context
# FAIL-OPEN: any error → exit silently
trap 'exit 0' ERR

GRAPH_FILE="graph.json"
[ ! -f "$GRAPH_FILE" ] && exit 0

# Reset state to bus mode
mkdir -p .claude 2>/dev/null
echo '{"role":"bus","active_node":null}' > .claude/modular-dev-state.json

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

# Output must be valid JSON - use simple safe string
printf '{"additionalContext":"[modular-dev] Bus agent active. Project: %s. Nodes: %s/%s done. Queue: %s. Follow the workflow in CLAUDE.md automatically."}\n' \
  "$PROJECT_NAME" "$DONE_NODES" "$TOTAL_NODES" "$QUEUE_MSG"

exit 0
