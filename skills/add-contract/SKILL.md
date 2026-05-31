---
name: add-contract
description: Add or modify a contract (interface) between nodes. Handles the full lifecycle — define the interface, update graph.json, write edge tests, snapshot affected nodes if modifying an existing contract. Use when the user says "add contract", "new interface", "connect these nodes", "modify contract", "change interface", or "/modular-dev:add-contract".
---

# Add or modify a contract

## Determine mode

- **New contract**: no existing contract with this ID in `graph.json`
- **Modify existing contract**: contract already exists — this is a breaking change

## New contract

### Step 1: Define the contract

With the user, define:
1. Contract ID (slug)
2. Which nodes it connects
3. Interface: methods/functions, inputs, outputs, behavioral constraints

### Step 2: Create files

1. Create `contracts/<contract-id>/` with the definition file
2. Create `overviews/contracts/<contract-id>.md` using the template from `references/overview-templates.md`
3. Add contract entry to `graph.json` with status `locked`
4. Update `graph.json` node entries to reference the new contract in `depends_on_contracts` or `implements_contracts`

### Step 3: Write edge tests

Spawn the zone manager for the relevant zone to write edge tests for this contract:

```
Write comprehensive edge tests for contract: <contract-id>

Contract definition:
<contract content>

Connected nodes:
<node-id-a> (implements), <node-id-b> (depends on)

Write tests covering:
1. Positive tests: each method with valid inputs, verify correct outputs
2. Boundary value analysis: edge cases for each parameter
3. Error handling: invalid inputs, expected error responses
4. State transitions: if any methods are non-idempotent, test state changes

Save tests to: tests/<contract-id>.test.<ext>
```

Set contract status to `tested` in `graph.json`.

### Step 4: Commit

Scope the commit to the contract's own artifacts so a concurrent session's changes can't be folded in. Stage first (so newly created files are included), then commit only that pathspec:

```
git add -- graph.json contracts/<contract-id>/ overviews/contracts/<contract-id>.md tests/<contract-id>.test.* && git commit --only --no-verify -m "[modular-dev] add-contract: <contract-id> connecting <node-a> ↔ <node-b>" -- graph.json contracts/<contract-id>/ overviews/contracts/<contract-id>.md tests/<contract-id>.test.*
```

Then verify with `git show --name-only --format= HEAD` that only those paths were committed.

## Modify existing contract (breaking change)

This is Case B from the architecture — interface modification affecting multiple nodes.

### Step 1: Impact analysis

Read `graph.json` to find all nodes that depend on or implement this contract.

Present to user:
```
Modifying contract: <contract-id>
Affected nodes: <node-a>, <node-b>, ...

This will require re-testing all affected nodes.
Nodes with status "done" may need re-development.

Proceed?
```

### Step 2: Snapshot

For each affected node with status `done`:
```bash
git tag modular-dev/snapshot/<node-id>/<timestamp>
```

### Step 3: Update contract

1. Apply the user's requested changes to the contract definition
2. Update the contract overview
3. Update edge tests to match the new interface

### Step 4: Re-test affected nodes

For each affected node:
1. Spawn the test agent to run the updated edge tests
2. If tests pass → node is still compatible, no action needed
3. If tests fail → set node status to `pending` in `graph.json` and add to the work queue

### Step 5: Commit and report

Scope the commit to the contract's own artifacts. Stage first (so newly created files are included), then commit only that pathspec:

```
git add -- graph.json contracts/<contract-id>/ overviews/contracts/<contract-id>.md tests/<contract-id>.test.* && git commit --only --no-verify -m "[modular-dev] modify-contract: <contract-id> — <summary of change>" -- graph.json contracts/<contract-id>/ overviews/contracts/<contract-id>.md tests/<contract-id>.test.*
```

Then verify with `git show --name-only --format= HEAD` that only those paths were committed.

Report which nodes need re-development and suggest running `/modular-dev:plan` to re-plan.
