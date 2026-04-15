import AppKit
import SwiftUI
import Observation
import MaitricsCore

final class StatusBarController {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var fileWatcher: FileWatcher?
    private var eventMonitor: Any?
    private var settingsWindow: NSWindow?
    let dataManager: ClaudeDataManager
    let settings: AppSettings

    init() {
        self.settings = AppSettings()
        self.dataManager = ClaudeDataManager(settings: settings)
        setupStatusItem()
        setupPopover()
        setupFileWatcher()
        dataManager.refresh()
        updateStatusText()
        observeDataChanges()
    }

    /// Re-registers on every change so the status bar stays in sync with async refreshes
    private func observeDataChanges() {
        withObservationTracking {
            _ = dataManager.usageData
            _ = dataManager.lastRefresh
        } onChange: {
            DispatchQueue.main.async { [weak self] in
                self?.updateStatusText()
                self?.observeDataChanges()
            }
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.action = #selector(togglePopover)
            button.target = self
        }
        updateStatusText()
    }

    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 420, height: 580)
        popover.behavior = .transient
        popover.animates = true
        let hostingController = NSHostingController(
            rootView: PopoverContentView(
                dataManager: dataManager,
                settings: settings,
                onSettingsOpen: { [weak self] in self?.openSettings() }
            )
            .preferredColorScheme(.dark)
        )
        popover.contentViewController = hostingController
    }

    private func setupFileWatcher() {
        fileWatcher = FileWatcher(path: settings.statsCachePath.path) { [weak self] in
            self?.dataManager.refresh()
            self?.updateStatusText()
        }
        fileWatcher?.start()
    }

    func updateStatusText() {
        guard let button = statusItem.button else { return }

        if let usage = dataManager.usageData {
            let sessionPct = Int(usage.fiveHour.utilization)
            let weeklyPct = Int(usage.sevenDay.utilization)

            let text = NSMutableAttributedString()
            let digitFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            let dimColor = NSColor(white: 0.50, alpha: 1)

            // Colored dot for session
            text.append(coloredDot(for: sessionPct, size: 6))
            text.append(str(" ", font: digitFont, color: dimColor))

            // Session percentage
            text.append(str("\(sessionPct)%", font: digitFont, color: colorForPct(sessionPct)))

            // Separator
            text.append(str("  ", font: digitFont, color: dimColor))

            // Colored dot for weekly
            text.append(coloredDot(for: weeklyPct, size: 6))
            text.append(str(" ", font: digitFont, color: dimColor))

            // Weekly percentage
            text.append(str("\(weeklyPct)%", font: digitFont, color: colorForPct(weeklyPct)))

            button.image = nil
            button.attributedTitle = text
        } else {
            // Fallback: show icon when no API data
            button.attributedTitle = NSAttributedString(string: "")
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            let image = NSImage(systemSymbolName: "gauge.with.dots.needle.33percent", accessibilityDescription: "Maitrics")?.withSymbolConfiguration(config)
            image?.isTemplate = true
            button.image = image
        }
    }

    private func str(_ text: String, font: NSFont, color: NSColor) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
    }

    private func coloredDot(for pct: Int, size: CGFloat) -> NSAttributedString {
        let dot = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let color = self.colorForPct(pct)
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)).fill()
            return true
        }
        let attachment = NSTextAttachment()
        attachment.image = dot
        // Center the dot vertically relative to the text
        attachment.bounds = CGRect(x: 0, y: 1, width: size, height: size)
        return NSAttributedString(attachment: attachment)
    }

    private func colorForPct(_ pct: Int) -> NSColor {
        if pct >= 90 { return NSColor(red: 1.0, green: 0.33, blue: 0.33, alpha: 1) }     // red
        if pct >= 70 { return NSColor(red: 1.0, green: 0.78, blue: 0.0, alpha: 1) }      // yellow
        if pct >= 50 { return NSColor(red: 1.0, green: 0.69, blue: 0.33, alpha: 1) }     // orange
        return NSColor(red: 0.29, green: 0.87, blue: 0.50, alpha: 1)                       // green
    }

    @objc private func togglePopover() {
        if popover.isShown {
            closePopover()
        } else {
            dataManager.refresh()
            updateStatusText()
            if let button = statusItem.button {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
            eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.closePopover()
            }
        }
    }

    private func closePopover() {
        popover.performClose(nil)
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    private func openSettings() {
        closePopover()
        settingsWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        settingsWindow?.title = "Maitrics Settings"
        settingsWindow?.center()
        settingsWindow?.appearance = NSAppearance(named: .darkAqua)
        settingsWindow?.contentViewController = NSHostingController(rootView: SettingsView(settings: settings))
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
