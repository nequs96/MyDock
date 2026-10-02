# AI accounts and Claude Code limits

MyDock detects existing Codex and Claude Code accounts using the providers’ own local tools. Credentials remain with the provider. It does not inspect browser cookies, copy OAuth tokens, or ask for account passwords.

In **AI Limits**, **AI Activity**, or **Settings → Integrations**, choose **Find Account** to check this Mac. The check also runs automatically when account controls open and when you return to MyDock. **Sign In…** opens the provider’s installed login command in Terminal. If the tool is missing, **Get Codex / Get Claude Code** opens its official installation guide.

Codex uses its local app-server with the documented `stdio://` transport. MyDock waits for initialization before requesting `account/read` or `account/rateLimits/read`, keeps input open until the response arrives, and bounds time and output. Requests do not start a task or consume model tokens. [Official Codex app-server documentation](https://learn.chatgpt.com/docs/app-server).

For Claude:

1. Sign in to **Claude Code**, or let MyDock find its existing account.
2. In AI Limits or Settings → Integrations, choose **Enable Limits**.
3. Start or restart Claude Code and use it once. Limits then sync automatically while you use Claude Code.

Enable Limits adds a status-line bridge using macOS’s built-in `plutil`; `jq` is unnecessary. Other settings, existing status-line output, and status-line options are preserved. Setup saves a private backup of `settings.json`, writes atomically, is idempotent, and refuses invalid or symlinked settings. The configured Claude directory is respected; the default is `~/.claude`.

The bridge saves only quota windows and a timestamp to `mydock-rate-limits.json`. The temporary input is private and removed after the original status line runs. MyDock rejects symlinked snapshots, files larger than 64 KB, invalid data, and samples older than 30 minutes. Spend percentages above 100 remain visible as reported; rings and bars saturate at 100%.

Claude Code 2.1.251 or later supplies the rate-limit fields for supported subscription/gateway accounts after the first API response. Missing windows and API-key-only sessions remain unavailable. Signing in only through Safari or the Claude desktop app does not expose a supported local usage reader; connect Claude Code for this widget. [Official status-line documentation](https://code.claude.com/docs/en/statusline), [authentication commands](https://code.claude.com/docs/en/cli-reference).

To remove the bridge, restore the `statusLine` entry from the saved `settings.before-mydock-…json` backup, preserving any other settings you have changed since setup. Local AI Activity reads usage counters independently of the limits bridge.
