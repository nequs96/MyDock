# Historical MyDock evidence

These reports preserve the observations and hashes from their original dates. Current development uses `Sources/MyDock/` and the single canonical app **`build/MyDock.app`**. See [current build evidence](../RELEASE_AUDIT.md) and [implementation status](../IMPLEMENTATION_STATUS.md).

| Report | Evidence |
| --- | --- |
| [Dock workspace rebuild](DOCK_WORKSPACE_REBUILD_2026-10-01.md) | [Directive acceptance ledger](PRODUCT_DESIGN_ACCEPTANCE_2026-10-01.md) |
| [Account and interface follow-up](ACCOUNT_AND_INTERFACE_FOLLOWUP_2026-10-01.md) | [Verification](ACCOUNT_AND_INTERFACE_VERIFICATION_2026-10-01.json) |
| [Canonical consolidation baseline](CANONICAL_BASELINE_2026-09-30.md) | [Verification](CANONICAL_BASELINE_VERIFICATION_2026-09-30.json) |
| [Repository review](REPOSITORY_REVIEW_2026-09-29.md) | Original roadmap and bug findings |
| [Final-build gap audit](FINAL_BUILD_GAP_AUDIT.md) | Historical acceptance gaps |
| [Product audit](FINAL_PRODUCT_AUDIT_CURRENT.md) | 29 September code audit |
| [Implementation verification](IMPLEMENTATION_VERIFICATION_2026-09-30.json) | Original implementation package and test hashes |
| [Apple-style design](APPLE_DESIGN_REBUILD_2026-09-30.md) | [Verification](APPLE_DESIGN_VERIFICATION_2026-09-30.json) |
| [Premium redesign](PREMIUM_REDESIGN_2026-09-30.md) | [Verification](PREMIUM_REDESIGN_VERIFICATION_2026-09-30.json) |
| [Bug audit](BUG_AUDIT_2026-09-30.md) | [Verification](BUG_AUDIT_VERIFICATION_2026-09-30.json) |
| [Gallery and visibility fixes](GALLERY_AND_DOCK_FIXES_2026-09-30.md) | [Verification](GALLERY_AND_DOCK_VERIFICATION_2026-09-30.json) |
| [Replacement mode and gallery](REPLACEMENT_MODE_AND_GALLERY_2026-09-30.md) | [Verification](REPLACEMENT_MODE_AND_GALLERY_VERIFICATION_2026-09-30.json) |
| [Earlier release evidence](RELEASE_EVIDENCE_2026-09-30.md) | Candidate builds and original acceptance checks |
| [Performance baseline, 29 September](PERFORMANCE_BASELINE_2026-09-29.json) | [30 September](PERFORMANCE_BASELINE_2026-09-30.json) |

## Recoverable local archive

The cleanup archive is alongside the repository at:

```text
../dockX-archive/2026-09-30-canonical-baseline/
```

It retains the source tree before cleanup and Git working-tree patch/status. `legacy-builds.zip` contains older application bundles, packaged ZIPs and old release staging. `legacy-local-artifacts.zip` contains experimental compiler artifacts, visual renders, logs and prior source snapshots. Both ZIPs were integrity-checked; important source/evidence files and app executables were also compared with their originals before the loose archive folders were removed. `baseline.json` records the original source hashes; `relocated-artifacts.json` maps the moved artifacts; `archive-verification.json` records checksums and verification counts. Paths beginning with `build/` in older reports now refer to the legacy-builds archive; historical `.build/` experiment paths are in the local-artifacts archive.

The archive is not an active build workspace. Saved profiles and credentials remain in their existing system locations. Existing source changes were preserved and were not reset or committed during cleanup.

- [Widget presentation, icon styles and utilities — 1 October 2026](WIDGET_PRESENTATION_AND_UTILITIES_2026-10-01.md): 30 widget popovers, three local tools, 242 tests and 76 final renders; native interaction limits recorded.
