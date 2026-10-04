# Reporting a MyDock problem

Start with the operation that failed and whether your work is still recoverable. Save failures, missing drafts, wrong-account readings and native actions targeting the wrong copy need priority over appearance differences.

1. Record MyDock's installed version/build, macOS version, Apple Silicon or Intel, and whether the app came from the local canonical build or a publisher release. For a publisher release, include its release-manifest identifier or executable hash when available.
2. Describe the shortest steps, expected result and observed result. Say whether it happens after relaunch and whether Retry succeeds. Mention setup mode, Dock position, approximate item count and relevant permission status. Do not grant permissions or change native preferences merely to reproduce a report.
3. For a reading problem, identify the provider and metric, displayed freshness/status and whether the account was replaced. Use a pseudonym for the account. Never send credentials, raw provider responses, private local AI logs or billing exports.
4. If useful, export diagnostics from MyDock's Settings. Review the contents before sharing and remove anything you consider sensitive. Diagnostics are saved locally; MyDock does not automatically upload them. Send a reproduction description alongside the file rather than relying on counters alone.
5. Redact screenshots: notes, calendar titles, file names, account names, window previews and saved snippets can contain private information. A fabricated example is usually enough for layout issues.

Keep failed-save drafts, recovery records and original incompatible files until the problem is understood. Do not delete Application Support or repeatedly reinstall as an initial recovery step. Use the visible Retry Save or native recovery command; if it fails, record the message and stop repeating the operation. Existing provider disconnect controls remove local credentials, while access revocation belongs to the provider.

## Maintainer triage

Record impact, recoverability, reproducibility, affected artifact and evidence class separately. Distinguish a source defect, isolated fixture failure, native acceptance gap and missing environment. Preserve originals and reproduce with synthetic private data in an isolated validation root first. Native preferences, permission changes, destructive actions and real accounts require separately authorized disposable environments.

For a fix, record the command outcome, retained data, source changes, relevant fixture result and remaining desktop/account acceptance. Confirm that evidence matches the tested executable and its source fingerprint. A local ad-hoc build is not a signed-release or supported-OS result. Do not request automatic telemetry, upload user data or expand a report into optional product changes.
