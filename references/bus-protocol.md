# Bus agent protocol

The bus agent is the main Claude Code session. It does not understand project internals — it routes messages between agents and manages the BFS queue. All intelligence about specific nodes lives in zone managers and dev agents.

## State machine

```
IDLE → ANALYZE → WRITE TESTS → DEVELOP → RUN TESTS → COMMIT → IDLE
                                  ↑                       |
                                  └──── RETRY ←───────────┘ (on test fail, max 3)
                                                          |
                                                ESCALATE ←┘ (after 3 failures)
```

## Step: ANALYZE

1. Read `graph.json` to identify the target node and its zone
2. Spawn the zone manager subagent for that zone (dynamically generated agent file)
3. Pass: the user's task description + the zone overview + relevant contract overviews
4. Receive: a refined spec describing exactly what the dev agent must implement, which node to modify, and which contracts to implement
5. If the zone manager reports cross-zone impact: spawn the affected zone's manager next, pass the first manager's output as context, collect refined cross-zone spec
6. If the zone manager reports ambiguity that cannot be resolved: pause and ask the user

## Step: WRITE TESTS

1. Check if edge tests already exist for this node's contracts and are current
2. If tests are needed, spawn the test-writer subagent (defined in `agents/test-writer.md`)
3. Pass: the refined spec, node overview, and full contract definitions
4. The test-writer produces tests using four techniques: positive (equivalence partitioning), BVA, state transition, and error guessing (negative tests)
5. Receive: test files, test count summary, assumptions, coverage gaps
6. If assumptions need confirmation: present to user
7. Commit test files separately before development begins
8. These tests are invisible to the dev agent — this is a hard architectural constraint

## Step: DEVELOP

1. Spawn the dev agent subagent
2. Pass to the dev agent:
   - The refined spec from ANALYZE
   - The node's overview file content
   - The contract definitions (file contents from contracts/<id>/)
   - The shared module paths
   - Instruction: "You may only modify files under packages/<node-id>/. You may read contracts/ and shared/ but not modify them. Do not read or access the tests/ directory."
3. Receive: completion message with a summary of changes made, and a proposed overview update

## Step: RUN TESTS

1. Spawn the test agent subagent
2. Pass: the contract ID(s) to test, the test file paths from graph.json
3. The test agent runs the relevant edge tests
4. Receive: pass/fail results with details

## Step: COMMIT

On pass:
1. Stage all changes under the node's directory (the `path` from `graph.json`)
2. Commit with message: `[modular-dev] <node-id>: <one-line summary>`
3. Update the node's status in `graph.json` to `done`
4. Update the node's overview file with the dev agent's proposed update (after validation)
5. Return to IDLE or pick the next node in the BFS queue

On fail (retry ≤ 3):
1. Pass the test failure details back to the dev agent (new spawn) along with the original spec
2. The dev agent sees: spec + its own node + contracts + the failure message
3. Re-enter TEST

On fail (retry > 3 — ESCALATE):
1. Collect: the spec, the dev agent's changes, the test failures
2. Spawn the zone manager to review: is this a test problem, a spec problem, or a dev problem?
3. Zone manager returns diagnosis:
   - "test issue" → bus flags the test for user review
   - "spec issue" → bus asks user to clarify the requirement
   - "dev issue" → bus may prune the node (`git checkout -- <node-path>/` using the path from `graph.json`) and retry from scratch

## Zone manager generation

At session init or when `/modular-dev:plan` is invoked:

1. Bus reads `graph.json`
2. Groups nodes into zones by contract coupling (nodes sharing contracts → same zone)
3. For each zone, writes a temporary agent definition to `.claude/agents/_zone-<id>.md`:

```markdown
---
name: _zone-<id>
description: Zone manager for <zone-id>. Responsible for nodes: <node-list>. Invoke when analyzing or planning work that touches any of these nodes.
model: sonnet
---

You are a zone manager responsible for the following nodes:
<for each node: node-id, one-line description, status>

You know these contracts:
<for each contract touching this zone: contract-id, connects, one-line description>

Your job:
1. When given a task, determine which node(s) in your zone need modification
2. Read the relevant node overviews and contract overviews to understand current state
3. Produce a precise development spec for the dev agent
4. If the task requires changes outside your zone, report which zones are affected and what they need to do
5. Never make assumptions about implementation details you haven't read in overviews
6. If the spec is ambiguous, say so explicitly — do not guess
```

4. Agent files prefixed with `_` are transient — regenerated each session, not committed to git

## Message format between agents

All inter-agent communication goes through the bus as natural language in the subagent prompt/response. There is no structured protocol — the bus extracts information from the zone manager's response and reformulates it as the dev agent's prompt. The bus is a translator, not a passthrough.

## Hook-based state management

The bus maintains a state file at `.claude/modular-dev-state.json` that controls hook enforcement:

```json
{"role": "bus", "active_node": null}    // normal mode — no restrictions
{"role": "dev", "active_node": "auth"}  // dev mode — hooks enforce isolation
```

State transitions:
1. **SessionStart hook** → resets to bus mode
2. **Bus writes state** → sets dev mode with active_node before spawning dev agent
3. **PreToolUse hooks** → read state, block forbidden operations in dev mode
4. **PostToolUse Agent hook** → resets to bus mode after any subagent completes

The bus MUST write the state file before spawning a dev agent. The PostToolUse hook on Agent automatically resets state after the dev agent returns, so the bus doesn't need to manually reset.

The hooks provide hard enforcement — even if the dev agent's prompt-level isolation is ignored, the hooks will block forbidden tool calls with exit code 2.

## Escalation chain

```
dev agent → bus → zone manager → bus → user
                      ↑
                      └── other zone manager (if cross-zone)
```

Each level only escalates when it cannot resolve the issue with available information. The bus never makes technical decisions — it routes and asks.
