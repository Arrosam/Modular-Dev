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

Analyze this task and produce a COMPLETE development spec for each affected node. The spec must be detailed enough that a dev agent can implement it without asking questions. Respond with:

1. Which nodes in your zone need modification (list node IDs)
2. For EACH affected node, a full implementation spec containing ALL of:
   a. Files to create or modify (exact file paths relative to the node directory)
   b. Functions/methods/classes to add or change (with signatures and parameter types)
   c. Data structures or state changes involved
   d. How this node interacts with its declared contracts (which interface methods are called, what data flows in/out)
   e. Edge cases and error handling expectations
   f. Any configuration or initialization changes
3. Which contracts are affected (list contract IDs and whether they need modification)
4. Whether other zones are impacted (list zone IDs and why)
5. Any ambiguities that CANNOT be resolved from the existing overviews — only flag genuine unknowns, do not ask about details you can infer from the contracts and overviews
```

### Iterate until spec is actionable

Review the zone manager's response. If any node spec is too vague to implement (e.g., says "update the handler" without specifying which methods change and how), re-prompt the zone manager:

```
Your spec for node <node-id> is not detailed enough. A dev agent needs to implement this without asking questions.

Missing details:
<list what's missing — e.g. "no method signatures", "unclear data flow from contract X", "no error handling spec">

Refine the spec with concrete file paths, method signatures, data structures, and integration points.
```

Repeat until every node has a spec that answers: what files, what functions, what data, how it connects to contracts. Do NOT present the plan to the user until all specs are implementation-ready.

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

Nodes to modify (in BFS order):
  1. [<node-id>] <one-line description of what this node does>
     Changes: <concise summary of what will be modified>
     Key details: <files affected, new methods/classes, data flow changes>
  2. [<node-id>] <one-line description of what this node does>
     Changes: <concise summary of what will be modified>
     Key details: <files affected, new methods/classes, data flow changes>
  ...

Estimated units of work: <N>

Proceed with this plan?
```

You MUST wait for explicit user approval before any development begins. Do NOT proceed to write tests, spawn dev agents, or modify any files until the user confirms.

**Once the user approves, the plan is final.** Running `/modular-dev:develop` after approval means the user has agreed to ALL planned changes. The develop phase will execute each node without per-node confirmation — it only interrupts for genuinely unexpected issues (contract insufficient, spec fundamentally wrong, new dependency needed).

Generate a unique queue ID using the current timestamp (`date +%Y%m%d-%H%M%S`). Save the work queue to `.claude/modular-dev-queue-<queue-id>.json`:

```json
{
  "queue_id": "<queue-id>",
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

Each session creates its own queue file. Multiple queues can coexist — they never overwrite each other.
