# graph.json schema

The dependency graph is the single source of truth for project structure. The bus agent reads this file to route tasks, partition zones, and determine BFS order.

## Schema

```json
{
  "project": {
    "name": "string",
    "description": "string",
    "created_at": "ISO 8601",
    "updated_at": "ISO 8601"
  },
  "zones": {
    "<zone-id>": {
      "description": "string — what this zone covers",
      "nodes": ["<node-id>", ...],
      "overview": "overviews/zones/<zone-id>.md"
    }
  },
  "nodes": {
    "<node-id>": {
      "zone": "<zone-id>",
      "path": "packages/<node-id>",
      "description": "string — one-line purpose",
      "depends_on_contracts": ["<contract-id>", ...],
      "implements_contracts": ["<contract-id>", ...],
      "status": "pending | in-progress | done | failed",
      "overview": "overviews/nodes/<node-id>.md"
    }
  },
  "contracts": {
    "<contract-id>": {
      "path": "contracts/<contract-id>",
      "connects": ["<node-id>", "<node-id>", ...],
      "test": "tests/<contract-id>.test.*",
      "status": "draft | locked | tested",
      "overview": "overviews/contracts/<contract-id>.md"
    }
  },
  "shared": {
    "<shared-id>": {
      "path": "shared/<shared-id>",
      "description": "string",
      "status": "pending | done"
    }
  }
}
```

## Status transitions

- Nodes: `pending` → `in-progress` → `done` (or `failed` → `pending` on retry)
- Contracts: `draft` → `locked` (before dev starts) → `tested` (after edge tests written)

## Zone partitioning rules

The bus partitions nodes into zones at session init using these heuristics:

1. Nodes that share contracts belong in the same zone (coupling affinity)
2. Each zone should contain 3-10 nodes; split or merge if outside this range
3. Isolated nodes (no shared contracts with others) form their own single-node zone
4. Zone IDs are descriptive slugs derived from the dominant function of their nodes

## BFS ordering

Determine development order by topological sort on the contract dependency graph:
1. Nodes whose `depends_on_contracts` are all `locked` or `tested` can be developed
2. Among eligible nodes, prioritize by: fewer dependencies first, then alphabetical
3. If circular dependency exists via contracts, all nodes in the cycle are eligible simultaneously (they depend on the contract abstraction, not on each other's implementation)
