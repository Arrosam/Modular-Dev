# modular-dev

**A Claude Code plugin that tames complex projects by breaking them into small, agent-manageable pieces.**

AI coding agents are powerful on small, focused tasks — but they fall apart on large codebases. Context windows overflow, changes ripple unpredictably, and one bad edit in module A breaks modules B through Z. **modular-dev** solves this by decomposing your project into independent packages that agents develop in isolation, with contract-driven testing. Independent packages are built concurrently — in waves — while each agent stays confined to its own package.

---

## How it works

```
You: "Add user authentication with OAuth support"

modular-dev:
  1. Reads the project dependency graph
  2. Routes to the relevant zone manager → analyzes which packages need changes
  3. Writes edge tests from contract definitions, in parallel, for every package in the wave (before any code exists)
  4. Once all tests are committed, spawns an isolated dev agent per package concurrently (each can't see tests or other packages)
  5. Runs tests → passes → commits by logical unit (one package = one commit)
  6. Moves to the next wave of ready packages → repeats until done
```

You describe what you want. The plugin handles decomposition, test writing, isolated development, verification, and commits — fully automated, building independent packages in parallel waves.

## The problem

When AI agents work on large projects:

- **Context overflow**: the agent can't hold the whole codebase in memory. It forgets what it read 10 minutes ago.
- **Cascading errors**: a change in one module breaks three others. The agent patches those, breaking two more.
- **No isolation**: the agent can read and modify anything, so it creates invisible coupling between components.
- **Test gaming**: if the agent can see the tests while coding, it writes code that passes tests rather than code that solves the problem.

These aren't model limitations — they're architectural failures. A smarter model makes them worse, not better, because it modifies more code with more confidence.

## The solution

Treat your project like a **package ecosystem**, not a monolith.

```
project/
├── graph.json                 ← dependency graph (source of truth)
├── contracts/auth-api/        ← interface between auth and api packages
├── packages/auth/             ← independent package (high cohesion)
├── packages/api-gateway/      ← independent package (loose coupling)
├── tests/auth-api.test.*      ← edge tests (invisible to dev agents)
├── overviews/                 ← summaries that replace reading source code
└── shared/                    ← cross-cutting concerns (logging, config)
```

Each package is developed by an isolated agent that can only see:
- ✅ Its own package directory
- ✅ Contract definitions (read-only)
- ✅ Shared modules (read-only)
- ❌ Other packages
- ❌ Test files
- ❌ Git operations

**Hooks enforce these boundaries at the tool level** — even if the agent ignores prompt instructions, PreToolUse hooks block forbidden operations.

## Architecture

```
┌──────┐
│ User │
└──┬───┘
   │ task
   ▼
┌──────────────────────────────────────────────┐
│              Bus Agent (main session)         │
│  Wave loop: Analyze → Test ∥ → Dev ∥ → Run ∥ │
└──┬──────────┬──────────┬──────────┬──────────┘
   │ spawn    │ spawn    │ spawn    │ spawn
   ▼          ▼          ▼          ▼
┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐
│  Zone  │ │  Test  │ │  Dev   │ │  Test  │
│Manager │ │Writer  │ │ Agent  │ │Runner  │
└────────┘ └────────┘ └────────┘ └────────┘
 analyzes    writes     codes      runs
 & routes    tests      1 pkg      tests
             first      only
```

- **Bus Agent**: the main Claude Code session. Routes messages between subagents. Doesn't understand code — only the dependency graph and overviews.
- **Zone Manager**: dynamically generated per session. Owns a group of related packages. Analyzes requirements, produces development specs.
- **Test Writer**: writes comprehensive edge tests from contract definitions *before* any implementation exists. Applies BVA, equivalence partitioning, state transition testing, and error guessing.
- **Dev Agent**: implements exactly one package. Isolated via hooks. If the contract is insufficient, it stops and escalates rather than working around it.
- **Test Runner**: executes edge tests. Cannot modify any file.

**Independent packages run in parallel waves.** Because dev agents code only against locked contract interfaces — never another package's code — packages whose contracts are ready have no development-time coupling and are built concurrently. Each concurrent dev agent runs in its **own sparse git worktree** containing only its package plus read-only `contracts/` and `shared/` — so it physically cannot see sibling packages or test files. **Each package is then tested inside its own worktree before being merged back** — so a failing test pinpoints exactly one package and its broken code never reaches your working tree. Only packages that pass in isolation are harvested into the main tree and committed sequentially, pathspec-scoped (one package = one commit). Parallelism never causes cross-package contamination or merge conflicts.

## Install

**From GitHub:**
```bash
# Inside Claude Code
/plugin marketplace add your-username/modular-dev
/plugin install modular-dev
```

**From local directory:**
```bash
# Inside Claude Code
/plugin marketplace add /path/to/modular-dev
/plugin install modular-dev
```

**Development/testing mode (temporary):**
```bash
claude --plugin-dir /path/to/modular-dev
```

> ⚠️ Do NOT enable the plugin via natural language. Use the `/plugin` command.

## Quick start

```
> /modular-dev:setup

# Describe your project. The plugin will:
# - Decompose it into packages and contracts
# - Partition packages into zones
# - Generate a CLAUDE.md that activates the bus agent protocol
# - Create the full directory skeleton
# - Commit the initial structure

# From now on, just describe what you want:
> Add user authentication with email/password and OAuth

# The bus agent automatically:
# 1. Analyzes → which packages need changes
# 2. Writes edge tests → before any code
# 3. Develops each package → in isolation
# 4. Runs tests → verifies contracts
# 5. Commits → one logical unit per package
```

## Commands

| Command | Purpose |
|---------|---------|
| `/modular-dev:setup` | Decompose a project into packages, contracts, and zones |
| `/modular-dev:plan <task>` | Analyze a task and build a BFS work queue |
| `/modular-dev:develop` | Execute the next unit of work from the queue |
| `/modular-dev:status` | Show progress across all packages |
| `/modular-dev:add-node` | Add a new package |
| `/modular-dev:add-contract` | Add or modify a contract interface |

After `/modular-dev:setup`, the generated `CLAUDE.md` makes all subsequent sessions **follow the bus agent protocol automatically** — no slash commands needed. Just describe your task.

## Key concepts

### Packages (nodes)

Each package is an independent unit of code — like an npm package or a Python module. It has high internal cohesion and communicates with the outside world only through contracts.

### Contracts (edges)

A contract defines the interface between two or more packages: method signatures, input/output types, behavioral constraints. Contracts are defined *before* development starts and are **locked** during implementation — dev agents cannot modify them.

Circular dependencies between packages work because both sides depend on the contract abstraction, not on each other's implementation.

### Zones

Packages that share contracts are grouped into zones. Each zone gets a dynamically generated zone manager agent that understands the packages in its zone. The bus agent routes tasks to zone managers based on the dependency graph.

- ≤10 packages → single zone
- More → auto-partitioned by contract coupling

### Overviews

Every package, contract, and zone has an overview document. These are the *only* information source for manager agents — they never read source code. Overviews are updated after each development cycle and validated against contract type signatures.

### The graph

`graph.json` is the single source of truth. It records all packages, contracts, zones, their dependencies, and their statuses (`pending`, `in-progress`, `done`, `failed`). The bus agent reads this file to route tasks and determine BFS order.

## Hooks

Seven hook scripts enforce architectural constraints at the tool level:

| Script | Event | What it does |
|--------|-------|-------------|
| `session-init.sh` | SessionStart | Loads project status, resets bus state |
| `guard-write.sh` | PreToolUse (Write) | Blocks dev agent writes outside assigned package |
| `guard-read.sh` | PreToolUse (Read) | Blocks dev agent reads of `tests/` and other `packages/` |
| `guard-bash.sh` | PreToolUse (Bash) | Blocks dev agent git operations and test access via shell |
| `pre-agent.sh` | PreToolUse (Agent) | Sets dev isolation state before dev agent spawn |
| `post-agent.sh` | PostToolUse (Agent) | Resets to bus state after subagent completes |
| `strip-coauthor.sh` | PostToolUse (Bash) | Removes `Co-authored-by` lines from commits |

All hooks are **fail-open** — if a hook script errors, it allows the operation rather than blocking it. Only explicit `exit 2` blocks a tool call.

## Design principles

1. **Divide and conquer**: split until each piece fits in an agent's context window
2. **Contract-first**: define interfaces before implementations
3. **Test before code**: edge tests are written from contracts, not from implementations — and dev agents can't see them
4. **Enforced isolation**: hooks block forbidden operations at the tool level, not just via prompt instructions
5. **Rebuild over repair**: when a package fails repeatedly, prune and rebuild from the contract + spec
6. **Overviews over source**: managers never read code — they read summaries. This keeps context small and decisions fast
7. **Sequential execution**: one agent, one package, one commit at a time. Zero conflicts

## Plugin structure

```
modular-dev/
├── .claude-plugin/
│   ├── plugin.json             # Plugin manifest
│   └── marketplace.json        # Local marketplace definition
├── skills/
│   ├── setup/SKILL.md          # Project initialization
│   ├── plan/SKILL.md           # BFS task planning
│   ├── develop/SKILL.md        # Core development loop
│   ├── add-node/SKILL.md       # Add new package
│   ├── add-contract/SKILL.md   # Add/modify contract
│   └── status/SKILL.md         # Progress display
├── agents/
│   ├── developer.md            # Dev agent (isolated, no Agent tool)
│   ├── test-writer.md          # Test writer (contract-based, 4 techniques)
│   └── tester.md               # Test runner (read-only, no write tools)
├── hooks/
│   └── hooks.json              # Hook configuration (auto-loaded)
├── scripts/                    # Hook implementation scripts
├── references/                 # Templates, schemas, protocols
│   ├── CLAUDE.md.template      # Generated into project root
│   ├── bus-protocol.md         # Bus agent state machine
│   ├── graph-schema.md         # graph.json structure
│   └── overview-templates.md   # Overview file templates
└── README.md
```

## Requirements

- Claude Code v2.1+
- Bash (macOS/Linux/WSL)
- Git

No additional dependencies. All hook scripts are pure bash — no Python, no Node, no external tools.

## License

MIT