# Bus agent protocol

The bus agent is the main Claude Code session. It does not understand project internals — it routes messages between agents and manages the BFS queue. All intelligence about specific nodes lives in zone managers and dev agents.

## State machine

Each cycle processes one **wave** — a set of independent nodes (contracts locked, dependencies done) built concurrently, each in its own git worktree. WRITE TESTS and DEVELOP fan out across the wave; a barrier between them ensures all tests are committed before any development starts. Each node is then **tested in its own worktree before being merged back** — the fault-isolation gate — so broken code never reaches the main tree and a failure points at one node. Only passing nodes are harvested; COMMIT is sequential (one node per commit).

```
IDLE → SELECT WAVE → ANALYZE → WRITE TESTS ──┐ (parallel per node)
                                              │
                                          [BARRIER: all tests committed]
                                              │
                                              ▼
                        ┌──────────────── DEVELOP (parallel, one worktree per node)
                        │                     │
                        │                     ▼
              RETRY (per node, in     VERIFY IN WORKTREE (per node, before merge)
              its worktree; max 3, ←───── │ (per-node pass gate)
              else ESCALATE)              ▼
                                       HARVEST passing nodes → main tree
                                              │
                                              ▼
                                       RUN TESTS (merged-tree confirmation)
                                              │
                                              ▼
                                       COMMIT (sequential) → next wave / IDLE
```

## Step: ANALYZE

1. Read `graph.json` to identify the target node and its zone
2. Spawn the zone manager subagent for that zone (dynamically generated agent file)
3. Pass: the user's task description + the zone overview + relevant contract overviews
4. Receive: a refined spec describing exactly what the dev agent must implement, which node to modify, and which contracts to implement
5. If the zone manager reports cross-zone impact: spawn the affected zone's manager next, pass the first manager's output as context, collect refined cross-zone spec
6. If the zone manager reports ambiguity that cannot be resolved: pause and ask the user

## Step: WRITE TESTS (parallel across a wave)

1. For each node in the wave, check if edge tests already exist for its contracts and are current
2. Spawn one test-writer subagent per node that needs tests, in parallel (test-writers don't modify code and aren't write-isolated, so they're safe to run concurrently); defined in `agents/test-writer.md`
3. Pass each: the refined spec, node overview, and full contract definitions
4. The test-writer produces tests using four techniques: positive (equivalence partitioning), BVA, state transition, and error guessing (negative tests)
5. Receive from each: test files, test count summary, assumptions, coverage gaps
6. If assumptions need confirmation: present to user
7. BARRIER: wait for every node's tests to be written, then commit them (one node per commit, sequentially) before any development begins
8. These tests are invisible to the dev agents — this is a hard architectural constraint

## Step: DEVELOP (parallel across a wave, one git worktree per node)

A "wave" is a set of nodes whose contracts are already locked/tested and whose node dependencies are `done` — they are independent at development time (dev agents code only against locked contract interfaces, never other nodes' code) and can be built concurrently.

Each dev agent runs in its **own sparse git worktree** under `.mdwt/<node-id>/`, checked out with only the node directory plus read-only `contracts/` and `shared/` (no sibling packages, no `tests/`). This is the primary isolation — physical, not just advisory. The active-path hooks remain as a second layer.

1. For each node, create a sparse worktree:
   - `git worktree add --no-checkout --detach .mdwt/<node-id> HEAD`
   - `git -C .mdwt/<node-id> sparse-checkout set --cone <node-path> contracts shared`
   - `git -C .mdwt/<node-id> checkout`
2. Spawn one dev agent subagent per node in the wave, in parallel (one Agent call per node in a single message). Pass to each:
   - The instruction to work inside its worktree `.mdwt/<node-id>/`
   - The refined spec from ANALYZE
   - The node's overview file content
   - The contract definitions (file contents from contracts/<id>/)
   - The shared module paths
   - Instruction (verbatim, with that node's actual `path` from `graph.json` in backticks): "You may ONLY create and modify files under `<node-path>/`. You may read contracts/ and shared/ but not modify them. Do not read or access the tests/ directory." The isolation hook reads the node path from between the backticks and adds it to the session's active-path set.
3. Receive from each: completion message with a summary of changes made, and a proposed overview update
4. BARRIER: wait for all agents to return (git is blocked while any dev agent is active).
5. VERIFY EACH NODE IN ITS WORKTREE, before merging back — this is the fault-isolation gate. For each node, reveal its tests in the worktree (the agent is gone), run the node's edge tests there, then act on the result:
   - `git -C .mdwt/<node-id> sparse-checkout add tests`
   - Spawn the test agent rooted in `.mdwt/<node-id>/`; it runs only this node's edge tests
   - **Pass** → strip tests back out and harvest (step 6)
   - **Fail (≤3)** → strip tests (`git -C .mdwt/<node-id> sparse-checkout set --cone <node-path> contracts shared`), re-spawn a dev agent IN THE SAME WORKTREE with the failures, re-reveal tests, re-run. The fault is contained to this node; its broken code never enters the main tree.
   - **Fail (>3)** → ESCALATE; leave the worktree in place, do NOT harvest.
6. HARVEST passing nodes only: strip tests, merge into the main tree, tear down the worktree:
   - `git -C .mdwt/<node-id> sparse-checkout set --cone <node-path> contracts shared`
   - `git -C .mdwt/<node-id> add -A -- <node-path>`
   - `git -C .mdwt/<node-id> diff --cached --binary -- <node-path> > .mdwt/<node-id>.patch`
   - `git apply --binary --whitespace=nowarn .mdwt/<node-id>.patch`
   - `git worktree remove --force .mdwt/<node-id>` (then delete the patch file)

## Step: RUN TESTS

Tests run twice, both with the read-only test agent:
1. **Primary gate — in each node's worktree, before merge** (DEVELOP step 5). A failure here pinpoints one node and keeps its broken code out of the main tree. The retry loop lives here.
2. **Confirmation — in the merged tree, after harvesting**. Spawn one test agent per harvested node, in parallel. A node that passed in isolation but fails here reveals an integration effect of merging, not a node-implementation bug — report it as such.

## Step: COMMIT (sequential, one node at a time)

Commit each passing node separately, even though the wave developed in parallel:
1. Stage the node's paths (`git add -- <node-path>/`, so newly created files are included) then commit scoped to that pathspec — `git commit --only -- <node-path>/` (the `path` from `graph.json`) — so only the node's files enter the commit even though sibling nodes' changes sit unstaged in the working tree (or another session shares the repo). Message: `[modular-dev] <node-id>: <one-line summary>`
2. Verify with `git show --name-only --format= HEAD` that every committed path is under `<node-path>/`; if not, the commit is contaminated — stop and correct it
3. Update the node's status in `graph.json` to `done`
4. Update the node's overview file with the dev agent's proposed update (after validation)
5. Repeat for each passing node in the wave, then pick the next wave from the BFS queue (or return to IDLE)

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

Isolation state is owned entirely by the hooks and is **per session**. Because a session may run several dev agents at once (a wave), the state is a **set of active node paths**, not a single cell. It is stored as a directory of marker files — one file per concurrently-active dev agent:

```
.claude/modular-dev-state/<session_id>/paths/<sanitized-path>.path   // each file's content = one active node path
```

- **Empty / no directory** → bus mode, no restrictions.
- **One or more marker files** → dev mode; a write/read is allowed if it falls under ANY active node path.

Using one file per path (rather than a shared JSON array) means concurrent PreToolUse/PostToolUse hooks for different dev agents touch different filenames and never race on a read-modify-write. Keying by `session_id` (read from the hook payload on stdin) means concurrent bus sessions on the same repo each have their own state directory and cannot clobber or block one another.

State transitions:
1. **SessionStart hook** → ensures the state root exists, retires legacy single-cell state (`.claude/modular-dev-state.json` and per-session `*.json`), prunes stale `*.path` markers and empty session dirs
2. **PreToolUse Agent hook** → on a dev-agent spawn (detected by the isolation directive), extracts that node's path and ADDS a marker to this session's active set
3. **PreToolUse Write/Read/Bash hooks** → read this session's active set; in dev mode, block writes/reads outside every active path, block reads of `tests/` and other nodes, block git
4. **PostToolUse Agent hook** → removes only the finishing agent's path from the set (recovered from the completed Agent call's directive); when the set empties, the session returns to bus mode

The bus does NOT write state itself — it only includes the canonical isolation directive (with the node path in backticks) in each dev-agent prompt. The hooks do the rest.

The hooks provide hard enforcement — even if a dev agent's prompt-level isolation is ignored, the hooks block forbidden tool calls with exit code 2. They **fail open**: if a hook cannot identify the session (or, in PostToolUse, cannot tell which of several concurrent agents finished), it errs toward allowing / leaving state intact rather than wedging, so a misidentified session degrades to prompt-level isolation only.

## Escalation chain

```
dev agent → bus → zone manager → bus → user
                      ↑
                      └── other zone manager (if cross-zone)
```

Each level only escalates when it cannot resolve the issue with available information. The bus never makes technical decisions — it routes and asks.
