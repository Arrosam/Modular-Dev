#!/usr/bin/env bash
# PreToolUse Agent: Set dev isolation state when dev agent is spawned
# Detects the isolation directive in the prompt and ensures state is set
# Writes owner_pid ($PPID) so guard hooks only apply to this session
# FAIL-OPEN: any error → allow
trap 'exit 0' ERR

[ ! -f "graph.json" ] && exit 0

INPUT=$(cat)

# Detect dev agent by the isolation directive in the prompt
if echo "$INPUT" | grep -q "ONLY create and modify files under"; then
  # Try packages/<node>/ pattern first (skeleton layout)
  NODE_ID=$(echo "$INPUT" | grep -o 'packages/[a-zA-Z0-9_-]*/' | head -1 | sed 's|packages/||;s|/||')

  # If not found, use the active node already set by the bus
  if [ -z "$NODE_ID" ] && [ -f ".claude/modular-dev-state.json" ]; then
    NODE_ID=$(grep -o '"active_node".*"[^"]*"' .claude/modular-dev-state.json 2>/dev/null | grep -o '[^"]*"$' | tr -d '"')
  fi

  if [ -n "$NODE_ID" ]; then
    mkdir -p .claude 2>/dev/null
    NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "unknown")
    printf '{"role":"dev","active_node":"%s","owner_pid":"%s","since":"%s"}\n' "$NODE_ID" "$PPID" "$NOW" > .claude/modular-dev-state.json
  fi
fi

exit 0
