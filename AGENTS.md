# MyDock development

- Continue from the current `Sources/MyDock/` working tree. It contains the completed redesign and subsequent Dock/gallery fixes. App bundles are generated outputs, not source baselines.
- The canonical local app is `build/MyDock.app`. Build it with `./BuildMyDock.sh` and launch that same path after each change.
- Keep `build/` for the canonical app. Do not create new named candidate, audit or redesign builds there. Use `.build/visual-qa/` for disposable validation bundles when required.
- Quit the target app cleanly before rebuilding. Never overwrite or move a running app bundle. Preserve profile drafts and let MyDock restore owned system preferences on quit.
- Use `./TestMyDock.sh` for the relevant tests. Keep opt-in native mutation and synthetic/runtime scenarios explicit.
- SwiftPM caches/debug products and Xcode DerivedData are intermediates. They are not alternate user-facing app baselines.
- Read `docs/RELEASE_AUDIT.md` for current build evidence and `docs/IMPLEMENTATION_STATUS.md` for remaining acceptance. Dated reports belong in `docs/history/`.
- Update current build evidence when validating a new development baseline; keep older verification explicitly dated.
- Preserve existing source changes, profile persistence, integrations and permissions. Repository cleanup must not touch `~/Library/Application Support/MyDock` or credentials.
