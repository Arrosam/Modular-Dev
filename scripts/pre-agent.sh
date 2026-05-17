#!/usr/bin/env bash
# PreToolUse Agent: Set dev isolation state when dev agent is spawned
# FAIL-OPEN: any error → allow
trap 'exit 0' ERR

[ ! -f "graph.json" ] && exit 0

INPUT=$(cat)

# Detect dev agent by looking for the isolation directive in the prompt
if echo "$INPUT" | grep -q "ONLY create and modify files under.*packages/"; then
  NODE_ID=$(echo "$INPUT" | grep -o 'packages/[a-zA-Z0-9_-]*/' | head -1 | sed 's|packages/||;s|/||')
  if [ -n "$NODE_ID" ]; then
    mkdir -p .claude 2>/dev/null
    echo "{\"role\":\"dev\",\"active_node\":\"$NODE_ID\"}" > .claude/modular-dev-state.json
  fi
fi

exit 0
