# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Maitrics is a native macOS menu bar app (Swift + SwiftUI) that displays Claude Code CLI usage data. It reads from `~/.claude/` local files and presents usage stats in a modern dark popover dashboard.

## Build & Run

```bash
# Build debug
swift build

# Build release + .app bundle
Scripts/build-app.sh release

# Run the app
open dist/Maitrics.app

# Run tests (requires Xcode — not just CommandLineTools)
swift test

# Create DMG installer
Scripts/create-dmg.sh 0.1.0
```

## Architecture

- **Target:** macOS 14+ (Sonoma), menu bar only (`LSUIElement = true`)
- **Build System:** Swift Package Manager (Package.swift)
- **UI:** SwiftUI views hosted in an `NSPopover` attached to `NSStatusItem`
- **Charts:** Swift Charts framework
- **Data:** Reads `~/.claude/stats-cache.json` and per-project `sessions-index.json` files
- **Reactivity:** `@Observable` data manager + DispatchSource file watcher on `~/.claude/stats-cache.json`

### Two targets
- `MaitricsCore` (library) — all testable business logic: JSON parsing, cost calculation, data management, file watching, formatting
- `Maitrics` (executable) — AppKit menu bar controller + SwiftUI views

### Key Components
- `MaitricsApp` — App entry point with `@NSApplicationDelegateAdaptor`, creates StatusBarController
- `StatusBarController` — Owns NSStatusItem + NSPopover, manages icon color thresholds, file watcher
- `ClaudeDataManager` (`@Observable`) — Orchestrates all data parsing, async refresh on background thread
- `CostCalculator` — Estimates costs from token counts using configurable per-model pricing
- `SessionDiscovery` — Scans `~/.claude/projects/` for sessions (index-based or JSONL fallback)
- `FileWatcher` — DispatchSource-based monitoring of stats-cache.json with parent-dir fallback

## Git Rules

- **Never include Co-Authored-By lines in commits**
- **Never mention Claude, AI, or LLM in commit messages**
- Commit messages should be concise and written in first person as if the repo owner wrote them
- Use conventional style: lowercase, imperative mood (e.g., "add settings view", "fix token parsing")
