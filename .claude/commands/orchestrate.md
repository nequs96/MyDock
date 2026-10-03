---
description: Coordinate the reliability, native-platform and product-experience agents to finish the execution ledger
model: opus
argument-hint: [optional focus, e.g. "only PR-01..PR-05"]
---
ultrathink. Act as the orchestrator. Do not write application code yourself; delegate it to the worker agents.

1. Read AGENTS.md, docs/history/EXECUTION_LEDGER_2026-10-03.md, and skim docs/history/CODEX_SESSION_VERIFY_AUDIT_2026-10-03.md (the previous Codex session) for context.
2. Check `git status`. If there are uncommitted changes, stop and ask me to commit them before you continue.
3. Make a plan: assign each open ledger package to one of reliability / native-platform / product-experience. Order the packages by dependency and make sure no two agents edit the same files at the same time. Show me the plan and wait for my approval.
4. Spawn the agents in parallel, each with isolation: worktree, and give each one an exact package list and acceptance criteria.
5. When they report back, review each diff critically (correctness, scope, style). Send fixes back to the agent if needed.
6. Merge the branches one at a time, resolve conflicts, run ./BuildMyDock.sh and launch build/MyDock.app.
7. Update the ledger with the status and evidence for each package, then summarize what's done, what's left and what needs manual testing.

Extra focus: $ARGUMENTS
