# Notchling

Tasks, notes, focus timers, calendar and clipboard clips in your Mac's notch. Free and open source (MIT).

Click the notch or press **⌥N**. Macs without a notch get one drawn at the top center of the screen.

> Notchling is an independent, clean-room project. It is written from scratch from publicly described
> notch-app features, and it shares no code, assets or branding with any commercial notch app.
> Please don't contribute code or assets copied or decompiled from closed-source apps.

## Features

| Area | What it does |
|---|---|
| **Notch** | Opens on click, ⌥N, or (optionally) hover. Closes on Esc or a click outside. Follows the pointer between displays. Draws a notch on displays without one. Adjustable size. |
| **Today** | Natural-language quick add: `call mom tomorrow at 5pm !` sets the day, a reminder at 17:00 and marks it important. URLs become attached links. Unfinished tasks carry forward to today. |
| **Reminders** | When a task comes due the notch opens with a chime: **Snooze 10 min** or **Done**. Alerts queue. Pause all reminders for an hour from the menu bar. |
| **Plan your day / Wrap up** | Plan fits today's untimed tasks into free time around calendar events, important first, and sets reminders. Wrap up moves leftovers to tomorrow or the Inbox. Offered once a day (can be turned off). |
| **Week** | Inbox plus the next 7 days. Drag tasks between columns. |
| **Notes** | A daily notepad that autosaves. **⌘↩** turns the current line into a task. |
| **Focus** | Countdown or stopwatch, pause/resume, +5 min. Pauses while the Mac sleeps. Procedural brown/pink/white/ocean noise. Runs your own Shortcuts on start/end (e.g. Do Not Disturb). A live timer shows beside the closed notch. |
| **Calendar** | Read-only next two weeks from Apple Calendar (including Google/Outlook accounts added in System Settings). One-click **Join** for Zoom/Meet/Teams/Webex links; the notch pops open when a meeting starts. |
| **Clips** | Recent copies, new screenshots and screen recordings. Click to copy, drag into any app, or make a task. Items that password managers mark as concealed are skipped. |
| **Insights** | Done today/week, active focus minutes, streak, best focus hour. |
| **AI agents (MCP)** | A bundled local MCP server (`notchling-mcp`) lets Claude Code, Claude Desktop or Cursor list/add/complete tasks, read/append notes and read insights. |
| **URL scheme** | `notchling://open/<tab>`, `notchling://close`, `notchling://add?text=…`, `notchling://focus?minutes=25` for Raycast, Alfred, Shortcuts. |

All data lives in one JSON file on your Mac: `~/Library/Application Support/Notchling/data.json`. No account, no network.

## Install

Download the DMG from Releases, open it, drag **Notchling** to Applications.

Builds from this repo are ad-hoc signed, so the first launch needs right-click → **Open** (or
`xattr -dr com.apple.quarantine /Applications/Notchling.app`). Release builds signed with a Developer ID and notarized open normally.

Requires macOS 14 or later. Apple silicon and Intel.

## Build

```sh
swift test                  # core logic tests
swift run Notchling         # run in dev (calendar needs the bundled app for its permission prompt)
scripts/build-dmg.sh        # dist/Notchling.app + dist/Notchling-<version>.dmg (universal)
```

Signed + notarized release:

```sh
xcrun notarytool store-credentials notary   # once
SIGN_ID="Developer ID Application: You (TEAMID)" NOTARY_PROFILE=notary VERSION=0.2.0 scripts/build-dmg.sh
```

Set `NOTCHLING_DATA=/path/to/file.json` to point the app or the MCP server at a different data file.

## Connect an AI agent

Claude Code:

```sh
claude mcp add notchling -- /Applications/Notchling.app/Contents/MacOS/notchling-mcp
```

Claude Desktop / Cursor (`mcp.json`):

```json
{ "mcpServers": { "notchling": { "command": "/Applications/Notchling.app/Contents/MacOS/notchling-mcp" } } }
```

Tools: `list_tasks`, `add_task`, `complete_task`, `get_note`, `append_note`, `insights`. The app picks up changes within two seconds.

## Layout

```
Sources/NotchlingCore    Models, natural-language parser, focus clock, day planner, insights, data file (pure, tested)
Sources/Notchling        The app: notch panel, SwiftUI views, calendar/clipboard/sound services
Sources/notchling-mcp    stdio MCP server over the same data file
Tests/                   XCTest for NotchlingCore
scripts/                 DMG build and icon generator
```

## Roadmap

Apple Reminders two-way sync, voice task entry (on-device speech), desktop widgets and App Intents, Spotlight indexing,
travel-time "time to leave" alerts, distraction nudges, localization. PRs welcome.

## License

MIT. See [LICENSE](LICENSE).
