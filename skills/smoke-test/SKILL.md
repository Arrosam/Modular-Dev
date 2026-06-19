---
name: smoke-test
description: Smoke-test the assembled application from a fresh new user's perspective, then loop fixes until clean. Generates a new-user manual test plan from what just shipped, runs it in a clean throwaway worktree (a simulated fresh clone), records bugs, then drives /modular-dev:plan and /modular-dev:develop to fix them — repeating until the app passes. Use after a develop wave, or when the user says "smoke test", "test as a new user", "end-to-end test the app", "manual test the application", "does the app actually work", "smoke-test loop", or "/modular-dev:smoke-test".
---

# Smoke-test the application as a fresh new user

You are the bus agent running the **acceptance gate** for a modular-dev project. After packages have been built and their edge tests pass, this skill answers the one question the edge tests cannot: *does the assembled product actually work for a real person who has never seen it before?* You then drive a closed loop — find bugs, plan fixes, develop fixes, re-test — until the app passes.

## Smoke test vs. edge tests — why this exists

Edge tests are **white-box and contract-scoped**: written before code, per contract, the dev agent can't see them. They prove each node fulfils its contract *in isolation*.

A smoke test is **black-box and whole-application**: run after integration, from the outside, as a brand-new user. It catches exactly what edge tests structurally cannot:
- Integration gaps — every node passes its contract, yet the wired-together app still breaks.
- First-run friction — a new user can't install, build, or even figure out how to start it.
- Missing or wrong docs — the README doesn't tell a newcomer how to run the thing.
- Confusing UX and poor error messages — the happy path works, but only if you already know the trick.

If every edge test is green and the app still doesn't work end-to-end for a newcomer, *this* is the gate that catches it.

## Prerequisites

1. Verify `graph.json` exists in the project root. If not, tell the user to run `/modular-dev:setup` first.
2. This skill is most useful **right after a `/modular-dev:develop` wave completes**, but it also runs standalone to audit the current committed state.
3. Make sure the fresh-user worktree dir is git-ignored (idempotent — appends only if absent), and `.claude/` exists for the findings report:
   ```bash
   mkdir -p .claude
   grep -qxF '.mdsmoke/' .gitignore 2>/dev/null || printf '.mdsmoke/\n' >> .gitignore
   ```
4. Generate a unique run ID for this smoke session: `date +%Y%m%d-%H%M%S` (used for the worktree path and findings file).

## Step 1: Determine the change surface ("what shipped")

Establish what to focus the test on, in this order:

1. **Most recent queue(s)** — read `.claude/modular-dev-queue-*.json` (and legacy `.claude/modular-dev-queue.json`). The newest one with `done` items gives you the `task` description and the list of nodes that were just modified.
2. **Git history** — `git log --oneline --stat <since>..HEAD` (use the queue's `planned_at`, or the last few commits if no timestamp) to see which files and nodes actually changed.
3. **Affected node overviews** — for each changed node, read `overviews/nodes/<node-id>.md` to learn its **user-facing surface**: what it exposes, what a user does with it.

Always read `overviews/project.md` for the overall product purpose and the intended user.

**Fallback:** if there is no recent develop work (e.g. first ever smoke test), treat the *whole project* as the change surface — base the plan on `overviews/project.md` plus every node overview, and run a full new-user end-to-end pass.

Stay consistent with the bus model: derive everything from **overviews, the queue, and git — never by reading package source**. Coordination knowledge lives in overviews.

## Step 2: Generate the new-user manual test plan

Write scenarios through the eyes of someone using this application for the **first time**. Cover these lenses, weighted toward the change surface from Step 1:

- **First run / setup / install** — can a newcomer get from "fresh clone" to "running" using only the README/getting-started? (If the docs don't say how, that itself is a finding.)
- **Primary happy paths** — the core value proposition, done end-to-end the way a real user would.
- **Discoverability** — is it obvious how to do the main thing without reading the source?
- **Naive / wrong input** — what a confused user types by mistake.
- **Error handling & messages** — when something goes wrong, is the failure graceful and the message informative?
- **The changed surface** — exercise the new/modified behavior directly, plus a regression check on the paths it touches.

Each scenario is a concrete, executable script — not a vague intention:

```
[<S-id>] <one-line user goal, in the user's words>
  Persona     : <who this user is / what they already know>
  Preconditions: <starting state — usually "fresh clone, nothing installed">
  Steps       : 1. <exact action a naive user would take>
                2. ...
  Expected    : <observable result that means success>
  Surface     : <node-id(s) / contract(s) this exercises, from Step 1>
  Severity-if-broken: P0 | P1 | P2 | P3
```

Severity scale (used throughout): **P0** app won't install/build/run or a core path is dead · **P1** a major feature is broken · **P2** minor or edge-case defect · **P3** cosmetic / docs nit.

**Present the plan to the user** as a compact scenario table and invite them to add, drop, or reword scenarios. Smoke testing is **read-only and isolated** (Steps 3–4 run only inside a throwaway worktree and never touch the repo), so unlike development it does **not** require a hard approval gate — present it, accept any edits, and proceed. The hard approval gate lives later, at the fix-planning boundary (Step 6), where real code changes begin.

## Step 3: Spin up a fresh-user worktree (a simulated fresh clone)

A new user gets only what's committed — they clone the repo and nothing else. A full worktree at `HEAD` reproduces that exactly: tracked files only, so the git-ignored `overviews/`, `.claude/`, `node_modules/`, and build artifacts are all **absent**, just as they would be for a newcomer. The newcomer (the smoke-tester) has to install and build from scratch — which is part of the test.

```bash
git worktree add .mdsmoke/<run-id> HEAD
```

Use a **full** checkout here (no sparse-checkout) — a real user receives the whole project, not a single node. This is deliberately different from `/modular-dev:develop`, which uses sparse per-node worktrees under `.mdwt/` for write-isolation; smoke testing is read-only on code and needs the whole assembled app.

## Step 4: Run the smoke test (spawn the smoke-tester subagent)

Spawn the **`modular-dev:smoke-tester`** subagent (defined in `agents/smoke-tester.md`), rooted in the worktree. It plays the naive user: it discovers how to run the app the way a newcomer would (README → getting-started → `package.json` scripts / Makefile / Dockerfile), executes each scenario, and reports faithfully what happened. It does **not** read or fix code beyond what's needed to run the app, and it never touches the main tree.

> **Critical — do NOT include the dev isolation directive.** The phrase "create and modify files under" flips a subagent into dev-isolation mode via the PreToolUse hook, which would block the tester from running install/build commands and from reading across packages. The smoke-tester must run freely inside its worktree, so its prompt must **not** contain that phrase. Use the rules below verbatim instead.

Construct the prompt by assembling the scenario plan with this wrapper:

```
You are smoke-testing an application as a brand-new user who has never seen it before.

Work entirely inside the directory `.mdsmoke/<run-id>/` — treat its root as a fresh clone of the project. It contains only committed files: no dependencies are installed and nothing is built yet. Getting it running is part of the test.

Your job:
1. Discover how a newcomer would run this app — read the README / getting-started / quickstart first, then fall back to package.json scripts, Makefile, Dockerfile, or other obvious entry points. If the docs do not explain how to install or run it, that is itself a finding (record it; then do your best to start it anyway).
2. Install / build / start the app from scratch, exactly as the docs instruct.
3. Execute each scenario below, step by step, as a real user would.
4. Record what actually happened for every scenario.

Scenarios:
<the scenario table from Step 2>

Rules:
- You may READ any file in the worktree and RUN any command needed to install, build, and operate the app inside the worktree.
- Do NOT modify the application's source code, and do NOT run git commands. You are testing the build as shipped, not changing it.
- Run only in a LOCAL / sandbox configuration. Take NO outward-facing or destructive action — no real emails, no production endpoints, no payments, no writes to shared/remote systems. If a scenario would require a real external side effect, stub or skip it and record that you did.
- Report findings, do not propose code fixes — you are the tester, not the developer. Name the suspected area (node/contract) when you can, but leave the diagnosis to the bus.

Return, for EVERY scenario:
- status: PASS | FAIL | BLOCKED  (BLOCKED = couldn't even attempt it, e.g. app wouldn't start)
- severity: P0 | P1 | P2 | P3  (only for FAIL/BLOCKED)
- repro: the exact commands/steps you ran
- expected vs. actual: what should have happened vs. what did
- suspected area: node-id / contract-id you think is involved, if any
- evidence: the relevant error output or observation (quote it; do not paraphrase away the detail)
Also return: how you started the app (command(s) used), and any setup friction a new user would hit.
```

If the test plan is large, you may split scenarios across multiple smoke-tester subagents and run them in parallel (they are read-only on code and each gets its **own** fresh worktree — give each a distinct `<run-id>` so they don't share a working directory). For most projects a single tester over one worktree is simplest.

## Step 5: Triage and record findings

When the smoke-tester returns, classify each reported failure — do not forward raw noise into a fix plan:

- **bug** — a genuine code or integration defect. Goes into the fix loop.
- **doc-ux** — the code may be "correct" but a new user is blocked or misled (missing run instructions, unhelpful error, undiscoverable feature). Still a real finding; fix the docs/UX via the same loop.
- **not-a-bug** — user error, expected behavior, environment-specific, or out of scope. Record the reason and drop it from the loop.

Write the findings report to `.claude/modular-dev-smoke-<run-id>.json` for the audit trail:

```json
{
  "run_id": "<run-id>",
  "iteration": 1,
  "based_on": { "queue_id": "<id or null>", "task": "<task or 'full app pass'>", "commit_range": "<base>..HEAD" },
  "scenarios": [
    { "id": "S1", "goal": "...", "surface": ["<node-id>"], "severity_if_broken": "P1" }
  ],
  "findings": [
    {
      "id": "F1", "scenario": "S1", "severity": "P0",
      "classification": "bug | doc-ux | not-a-bug",
      "summary": "...", "repro": ["..."], "expected": "...", "actual": "...",
      "suspected_nodes": ["<node-id>"], "status": "open"
    }
  ]
}
```

**If there are no `bug` or `doc-ux` findings at P0–P2** (only P3 nits or not-a-bug items), the app passes this gate. Report success (Step 9), remove the worktree, and the loop ends. Otherwise continue.

## Step 6: Plan the fixes (`/modular-dev:plan`)

Synthesize a fix task from the confirmed `bug` / `doc-ux` findings — group them by suspected node where possible and quote the repro for each — then invoke the **`/modular-dev:plan`** skill with that task description. Plan routes to the zone managers, builds the BFS fix queue, renders the change diagram, and **enforces the standard hard approval gate**: no development begins until the user approves the plan. That gate is intentional and is preserved here.

### Auto-fix opt-in (how the loop stays "automatic" without breaking the safety rule)

The first time you reach this step, offer the user a choice:

- **Approve this fix plan** (default) — you review and approve each fix plan/wave as it comes, the normal way.
- **Auto-fix** — you grant the smoke loop **durable approval** to plan, develop, and re-test fixes for the bugs surfaced in the findings report, iterating without re-confirming each plan and wave. You still see the findings report and the final summary, and the loop still stops and escalates on anything unexpected (see Step 8).

"Auto-fix" is explicit, opt-in authorization scoped to this loop — it satisfies the project's hard "no development without approval" rule by being approval granted up front for the loop, not a bypass of it. Default behavior, if the user says nothing, is to ask per plan.

## Step 7: Develop the fixes (`/modular-dev:develop`)

Once the fix plan is approved (per-plan, or up front via auto-fix), invoke **`/modular-dev:develop`** to execute the fix queue — write tests, develop in isolated worktrees, verify, and commit — repeating until that queue's pending items are drained. This is the existing develop loop unchanged; smoke-test just feeds it.

## Step 8: Loop until clean

After the fixes are committed, close the loop:

1. **Refresh the fresh-user view** — remove the old worktree and recreate it at the new `HEAD` so the next pass sees a clean clone of the fixed code:
   ```bash
   git worktree remove --force .mdsmoke/<run-id>
   git worktree add .mdsmoke/<new-run-id> HEAD
   ```
   (A fresh worktree avoids stale build artifacts leaking between iterations. Use a new run ID per iteration.)
2. **Re-run the smoke test** (Steps 4–5) over the **same scenarios**, plus a focused regression check on each bug that was just fixed (re-run its exact repro). Increment the `iteration` count in the findings report.
3. **Decide:**
   - **Clean** (no P0–P2 `bug`/`doc-ux` findings) → done. Go to Step 9.
   - **New or remaining bugs** → back to Step 6 for another fix cycle.

**Convergence guards** — never loop forever:
- **Iteration cap** — default **3** full smoke→fix iterations. On hitting the cap without converging, stop and hand the user the outstanding findings rather than continuing silently.
- **Recurrence escalation** — if a *specific* finding survives a fix cycle that targeted it (i.e. the same repro still fails after development aimed at it), escalate **that** finding to the user with the zone manager's diagnosis instead of re-queuing it blindly. This mirrors the develop loop's 3-strike escalation: a bug that won't die signals a spec/contract problem, not a coding slip.
- Always clean up: `git worktree remove --force` for every `.mdsmoke/<id>` you created, at the end and between iterations.

## Step 9: Report

Summarize the whole smoke session for the user:

```
Smoke test — <task summary or "full app pass">  (run <run-id>, <N> iterations)

Scenarios: <total> run · <pass> pass · <fail> fail · <blocked> blocked
Bugs:      <found> found → <fixed> fixed → <outstanding> outstanding

  Fixed this session:
    - [<F-id>] <severity> <summary> — fixed in <node-id> (commit <short hash>)
  Outstanding / escalated:
    - [<F-id>] <severity> <summary> — <why it's still open / escalation reason>
  Accepted (not-a-bug / deferred P3):
    - [<F-id>] <summary> — <reason>

Result: PASS — app works end-to-end for a fresh user
   (or) NEEDS ATTENTION — <count> finding(s) escalated; see .claude/modular-dev-smoke-<run-id>.json
```

State the result plainly. If anything failed or was skipped, say so with the evidence — a smoke test that "passed" only because a scenario was blocked is not a pass.
