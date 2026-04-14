# Maitrics — Design Spec

macOS menu bar app that displays Claude Code CLI usage data in a modern dark dashboard popup.

## Overview

Maitrics is a native macOS menu bar utility that reads Claude Code's local usage data from `~/.claude/` and presents it in a popover with today's summary, model breakdown, usage trends, and recent sessions. The menu bar icon changes color based on configurable token usage thresholds.

## Technology

- **Language:** Swift
- **UI Framework:** SwiftUI (popup content) + AppKit (menu bar integration via `NSStatusItem` + `NSPopover`)
- **Charts:** Swift Charts (requires macOS 13+)
- **Minimum Target:** macOS 14 (Sonoma) — required for @Observable and @Bindable
- **Distribution:** DMG installer
- **App Type:** Menu bar only — no dock icon, no main window (`LSUIElement = true`)

## Data Sources

All data is read locally from `~/.claude/`. No API keys or network requests required.

### Primary: `~/.claude/stats-cache.json`

Aggregated stats file containing:
- `dailyActivity`: per-day messageCount, sessionCount, toolCallCount
- `dailyModelTokens`: per-day token usage broken down by model
- `modelUsage`: aggregate per-model stats (inputTokens, outputTokens, cacheReadInputTokens, cacheCreationInputTokens)
- `totalSessions`, `totalMessages`
- `hourCounts`: usage distribution by hour of day
- `firstSessionDate`: when the user started using Claude Code

### Secondary: Per-project session indexes

- `~/.claude/projects/<project-path>/sessions-index.json` — session metadata (sessionId, firstPrompt, messageCount, created, modified, gitBranch, projectPath)
- Individual session JSONL files are only parsed on demand (drill-down) to avoid reading hundreds of MB on every refresh

### Token usage structure per message (in JSONL files)

```json
{
  "usage": {
    "input_tokens": 1234,
    "output_tokens": 567,
    "cache_creation_input_tokens": 100,
    "cache_read_input_tokens": 200
  }
}
```

## Data Models

```
TokenUsage
  inputTokens: Int
  outputTokens: Int
  cacheReadInputTokens: Int
  cacheCreationInputTokens: Int
  model: String

DailyActivity
  date: Date
  messageCount: Int
  sessionCount: Int
  toolCallCount: Int
  tokensByModel: [String: TokenUsage]

Session
  sessionId: String
  projectPath: String
  firstPrompt: String
  messageCount: Int
  created: Date
  modified: Date
  gitBranch: String?
  totalTokens: TokenUsage
  estimatedCost: Double

AppSettings (persisted to UserDefaults or app config file)
  thresholdGreen: Int       — default 100,000 tokens
  thresholdYellow: Int      — default 500,000 tokens
  modelPricing: [String: PricingTier]

PricingTier
  inputPer1M: Double
  outputPer1M: Double
  cacheReadPer1M: Double
  cacheWritePer1M: Double
```

## Architecture

### Components

1. **MaitricsApp** — SwiftUI `App` entry point. Sets `LSUIElement`. Creates the `StatusBarController`.

2. **StatusBarController** — AppKit class owning the `NSStatusItem` and `NSPopover`. Handles:
   - Rendering the menu bar icon with dynamic color (green/yellow/red) based on today's total tokens vs configured thresholds
   - Toggling the popover on click
   - Triggering a data refresh on popover open

3. **ClaudeDataManager** (`@Observable`) — Singleton responsible for:
   - Parsing `stats-cache.json` and session index files
   - Publishing parsed data as observable properties
   - Computing cost estimates from token counts using the pricing table
   - Aggregating today's stats, model breakdowns, and daily trends

4. **FileWatcher** — Uses `DispatchSource.makeFileSystemObjectSource` or `FSEvents` to watch `~/.claude/` for changes. Notifies `ClaudeDataManager` to re-parse on change. Combined with refresh-on-popover-open as a safety net.

5. **SwiftUI Views** — The popup content, described below.

6. **SettingsView** — Preferences panel for configuring thresholds and model pricing. Accessible via the gear icon in the popup header.

### Data Flow

```
~/.claude/ files change
  → FileWatcher detects change
  → ClaudeDataManager re-parses affected files
  → @Observable properties update
  → SwiftUI views reactively re-render
  → StatusBarController updates icon color if today's totals crossed a threshold
```

Additionally, popover open triggers a refresh as a safety net.

## Popup UI Layout

420px wide `NSPopover` with the following sections top-to-bottom, using Layout A (Card Grid) style:

### 1. Header
- Left: "MAITRICS" app title
- Right: gear icon opening Settings

### 2. Today's Summary
- Label: "Today"
- Three stat cards in a row:
  - **Est. Cost** (green accent) — e.g., `$4.82`
  - **Tokens** (blue accent) — e.g., `247k`
  - **Sessions** (purple accent) — e.g., `8`

### 3. Model Breakdown
- Label: "By Model"
- Horizontal progress bars for each model (Opus / Sonnet / Haiku)
- Each bar has: model name, colored fill proportional to usage, token count
- Colors: Opus = orange, Sonnet = blue, Haiku = purple

### 4. Usage Trend Chart
- Label: "Usage Trend"
- Segmented control to switch between 7d / 30d / All time
- Bar chart (Swift Charts) with one bar per day
- Today's bar highlighted in green
- Y-axis: token count

### 5. Recent Sessions
- Label: "Recent Sessions"
- Last 5 sessions, each row showing:
  - First prompt text (truncated)
  - Project name, git branch, time ago
  - Token count + estimated cost (e.g., `52k  ~$1.20`)
- Scrollable if more sessions available

### 6. Footer
- Left: green dot + "Live" file watcher status
- Right: "Last: just now" timestamp of last data refresh

## Visual Style

- **Dark theme** with native macOS vibrancy (`NSVisualEffectView` / `.ultraThinMaterial`)
- Background: dark translucent with blur
- Subtle borders: `rgba(255,255,255,0.06)`
- Cards: slightly lighter background with soft borders
- Typography: SF Pro (system font), uppercase labels for section headers
- Color palette:
  - Green (#4ade80): cost, today indicator, live status
  - Blue (#60a5fa): tokens
  - Purple (#c084fc): sessions, Haiku
  - Orange (#f97316): Opus
  - Blue (#3b82f6): Sonnet

## Menu Bar Icon

- SF Symbol `gauge.with.dots.needle.33percent` (or similar gauge symbol) as the base icon
- Dynamic tint color based on today's total token count:
  - **Green:** below `thresholdGreen` (default 100k)
  - **Yellow:** between `thresholdGreen` and `thresholdYellow` (default 500k)
  - **Red:** above `thresholdYellow`
- Thresholds configurable in Settings

## Settings Panel

Accessed via gear icon in popup header. Contains:

- **Thresholds section:**
  - Green threshold (token count, default 100,000)
  - Yellow threshold (token count, default 500,000)
- **Pricing section:**
  - Per-model pricing (input/output/cache per 1M tokens)
  - Pre-populated with current Claude pricing, user can update
- **General:**
  - Launch at login toggle
  - Claude data path (default `~/.claude/`, configurable for non-standard setups)

## Cost Estimation

Calculated locally from token counts. Clearly labeled as "estimated" everywhere.

Formula per model:
```
cost = (inputTokens * inputPer1M / 1_000_000)
     + (outputTokens * outputPer1M / 1_000_000)
     + (cacheReadInputTokens * cacheReadPer1M / 1_000_000)
     + (cacheCreationInputTokens * cacheWritePer1M / 1_000_000)
```

Default pricing (as of early 2025, user-configurable):
- **Opus:** $15 input, $75 output, $1.50 cache read, $18.75 cache write per 1M tokens
- **Sonnet:** $3 input, $15 output, $0.30 cache read, $3.75 cache write per 1M tokens
- **Haiku:** $0.80 input, $4 output, $0.08 cache read, $1 cache write per 1M tokens

## DMG Distribution

- Xcode project with archive → export → create DMG workflow
- DMG contains the `.app` bundle and a symlink to `/Applications` for drag-to-install
- App is code-signed with a Developer ID (or unsigned for personal use)
- No Mac App Store distribution planned initially

## Error Handling

- If `~/.claude/` doesn't exist or is empty: show a friendly "No Claude Code data found" message with guidance
- If `stats-cache.json` is malformed: show last known good state, log error
- If file watcher fails: fall back to refresh-on-open only
- Gracefully handle missing fields in JSON (Claude Code may add/change fields across versions)

## Scope Boundaries

**In scope:**
- Menu bar icon with color thresholds
- Popover with today's stats, model breakdown, trend chart, recent sessions
- Settings for thresholds and pricing
- File watching + refresh on open
- DMG packaging

**Out of scope:**
- Notifications or alerts
- Historical data export
- Multiple account support
- API-based usage fetching
- Windows/Linux support
