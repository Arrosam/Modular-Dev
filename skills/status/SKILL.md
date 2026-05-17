---
name: status
description: Display the current state of a modular-dev project — nodes, contracts, zones, and development progress. Use when the user says "status", "show progress", "what's done", "project status", "graph status", or "/modular-dev:status".
---

# Show project status

Read `graph.json` and present a clear summary of the project state.

## Output format

```
Project: <name>
Zones: <N> | Nodes: <done>/<total> | Contracts: <tested>/<total>

Zones:
  <zone-id> [<done>/<total> nodes]
    ✓ <node-id> — <one-line description>
    ◻ <node-id> — <one-line description>  [pending]
    ✗ <node-id> — <one-line description>  [failed]

Contracts:
  ✓ <contract-id>: <node-a> ↔ <node-b>  [tested]
  ◻ <contract-id>: <node-a> ↔ <node-b>  [locked]

Shared:
  ✓ <shared-id> — <description>

Current queue:
  <If .claude/modular-dev-queue.json exists, show pending items>
  <If no queue, show "No active work queue. Run /modular-dev:plan to create one.">

Next developable nodes:
  <List nodes whose dependencies are all satisfied and status is pending>
```

Use simple ASCII indicators: `✓` done, `◻` pending, `✗` failed, `⟳` in-progress.

If the user asks for more detail about a specific node or contract, read its overview file and present the content.
