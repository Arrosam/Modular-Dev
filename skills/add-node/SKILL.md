---
name: add-node
description: Add a new package node to an existing modular-dev project. Creates the package directory, overview file, updates graph.json, and re-partitions zones if needed. Use when the user says "add a node", "new module", "add package", "I need a new component", or "/modular-dev:add-node".
---

# Add a new node

## Step 1: Gather node information

Ask the user (or extract from context):
1. What does this node do? (purpose)
2. Which existing contracts will it implement or depend on?
3. Does it need new contracts to connect to existing nodes?

## Step 2: Create the node

1. Choose a `node-id` slug (lowercase, hyphenated)
2. Create `packages/<node-id>/` with a README.md placeholder
3. Create `overviews/nodes/<node-id>.md` using the template from `references/overview-templates.md`
4. Add the node entry to `graph.json` with status `pending`

## Step 3: Create new contracts if needed

If the new node requires contracts that don't exist yet:
1. Define each new contract's interface with the user
2. Create `contracts/<contract-id>/` with the definition file
3. Create `overviews/contracts/<contract-id>.md`
4. Add contract entries to `graph.json` with status `locked`
5. Create placeholder test files in `tests/`

## Step 4: Re-partition zones

Read the updated `graph.json` and re-run zone partitioning:
1. Check if the new node shares contracts with nodes in an existing zone → add it there
2. If it shares contracts with multiple zones → add to the zone with strongest coupling
3. If it has no contract connections → create a single-node zone
4. Update zone entries in `graph.json`
5. Update `overviews/zones/<zone-id>.md` for affected zones
6. Regenerate `.claude/agents/_zone-*.md` for affected zones

## Step 5: Commit

```
git commit --only --no-verify -m "[modular-dev] add-node: <node-id>" -- graph.json overviews/nodes/<node-id>.md <node-path>/
```

Report: "Node `<node-id>` added to zone `<zone-id>`. Run `/modular-dev:plan <task>` to plan its development."
