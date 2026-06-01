---
name: develop
description: Execute the next wave of development work from the BFS queue. Runs the full bus loop — analyze, write tests, develop, run tests, commit. Independent nodes in a wave are processed in parallel: tests are written concurrently, and once ALL tests are committed, development starts concurrently. Tests are written BEFORE development and the dev agent cannot see them. Use when the user says "develop", "build the next node", "start building", "continue development", "implement", or runs "/modular-dev:develop". This is the core execution skill of modular-dev.
---

# Execute a development wave

You are the bus agent executing one cycle of the develop loop. You process one **wave** of work — a set of independent nodes that can be built concurrently — then stop and report results.

## Why nodes can run in parallel

In modular-dev, a dev agent implements a node strictly against **locked contract interfaces** — it never reads or imports another node's code. So any nodes whose contracts are already `locked`/`tested` are independent at development time and safe to build at the same time. Parallelism is bounded by contract readiness, NOT by BFS node ordering. Commits remain sequential and pathspec-scoped (one node = one commit, `git commit --only -- <node-path>/`), so the bus committing node A never sweeps in node B's in-flight changes.

A **wave** is one or more such independent nodes processed together. A single-node wave is just the degenerate case — the loop is identical.

## Prerequisites

1. Verify `graph.json` exists
2. Check for queue files matching `.claude/modular-dev-queue-*.json` (also check legacy `.claude/modular-dev-queue.json`). If none exist, tell the user to run `/modular-dev:plan <task>` first.
3. If multiple queue files have pending items, list them (showing task description and pending count) and ask the user which one to continue. If only one has pending items, use it automatically.
4. Read the selected queue and find all items with status `pending`
5. If no pending items exist, report "All work in the current plan is complete" and stop

### Select the wave

From the pending items, select the set of nodes whose contract dependencies are all satisfied (their contracts are `locked` or `tested`, and any node they depend on is already `done`). These nodes form this wave and will be processed in parallel. Nodes still waiting on an unbuilt dependency stay queued for a later wave.

If you are unsure whether two nodes are truly independent (e.g. they share a contract that is still being shaped), be conservative and place them in separate waves. When in doubt, a single-node wave is always safe.

## MANDATORY: Confirm before development

Before executing ANY phase beyond ANALYZE, you MUST present the user with:
1. **Which nodes** will be developed in this wave (node IDs and descriptions)
2. **What changes** will be made to each (the refined spec summary)

Then ask: "Proceed with development of this wave?"

Do NOT write tests, spawn dev agents, or modify any files until the user explicitly approves. This is a hard requirement with no exceptions.

## Phase: ANALYZE

For each node in the wave, read its queue item to get the `node_id`, `zone_id`, and `spec`.

If zone manager agent files are missing, regenerate them (see `/modular-dev:plan` step 2 — read `references/bus-protocol.md` for the template).

Validate and refine each node's spec. When the wave spans multiple zones, you MAY spawn the relevant zone managers in parallel (one Agent call per zone manager in a single message) since validation is read-only. Spawn the zone manager subagent with:

```
You are validating a development spec before handing it to a dev agent.

Node to modify: <node_id>
Planned spec: <spec from queue>

Current node overview:
<content of overviews/nodes/<node-id>.md>

Contracts this node implements:
<content of each contract overview>

Contracts this node depends on:
<content of each contract overview>

Validate:
1. Is this spec still accurate given the current state of overviews?
2. Is the spec precise enough for a dev agent to implement without guessing?
3. Are there any contract changes required that weren't planned?

Respond with the final, refined spec or report issues.
```

If the zone manager reports issues, pause and present them to the user.

## Phase: WRITE TESTS (parallel across the wave)

Before any implementation begins, write comprehensive edge tests for EVERY node in the wave. This ensures each dev agent is measured against tests it has never seen.

Test-writers do not modify code and are not write-isolated, so they are safe to run concurrently. **Spawn one test-writer per node in the wave in parallel** — issue all the Agent tool calls in a single message so they run at the same time. For each node, first check whether tests already exist for its contracts (look at the test paths in `graph.json`); skip nodes whose tests exist and whose contracts haven't changed.

Use this prompt for each test-writer (defined in `agents/test-writer.md` in the plugin directory):

```
Write edge tests for the following contracts as they relate to node <node-id>.

Development spec:
<the refined spec from ANALYZE>

Node overview:
<content of overviews/nodes/<node-id>.md>

Contracts this node implements:
<for each contract: contract-id, full contract definition file content>

Contracts this node depends on:
<for each contract: contract-id, full contract definition file content>

Write test files to:
<test path from graph.json for each contract, e.g. tests/<contract-id>.test.*>

Apply all four testing techniques systematically:
1. Positive tests with equivalence partitioning
2. Boundary value analysis for every parameter
3. State transition tests for non-idempotent operations
4. Negative tests via error guessing

You are writing tests BEFORE the implementation exists. Test against the contract interface only — do NOT assume any implementation details.
```

Each test-writer returns:
- Test file paths
- Test count summary per method per technique
- Assumptions it made (may need user confirmation)
- Coverage gaps (parts of the spec too vague to test)

### Handle test-writer output (barrier)

Wait for ALL test-writers in the wave to return before proceeding — development must not start until every node's tests are committed.

For each node's result:
1. If the test-writer reports assumptions: present them to the user for confirmation. If the user disagrees, have the test-writer revise.
2. If the test-writer reports coverage gaps: present them to the user. The user may clarify the spec (re-enter ANALYZE) or accept the gap.
3. Once confirmed, update `graph.json`: set the contract status to `tested` and record the test file path.
4. Stage and commit the test files, scoped to `tests/` so only test files are captured (stage first so newly created test files are included; `--only` ignores anything else staged):
   `git add -- tests/ && git commit --only --no-verify -m "[modular-dev] tests: edge tests for <node-id> contracts" -- tests/`

Commit test files one node at a time (commits are sequential even though the writing was parallel). The dev agents in the next phase will NOT be given access to these files.

Only once EVERY node in the wave has its tests written and committed do you move to DEVELOP.

## Phase: DEVELOP (parallel across the wave, one git worktree per node)

All test files for the wave are committed, so now development for every node in the wave starts together. Each dev agent runs in its **own git worktree** — a checkout containing ONLY the files it needs (its node directory, plus read-only `contracts/` and `shared/`). This is the primary isolation: an agent physically cannot see sibling packages or the `tests/` directory because they aren't in its worktree. The active-path hooks still fire as a second layer of defense.

For each node, read its `path` field from `graph.json` to determine its actual directory (e.g. `krakey/engines/recall`, not necessarily `packages/<node-id>`).

### Step 1 — Create one worktree per node

Ensure `.mdwt/` is git-ignored (the setup skill adds it; if missing, append `.mdwt/` to `.gitignore` and commit that first). Then, for each node in the wave, create a sparse worktree that checks out only the node path plus `contracts/` and `shared/`:

```bash
git worktree add --no-checkout --detach .mdwt/<node-id> HEAD
git -C .mdwt/<node-id> sparse-checkout set --cone <node-path> contracts shared
git -C .mdwt/<node-id> checkout
```

The worktree shares the repo's object store but has its own index and working directory, so concurrent agents never collide. (Cone mode also includes top-level files such as `graph.json` and `README.md`; that is harmless — they are not sibling packages or tests.)

### Step 2 — Spawn all dev agents in parallel, each rooted in its worktree

**Spawn all dev agents for the wave in parallel** — issue one Agent tool call per node in a single message. Each dev agent's prompt MUST instruct it to work inside its worktree directory `.mdwt/<node-id>/` and include the canonical isolation directive verbatim, with that node's actual path wrapped in backticks. The backtick path is still required: the active-path hooks read it and add it to this session's active set (`.claude/modular-dev-state/<session-id>/paths/`) as defense-in-depth, and a matching PostToolUse hook removes it when the agent returns.

Spawn the dev agent subagent (defined in `agents/developer.md` in the plugin directory). For each node, construct the prompt by assembling:

1. The instruction: "Work entirely inside the directory `.mdwt/<node-id>/`. This is your worktree — treat its root as the project root."
2. The refined spec from ANALYZE
3. The node overview content
4. The contract definition files (read from `contracts/<id>/`)
5. Information about available shared modules

Each dev agent prompt must include this isolation directive, using that node's actual `path` from `graph.json`:
"You may ONLY create and modify files under `<node-path>/`. You may READ files in `contracts/` and `shared/` but must NOT modify them. You must NOT read or access the `tests/` directory. If you find that the contract interface is insufficient for your implementation, STOP and report what's missing — do not modify contracts yourself. You may ONLY import interfaces already declared in your contracts (`implements_contracts` and `depends_on_contracts`). Do NOT add new hard imports or dependencies — if you need new functionality, STOP and report what you need so the dependency can be evaluated."

Each dev agent returns:
- A summary of what it implemented
- A proposed overview update (what methods are now exposed, what the node does)
- Any escalation (contract insufficient, spec ambiguous, etc.)

### Step 3 — Verify each node IN ITS WORKTREE, before merging back (barrier)

Wait for ALL dev agents to return. (You cannot run git while any dev agent is active — the active-path hooks block git until the set empties — so this step happens after every agent has finished.)

Each node is tested **inside its own worktree first**, while still quarantined from the main tree. This is the key to fault isolation: if a node's edge tests fail, the failure points at exactly that node, and its broken code never touches your local working tree or the other nodes. Only nodes that pass their tests in isolation are merged back.

The dev agent never saw `tests/` (it wasn't in the worktree). Now that the agent has returned, add the test files to that node's worktree, run the node's edge tests there, then remove the tests again so they can't leak into a retry:

For each node, in its worktree `.mdwt/<node-id>/`:

1. Reveal the node's tests in the worktree (the agent is gone, so this is safe):
   `git -C .mdwt/<node-id> sparse-checkout add tests`
2. Spawn the test agent (`agents/tester.md`) **rooted in `.mdwt/<node-id>/`** to run this node's edge tests against the just-written implementation. Pass it the node's contract IDs and test file paths (from `graph.json`). Test agents are read-only and per-node, so run them for all wave nodes in parallel.
3. Evaluate that node's result:
   - **Pass** → the node is verified in isolation. Strip tests back out and harvest it into the main tree (Step 4).
   - **Fail (attempt ≤ 3)** → the fault is isolated to THIS node. Strip the tests back out so the retry dev agent can't see them (`git -C .mdwt/<node-id> sparse-checkout set --cone <node-path> contracts shared`), then re-spawn a dev agent **in the same worktree** with the failure details (see RUN TESTS → Failures). Re-reveal tests and re-run. Other nodes are unaffected.
   - **Fail (attempt > 3)** → ESCALATE for this node (see RUN TESTS → ESCALATE). Do NOT harvest it; leave its worktree in place for diagnosis.

### Step 4 — Harvest each PASSING node into the main working tree

Only after a node has passed its edge tests in its worktree, strip the tests back out and merge its implementation into the main tree, scoped to the node path, then remove the worktree:

```bash
git -C .mdwt/<node-id> sparse-checkout set --cone <node-path> contracts shared   # drop tests/ before harvesting
git -C .mdwt/<node-id> add -A -- <node-path>
git -C .mdwt/<node-id> diff --cached --binary -- <node-path> > .mdwt/<node-id>.patch
git apply --binary --whitespace=nowarn .mdwt/<node-id>.patch     # apply into the main tree
git worktree remove --force .mdwt/<node-id>
rm -f .mdwt/<node-id>.patch
```

If a node's patch is empty, the dev agent made no changes — investigate before continuing. After harvesting, the main working tree holds each verified node's changes (unstaged), ready for the pathspec-scoped COMMIT. Because every harvested node already passed its tests in isolation, the post-merge RUN TESTS phase is a confirmation that the merged tree still passes — not the first time failures are discovered.

Collect all dev agents' results, then proceed to COMMIT for each verified node (re-running tests in the merged tree first as a final confirmation — see RUN TESTS).

### Handle dev agent escalation

If the dev agent reports it cannot complete the work:
- "contract insufficient": escalate to zone manager for diagnosis, then to user if needed
- "spec ambiguous": present the ambiguity to the user
- "cannot implement within scope": the node may need splitting — present to user
- "needs new dependency": the dev agent requires functionality not available through existing contracts or shared modules. Escalate to zone manager to evaluate whether a new contract dependency should be added. Present the zone manager's recommendation to the user for approval. Do NOT re-spawn the dev agent until the dependency is resolved (contract added/updated and locked).

## Phase: RUN TESTS

Tests run at TWO points, both using the read-only test agent (`agents/tester.md`):

1. **In-worktree, per node, BEFORE merge** (DEVELOP Step 3) — the primary gate. Each node is tested in isolation so a failure pinpoints that node and broken code never reaches the main tree. This is where the retry loop below lives.
2. **In the merged tree, AFTER harvesting** — a confirmation pass that the verified nodes still pass once combined. Spawn one test agent per harvested node (in parallel; they're read-only). If a node that passed in isolation fails here, the cause is an integration effect of merging — report it explicitly rather than blaming the node's implementation.

Use this prompt for each test agent (rooted in the worktree for gate #1, or the main tree for gate #2):

```
Run edge tests for node: <node-id>

Contracts to test:
<for each contract this node implements or depends on>
  - contract: <contract-id>
  - test file: <test path from graph.json>

Run each test file. Report:
1. Total tests, passed, failed
2. For each failure: test name, expected vs actual, relevant error
```

### Handle test results

Evaluate each node's results independently. A node whose tests pass in its worktree is harvested (DEVELOP Step 4) and proceeds to COMMIT; a node with failures enters its own retry loop below — in its worktree — without blocking the others.

**All pass**: harvest the node (DEVELOP Step 4), then proceed to COMMIT.

**Failures (attempt ≤ 3)**:

Increment that node's retry counter. The node is still in its worktree, unharvested, so the fault is fully contained. First strip the tests back out of the worktree so the retry agent can't see them:
`git -C .mdwt/<node-id> sparse-checkout set --cone <node-path> contracts shared`
Then spawn a new dev agent **in that same worktree** with:

```
Your previous implementation of <node-id> failed some edge tests.

Test failures:
<failure details from test agent>

Original spec:
<the refined spec>

Current node overview:
<overview content>

Contract definitions:
<contract contents>

Fix the implementation to pass these tests. Work entirely inside the directory `.mdwt/<node-id>/`. Same isolation rules apply: You may ONLY create and modify files under `<node-path>/` (the node's path from graph.json).
```

The retry dev agent works in the node's existing worktree, where its previous (failing) implementation still lives — so it fixes in place, still quarantined from the main tree and from `tests/`. The backtick-wrapped path is required: the isolation hook reads the node path from between the backticks to scope this retried dev agent.

After the retry agent returns, re-reveal the tests (`git -C .mdwt/<node-id> sparse-checkout add tests`) and re-run the test agent in the worktree (DEVELOP Step 3).

**Failures (attempt > 3)**: ESCALATE.

Spawn the zone manager:

```
The dev agent has failed 3 times to pass edge tests for node <node-id>.

Spec: <spec>
Test failures: <latest failure details>
Dev agent's last changes summary: <summary>

Diagnose:
1. Is this a test case problem (test expectations wrong)?
2. Is this a spec problem (spec doesn't match what tests expect)?
3. Is this a dev problem (implementation approach is wrong)?

Report your diagnosis.
```

The failing node is still in its worktree, never harvested — so the main tree is clean and nothing needs reverting there. Present the zone manager's diagnosis to the user with options:
- "Retry from scratch" → reset the node's worktree to a clean checkout (`git -C .mdwt/<node-id> checkout -- <node-path>/` to discard the failed implementation), re-enter DEVELOP for that node
- "Flag test for review" → mark the test as needing user attention; remove the worktree (`git worktree remove --force .mdwt/<node-id>`) and skip this node — its code is NOT merged
- "Revise spec" → re-enter ANALYZE with user's revised requirements (keep or reset the worktree as appropriate)

## Phase: COMMIT (sequential, one node at a time)

Even though the wave was developed in parallel, commit each node separately and sequentially — one node is one logical unit, one commit. Do not split a node's changes across multiple commits, and do not bundle multiple nodes into one commit. Process the wave's passing nodes one at a time through the steps below.

Always scope commits to an explicit pathspec: stage the node's paths with `git add -- <paths>` (so newly created files are included — `--only` alone will NOT pick up untracked files), then commit that same pathspec with `git commit --only -- <paths>`. The `--only` flag captures ONLY the named paths, ignoring anything else that happens to be staged — so even with sibling nodes' changes sitting unstaged in the working tree (or another bus session sharing the repo), this commit contains only this node's files.

1. Stage and commit the node's implementation, scoped to its directory (the node's `path` from `graph.json`). Stage first so new files are included, then commit only that pathspec:
   `git add -- <node-path>/ && git commit --only --no-verify -m "[modular-dev] <node-id>: <one-line summary from dev agent>" -- <node-path>/`
   - Do NOT include `Co-authored-by` lines in commit messages. A PostToolUse hook automatically strips them if they appear.
   - If git reports "nothing to commit" for that path, the dev agent made no changes — investigate before continuing rather than committing unrelated files.
2. VERIFY the commit captured only the intended files:
   `git show --name-only --format= HEAD`
   Every path listed MUST be under `<node-path>/`. If any file outside that pathspec appears, STOP and report it — the commit is contaminated. Correct it (e.g. `git reset --soft HEAD^`, then re-commit with the correct `--only -- <node-path>/` pathspec) before continuing.
3. Update `graph.json`: set node status to `done`
4. Validate and apply the dev agent's proposed overview update:
   - Read the contract type signatures
   - Check that every method claimed in the overview exists in the contracts
   - Write the updated overview to `overviews/nodes/<node-id>.md`
5. Stage and commit meta changes as a separate logical unit, also pathspec-scoped (stage first so new overview files are included):
   `git add -- graph.json overviews/ && git commit --only --no-verify -m "[modular-dev] meta: update graph and overview for <node-id>" -- graph.json overviews/`
6. Update the work queue: set this item's status to `done`

After committing every node in the wave, report the wave to the user:

```
✓ Completed wave (<N> nodes):
  - <node-id-1>: <what was implemented> — <M> tests passed — commit <short hash>
  - <node-id-2>: <what was implemented> — <M> tests passed — commit <short hash>

  Remaining in queue: <count> nodes (<next ready node(s)>)
  Run /modular-dev:develop to build the next wave, or /modular-dev:status for full progress.
```

If a node could not be completed (escalation or exhausted retries), report it explicitly alongside the completed ones rather than silently dropping it.
