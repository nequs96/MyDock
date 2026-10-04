# Canonical MyDock development baseline

Recorded 4 October 2026, first delegated follow-up wave. Source remains `Sources/MyDock/`; canonical app remains `build/MyDock.app`. Current working-tree wave2 edits are not yet represented by this tested artifact.

Status rechecked 4 October at 06:37 UTC: the canonical executable/hash/signature/architectures/plist still match this baseline. Later source is unfinished and integration-unverified; syntax checking found a malformed new Reliability test, and all three medium specialists are stopped by usage limits. Default-production network isolation guards, Settings scope and diagnostics preview remain open. See [verified work status](history/VERIFIED_WORK_STATUS_2026-10-04.md). No later source/build/native acceptance is implied by the results below.

The first wave separates external readings from in-memory authored edits, protects legacy cache migration and atomic save outcomes, consumes capability metadata in discovery, clarifies repeated instances and converter precision, extracts reveal monitoring, corrects login-state reporting and fixes exact-artifact CI tooling. Scope, dependencies and acceptance are in [the execution ledger](history/EXECUTION_LEDGER_2026-10-03.md). AI configured-root attribution remains a known next-wave gap.

`./TestMyDock.sh` passed: **445 individual passes,5 explicit skips,450 reported tests in56 suites,0 failures**. Five isolated Python manifest fixtures passed. Xcode project regeneration, shell/project/plist/entitlement syntax and whitespace checks passed. Initial compile failures were corrected by their owners before the successful run.

`./BuildMyDock.sh` succeeded after process absence was checked. The canonical executable is universal arm64+x86_64, both slices declare macOS13.0, strict ad-hoc signature and plist checks pass. SHA-256: `67810611f8cb9431f4025d0174a3cc647a99ec8afcb3e16e6f1d642f177fd8c0`. Source/build/test input fingerprint: `c2a69f7861219837f5aa1d3585232de9b56921ab6f73eb341f757959e67567de`. Inputs stayed unchanged during validation.

The exact canonical executable launched as PID5317 with a private validation root and native/credential effects disabled. Normal termination was accepted; the process exited0 and absence was verified. This is an isolated launch/quit check. It does not certify production-data isolation by a disposable-user trace, native actions, compositor/motion, permissions, VoiceOver, live accounts or notification delivery.

The CLI app lacks App Intents metadata. Full Xcode, Developer ID/notarization, Focus discovery, signed login/install/update/rollback, supported-OS and Intel runtime qualification remain blocked/open. No native preference mutation, permission grant, account connection, destructive validation, commit or publication occurred in this continuation.

Logs and machine-readable inputs/evidence are under `.build/orchestrate-20261004/`. [BUILD_BASELINE.json](BUILD_BASELINE.json) identifies the exact artifact. Host: Apple Silicon, macOS27.0.1(26A434), Swift6.3, SDK26.4. [Preceding evidence](history/RELEASE_EVIDENCE_PRE_COORDINATED_FOLLOWUP_2026-10-04.md) and older renders/performance measurements remain explicitly historical.
