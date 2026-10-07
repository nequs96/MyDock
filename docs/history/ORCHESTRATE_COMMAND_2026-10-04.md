# Archived `/orchestrate` command — 4 October 2026

> Archived record of the slash command that resumed the Codex-started execution ledger. That campaign is finished; do not run these steps again. Current acceptance is in [implementation status](../IMPLEMENTATION_STATUS.md).

Act as the coordinator. You are resuming work that a Codex session started. The user ALREADY AUTHORIZED implementation of the required corrective work and the design/architectural improvements, so don't ask for that approval again. Do not write application code yourself except for small integration fixes; delegate the rest to the worker agents.

## 1. Rebuild context
- Read AGENTS.md and docs/history/EXECUTION_LEDGER_2026-10-03.md completely.
- Read docs/history/CODEX_SESSION_VERIFY_AUDIT_2026-10-03.md (the previous Codex session, including its subagents). Codex was in the middle of implementing when it stopped: it was making persistence APIs report durable saves, keeping drafts when a note write fails, wiring this into Restore, note editing and Quit, and isolating the validation boundary. Its partial edits are in commit 6f94afd ("Baseline before Claude agents").
- Use `git show --stat 6f94afd` and `git diff 24f9c76 6f94afd` to see exactly what Codex changed. Treat those edits as unreviewed work in progress: verify them, finish them or fix them.
- If `git status` shows uncommitted changes, stop and ask me to commit them first.

## 2. Plan (short)
- Update the ledger: for every entry Codex touched, record its implementation status and verification status.
- Group the remaining work into batches: (1) required corrective work, (2) design and architectural improvements, (3) OP-* optional opportunities. Do NOT implement batch 3; list those items for a product decision.
- Assign the packages in dependency order to reliability / native-platform / product-experience, with exclusive file ownership. Shared models and integration changes stay with one owner.
- Show the plan in a few lines and then continue. Pause only if something is ambiguous or risky.

## 3. Execute
- Spawn the agents in parallel where their files don't overlap, each with isolation: worktree, an exact package list and acceptance criteria. Run dependent packages in order.
- Review every diff critically (correctness, scope, AGENTS.md compliance). Send it back for fixes when needed.
- Merge the branches one at a time. You alone coordinate builds: run ./BuildMyDock.sh and launch build/MyDock.app after integrating.
- Only you edit the ledger. Update it after every package, tracking implementation and verification separately.

## 4. Hard rules (from the original brief)
- Treat the reports as specifications and evidence leads. Verify the current source before acting.
- Do not grant permissions, connect accounts, modify user data, change native system preferences or exercise destructive features to get validation evidence. Use isolated fixtures, and record native acceptance you couldn't run as blocked.
- Never mark acceptance complete just because a report says implemented, a build passes, a static render looks right or an unrelated test passes.
- Preserve existing working-tree changes. Do not push or publish.

## 5. Finish
Before declaring completion, reconcile every MD-* finding, PR-* package, OP-* opportunity, widget family and acceptance scenario in the ledger. Report completed, partial, blocked, deferred and unstarted work separately. Never represent unverified behavior as passed. List the manual tests I still need to do on the native app.

Extra focus: $ARGUMENTS
