---
name: setup
description: Initialize a modular-dev project structure. Decomposes a project idea into independent package nodes connected by contract interfaces, creates the directory skeleton, graph.json, and overview files. Use when the user says "setup modular project", "set up modular-dev", "decompose this project", "create modular structure", "modular-dev setup", or wants to start a new project with the modular-dev pattern. Also triggers on "/modular-dev:setup".
---

# Initialize modular-dev project

You are setting up a divide-and-conquer project structure. The goal is to decompose the user's project idea into independent package nodes that communicate only through contract interfaces.

## Step 1: Understand the project

Ask the user to describe what they want to build. You need:
- What the project does (purpose)
- Who uses it (users/consumers)
- What the major functional areas are (the user may or may not know — help them think through it)

Do NOT proceed until you have a clear enough picture to identify at least 3 distinct functional areas.

## Step 2: Decompose into nodes and contracts

Based on the project description, identify:

**Nodes** — independent packages, each responsible for one cohesive functional area. Each node should:
- Be developable in isolation (an agent can build it without understanding other nodes)
- Have a clear, single responsibility
- Be small enough for an agent to hold in context (target: ≤500 lines of implementation)
- Communicate with other nodes ONLY through contracts

**Contracts** — interface definitions between nodes. Each contract should:
- Define the boundary between exactly 2+ nodes
- Specify methods/functions, their inputs, outputs, and behavioral expectations
- Be defined BEFORE implementation starts
- Be language-agnostic (describe in natural language or pseudocode unless the user specifies a language)

**Shared modules** — cross-cutting concerns (logging, config, error types) that every node may use.

Present the decomposition to the user as a table:

```
Proposed nodes:
| Node | Purpose | Depends on contracts |
|------|---------|---------------------|

Proposed contracts:
| Contract | Connects | Methods |
|----------|----------|---------|

Proposed shared:
| Module | Purpose |
|--------|---------|
```

Ask: "Does this decomposition look right? Should any nodes be merged, split, or renamed?"

Iterate until the user approves.

## Step 3: Create directory structure

Once approved, create the following directories and files:

```
<project-root>/
├── graph.json
├── overviews/
│   ├── project.md
│   ├── zones/          (empty — populated in step 4)
│   ├── nodes/<node-id>.md    (one per node)
│   └── contracts/<contract-id>.md  (one per contract)
├── contracts/<contract-id>/  (one dir per contract, with a definition file)
├── packages/<node-id>/       (one dir per node, with a README.md placeholder)
├── shared/<shared-id>/       (one dir per shared module)
└── tests/                    (empty — populated during edge test phase)
```

Read the templates from `references/overview-templates.md` in the plugin directory to generate overview files. Read the schema from `references/graph-schema.md` to generate `graph.json`.

## Step 4: Partition zones

After creating the structure, analyze the graph to partition nodes into zones:

1. Build an adjacency map: two nodes are "connected" if they share a contract
2. Group connected nodes using the coupling heuristic:
   - Start with the node that has the most contract connections
   - Add nodes that share contracts with the current group
   - When the group reaches 10 nodes or no more connected nodes exist, start a new group
   - Isolated nodes (no shared contracts) get their own single-node zone
3. If total nodes ≤ 10, create a single zone called "core" containing everything
4. Name each zone with a descriptive slug based on the dominant function of its nodes

For each zone:
- Add the zone entry to `graph.json`
- Create `overviews/zones/<zone-id>.md`
- Generate a temporary zone manager agent file at `.claude/agents/_zone-<zone-id>.md`

Read `references/bus-protocol.md` in the plugin directory for the zone manager agent template format.

## Step 5: Lock contracts

For each contract:
- Write the interface definition in `contracts/<contract-id>/` (format depends on user's tech stack — markdown by default, or .ts/.py/etc. if specified)
- Set contract status to `locked` in `graph.json`

## Step 6: Generate CLAUDE.md

Read the template from `references/CLAUDE.md.template` in the plugin directory. Write it to the project root as `CLAUDE.md`.

If a `CLAUDE.md` already exists in the project, append the modular-dev instructions under a clearly marked section:
```
<!-- modular-dev: START -->
<template content>
<!-- modular-dev: END -->
```

This is critical — `CLAUDE.md` is what makes the main session automatically follow the bus agent workflow in every future session. Without it, the user would need to manually invoke slash commands.

## Step 7: Initialize hook state

The plugin's hooks are automatically loaded by Claude Code from `hooks/hooks.json` — no manual installation needed.

There is no isolation state to initialize by hand: the hooks create and manage it per session under `.claude/modular-dev-state/<session-id>.json`. Just make sure the `.claude` directory exists for queue and state files:
```bash
mkdir -p .claude
```

## Step 8: Summary

Present the user with:
- Total nodes, contracts, shared modules, and zones created
- The BFS development order (which nodes can be built first)
- "The project is ready. Describe any task and I'll automatically analyze, plan, develop, test, and commit — no slash commands needed."

Commit the entire skeleton: `init: project skeleton with <N> nodes, <M> contracts`
