# Claude Code limit snapshots

Claude Code can include subscription rate-limit windows in the JSON it sends to a configured status line. MyDock does not read Claude credentials or query Anthropic's private OAuth endpoints. It reads only `~/.claude/mydock-rate-limits.json`, a small file containing the reported windows and a sample timestamp.

This requires a current Claude Code version, a first-party Pro/Max subscription or a gateway spend limit, and a `jq` executable. Anthropic says rate-limit fields may be absent until a session has received its first API response. See the [official status-line documentation](https://code.claude.com/docs/en/statusline).

1. In AI Limits, enable Claude and click **Copy statusLine value**.
2. Merge the copied JSON string into `statusLine.command` in `~/.claude/settings.json`. Keep any existing status-line output by adding the file-writing step to your current command.
3. Use Claude Code until the status-line JSON contains a `rate_limits` object. MyDock checks the local file while the AI Limits popout is open.

The copied value creates a private temporary file, extracts only `rate_limits` and the current time with `jq`, then atomically replaces the snapshot. It never writes session IDs, transcript paths, prompts, or project details. MyDock rejects symlinks, files over 64 KB, invalid percentages, and samples older than 30 minutes. Reported spend percentages above 100 stay visible as reported; rings and bars saturate at 100%. Missing windows and API-key-only sessions remain unavailable; MyDock does not estimate them.

If there is no existing `statusLine` setting, the copied command prints a short confirmation in Claude Code's terminal status line after saving. To stop sharing limits, remove the status-line command and delete `~/.claude/mydock-rate-limits.json`.
