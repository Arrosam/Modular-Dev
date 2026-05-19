---
name: develop
description: Execute the next unit of development work from the BFS queue. Runs the full bus loop — analyze, write tests, develop, run tests, commit — for one node at a time. Tests are written BEFORE development starts, and the dev agent cannot see them. Use when the user says "develop", "build the next node", "start building", "continue development", "implement", or runs "/modular-dev:develop". This is the core execution skill of modular-dev.
---

# Execute one development unit

You are the bus agent executing one cycle of the develop loop. You process exactly ONE node from the work queue, then stop and report results.

## Prerequisites

1. Verify `graph.json` exists
2. Check for `.claude/modular-dev-queue.json` — if missing, tell the user to run `/modular-dev:plan <task>` first
3. Read the queue and find the first item with status `pending`
4. If no pending items exist, report "All work in the current plan is complete" and stop

## MANDATORY: Confirm before development

Before executing ANY phase beyond ANALYZE, you MUST present the user with:
1. **Which node** will be developed (node ID and description)
2. **What changes** will be made (the refined spec summary)

Then ask: "Proceed with development of this node?"

Do NOT write tests, spawn dev agents, or modify any files until the user explicitly approves. This is a hard requirement with no exceptions.

## Phase: ANALYZE

Read the work queue item to get the `node_id`, `zone_id`, and `spec`.

If zone manager agent files are missing, regenerate them (see `/modular-dev:plan` step 2 — read `references/bus-protocol.md` for the template).

Spawn the zone manager subagent to validate and refine the spec:

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

## Phase: WRITE TESTS

Before any implementation begins, write comprehensive edge tests based on the contract definitions and the refined spec. This ensures the dev agent is measured against tests it has never seen.

Check whether tests already exist for this node's contracts (look at the test paths in `graph.json`). If tests exist and the contract has not changed since they were written, skip this phase. If tests are missing or the contract was modified, proceed.

Spawn the test-writer agent subagent (defined in `agents/test-writer.md` in the plugin directory):

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

The test-writer returns:
- Test file paths
- Test count summary per method per technique
- Assumptions it made (may need user confirmation)
- Coverage gaps (parts of the spec too vague to test)

### Handle test-writer output

1. If the test-writer reports assumptions: present them to the user for confirmation. If the user disagrees, have the test-writer revise.
2. If the test-writer reports coverage gaps: present them to the user. The user may clarify the spec (re-enter ANALYZE) or accept the gap.
3. Once confirmed, update `graph.json`: set the contract status to `tested` and record the test file path.
4. Commit the test files: `git add tests/ && git commit -m "[modular-dev] tests: edge tests for <node-id> contracts"`

The tests are now written and committed. The dev agent in the next phase will NOT be given access to these files.

## Phase: DEVELOP

Before spawning the dev agent, read the node's `path` field from `graph.json` to determine its actual directory (e.g. `krakey/engines/recall`, not necessarily `packages/<node-id>`). Then write the isolation state file so that hooks can enforce boundaries at the tool level:

```bash
echo '{"role":"dev","active_node":"<node-id>"}' > .claude/modular-dev-state.json
```

This activates three PreToolUse hooks that will automatically block the dev agent from:
- Writing files outside the node's directory (resolved from `graph.json`)
- Reading `tests/` or other nodes' directories
- Running git commands or accessing tests via bash

These hooks fire on every tool call the dev agent makes, providing hard enforcement on top of the prompt-level isolation directive.

Spawn the dev agent subagent (defined in `agents/developer.md` in the plugin directory). Construct the prompt by assembling:

1. The refined spec from ANALYZE
2. The node overview content
3. The contract definition files (read from `contracts/<id>/`)
4. Information about available shared modules

The dev agent prompt must include this isolation directive, using the node's actual `path` from `graph.json`:
"You may ONLY create and modify files under `<node-path>/`. You may READ files in `contracts/` and `shared/` but must NOT modify them. You must NOT read or access the `tests/` directory. If you find that the contract interface is insufficient for your implementation, STOP and report what's missing — do not modify contracts yourself. You may ONLY import interfaces already declared in your contracts (`implements_contracts` and `depends_on_contracts`). Do NOT add new hard imports or dependencies — if you need new functionality, STOP and report what you need so the dependency can be evaluated."

The dev agent returns:
- A summary of what it implemented
- A proposed overview update (what methods are now exposed, what the node does)
- Any escalation (contract insufficient, spec ambiguous, etc.)

### Handle dev agent escalation

If the dev agent reports it cannot complete the work:
- "contract insufficient": escalate to zone manager for diagnosis, then to user if needed
- "spec ambiguous": present the ambiguity to the user
- "cannot implement within scope": the node may need splitting — present to user
- "needs new dependency": the dev agent requires functionality not available through existing contracts or shared modules. Escalate to zone manager to evaluate whether a new contract dependency should be added. Present the zone manager's recommendation to the user for approval. Do NOT re-spawn the dev agent until the dependency is resolved (contract added/updated and locked).

## Phase: RUN TESTS

Spawn the test agent subagent (defined in `agents/tester.md` in the plugin directory).

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

**All pass**: proceed to COMMIT.

**Failures (attempt ≤ 3)**:

Increment the retry counter. Spawn a new dev agent with:

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

Fix the implementation to pass these tests. Same isolation rules apply — only modify files under <node-path>/ (the node's path from graph.json).
```

Then re-enter TEST.

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

Present the zone manager's diagnosis to the user with options:
- "Retry from scratch" → revert node (`git checkout -- <node-path>/`), re-enter DEVELOP
- "Flag test for review" → mark the test as needing user attention, skip this node
- "Revise spec" → re-enter ANALYZE with user's revised requirements

## Phase: COMMIT

Each completed node is one logical unit — one commit. Do not split a node's changes across multiple commits, and do not bundle multiple nodes into one commit.

1. Stage changes: `git add <node-path>/` (using the node's `path` from `graph.json`)
2. Commit with a concise message describing the logical unit of work:
   `git commit -m "[modular-dev] <node-id>: <one-line summary from dev agent>" --no-verify`
   - Do NOT include `Co-authored-by` lines in commit messages. A PostToolUse hook automatically strips them if they appear.
3. Update `graph.json`: set node status to `done`
4. Validate and apply the dev agent's proposed overview update:
   - Read the contract type signatures
   - Check that every method claimed in the overview exists in the contracts
   - Write the updated overview to `overviews/nodes/<node-id>.md`
5. Stage and commit meta changes as a separate logical unit:
   `git add graph.json overviews/`
   `git commit -m "[modular-dev] meta: update graph and overview for <node-id>"`
6. Update the work queue: set this item's status to `done`
7. Report to user:

```
✓ Completed: <node-id>
  Summary: <what was implemented>
  Tests: <N> passed
  Commit: <short hash>

  Next in queue: <next-node-id> (<one-line spec>)
  Run /modular-dev:develop to continue, or /modular-dev:status for full progress.
```
