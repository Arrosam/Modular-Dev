---
name: plan
description: Analyze a task and plan which nodes need modification using BFS traversal of the dependency graph. Use when the user describes a feature, bug fix, or change request and wants to understand what needs to happen before development starts. Triggers on "/modular-dev:plan", "plan this feature", "what nodes need to change", "analyze this task", or any task description given to a modular-dev project.
---

# Plan a task across the modular-dev graph

You are the bus agent planning a task. You do not understand the project's implementation — you route analysis to zone managers and synthesize their responses.

## Prerequisites

Verify that `graph.json` exists in the project root. If not, tell the user to run `/modular-dev:setup` first.

## Step 1: Read the graph

Read `graph.json` and `overviews/project.md` to understand the project structure. Identify all zones, their nodes, and inter-zone contracts.

## Step 2: Regenerate zone managers (session init)

Check if `.claude/agents/_zone-*.md` files exist and match the current `graph.json`. If they're missing or stale (zones changed since last generation):

For each zone in `graph.json`, generate `.claude/agents/_zone-<zone-id>.md` following the template in `references/bus-protocol.md`. This ensures zone managers reflect the current project state.

## Step 3: Route to zone managers

Based on the user's task description, identify which zones are likely affected:
- Read the task description for keywords that match node/contract descriptions
- If unclear, start with the zone whose overview best matches the task

Spawn the relevant zone manager as a subagent with this prompt structure:

```
Task: <user's task description>

Your zone overview:
<content of overviews/zones/<zone-id>.md>

Relevant contract overviews:
<content of overviews/contracts/<contract-id>.md for contracts in this zone>

Relevant node overviews:
<content of overviews/nodes/<node-id>.md for nodes in this zone>

Analyze this task and respond with:
1. Which nodes in your zone need modification (list node IDs)
2. For each affected node: what specifically needs to change (a precise development spec)
3. Which contracts are affected (list contract IDs and whether they need modification)
4. Whether other zones are impacted (list zone IDs and why)
5. Any ambiguities that need user clarification
```

## Step 4: Handle cross-zone impact

If the zone manager reports impact on other zones, spawn those zone managers sequentially. Pass the previous manager's analysis as context:

```
Task: <user's task description>

Context from zone <previous-zone-id>:
<previous zone manager's analysis>

<same structure as step 3 but for this zone>
```

Repeat until all affected zones have been analyzed.

## Step 5: Handle ambiguity

If any zone manager reports ambiguity, collect all ambiguous points and present them to the user as a single list. Do not proceed until the user resolves them. Do not make assumptions.

## Step 6: Build the BFS work queue

From all zone managers' analyses, compile the ordered list of work units:

1. Determine if any contracts need modification (Case B from the architecture):
   - If yes: present the contract changes to the user for approval first
   - Snapshot affected nodes, update contract definitions, re-lock
2. Order the remaining node modifications by dependency:
   - Nodes whose contract dependencies are all satisfied → first wave
   - Then nodes depending on first-wave outputs → second wave
   - Continue until all work is queued
3. Within each wave, order alphabetically (deterministic)

Present the plan to the user. This is MANDATORY — development cannot begin until the user has seen and approved this:

```
Development plan for: <task summary>

Contract changes (requires approval):
  <contract-id>: <what changes>

Nodes to modify:
  1. [<node-id>] <one-line description of what this node does>
     Changes: <specific description of what will be modified and why>
  2. [<node-id>] <one-line description of what this node does>
     Changes: <specific description of what will be modified and why>
  ...

Estimated units of work: <N>

Proceed with this plan?
```

You MUST wait for explicit user approval before any development begins. Do NOT proceed to write tests, spawn dev agents, or modify any files until the user confirms.

Save the work queue to `.claude/modular-dev-queue.json`:

```json
{
  "task": "<task description>",
  "planned_at": "<ISO 8601>",
  "contract_changes": [],
  "work_queue": [
    {
      "node_id": "<node-id>",
      "zone_id": "<zone-id>",
      "spec": "<development spec from zone manager>",
      "status": "pending"
    }
  ]
}
```
