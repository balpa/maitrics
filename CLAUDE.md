# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Maitrics is a native macOS menu bar app (Swift + SwiftUI) that displays Claude Code CLI usage data. It reads from `~/.claude/` local files and presents usage stats in a modern dark popover dashboard.

## Build & Run

```bash
# Build from command line
xcodebuild -project Maitrics.xcodeproj -scheme Maitrics -configuration Debug build

# Build release
xcodebuild -project Maitrics.xcodeproj -scheme Maitrics -configuration Release build

# Run after build
open build/Debug/Maitrics.app
# or
open build/Release/Maitrics.app
```

## Architecture

- **Target:** macOS 13+ (Ventura), menu bar only (`LSUIElement = true`)
- **UI:** SwiftUI views hosted in an `NSPopover` attached to `NSStatusItem`
- **Charts:** Swift Charts framework
- **Data:** Reads `~/.claude/stats-cache.json` and per-project `sessions-index.json` files
- **Reactivity:** `@Observable` data manager + FSEvents file watcher on `~/.claude/`

### Key Components
- `MaitricsApp` — App entry point, creates StatusBarController
- `StatusBarController` — Owns NSStatusItem + NSPopover, manages icon color
- `ClaudeDataManager` — Parses Claude data files, publishes observable state
- `FileWatcher` — Watches ~/.claude/ for changes via DispatchSource/FSEvents

## Git Rules

- **Never include Co-Authored-By lines in commits**
- **Never mention Claude, AI, or LLM in commit messages**
- Commit messages should be concise and written in first person as if the repo owner wrote them
- Use conventional style: lowercase, imperative mood (e.g., "add settings view", "fix token parsing")
