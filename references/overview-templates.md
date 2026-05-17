# Overview file templates

Overview files are the primary information source for manager and bus agents. They replace the need to read source code. Every overview must be accurate and current — the bus and zone managers make decisions based solely on these files.

## Project overview (overviews/project.md)

```markdown
# <Project Name>

## Purpose
<One paragraph describing what this project does>

## Architecture
<High-level description of how nodes are organized and interact>

## Zones
| Zone | Purpose | Nodes |
|------|---------|-------|
| <zone-id> | <description> | <node-1>, <node-2> |

## Shared modules
| Module | Purpose |
|--------|---------|
| <shared-id> | <description> |

## Key contracts
| Contract | Connects | Purpose |
|----------|----------|---------|
| <contract-id> | <node-a> ↔ <node-b> | <description> |
```

## Node overview (overviews/nodes/<node-id>.md)

```markdown
# Node: <node-id>

## Purpose
<What this node does, in one paragraph>

## Zone
<zone-id>

## Implements contracts
<List each contract this node provides an implementation for, with a brief note on what it implements>

## Depends on contracts
<List each contract this node consumes, with a brief note on what it uses>

## Exposed interface
<For each method/function/endpoint this node exposes through its contracts:>
- `methodName(params)` → `returnType` — <what it does>

## Internal structure
<Brief description of key internal components, without implementation details>

## Status
<pending | in-progress | done>

## Change log
- <date>: <what changed>
```

## Contract overview (overviews/contracts/<contract-id>.md)

```markdown
# Contract: <contract-id>

## Purpose
<What this interface boundary defines>

## Connects
<node-a> ↔ <node-b> [↔ <node-c> if multi-node]

## Interface definition
<For each method/type in the contract:>
- `methodName(params)` → `returnType` — <behavioral description>

## Behavioral constraints
<Any invariants, ordering guarantees, error handling expectations>

## Status
<draft | locked | tested>
```

## Zone overview (overviews/zones/<zone-id>.md)

```markdown
# Zone: <zone-id>

## Purpose
<What this group of nodes collectively handles>

## Nodes
| Node | Purpose | Status |
|------|---------|--------|
| <node-id> | <one-line> | <status> |

## Internal contracts
<Contracts where both endpoints are within this zone>

## External contracts
<Contracts where one endpoint is in this zone and the other is in a different zone>

## Dependencies on other zones
<Which other zones this zone depends on, via which contracts>
```

## Update rules

1. After a dev agent completes work on a node, it drafts an overview update
2. The bus validates the update against the contract type signatures and test results
3. If the overview claims a method exists that isn't in the contract, it's flagged as inconsistent
4. Only the bus writes to overview files; dev agents propose changes via their return message
