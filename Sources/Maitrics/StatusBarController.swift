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

            // "S:" label
            text.append(NSAttributedString(string: "S:", attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium),
                .foregroundColor: NSColor(white: 0.55, alpha: 1)
            ]))
            // Session percentage
            text.append(NSAttributedString(string: "\(sessionPct)%", attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: colorForPct(sessionPct)
            ]))

            // separator
            text.append(NSAttributedString(string: " ", attributes: [
                .font: NSFont.systemFont(ofSize: 10)
            ]))

            // "W:" label
            text.append(NSAttributedString(string: "W:", attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium),
                .foregroundColor: NSColor(white: 0.55, alpha: 1)
            ]))
            // Weekly percentage
            text.append(NSAttributedString(string: "\(weeklyPct)%", attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: colorForPct(weeklyPct)
            ]))

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

    private func colorForPct(_ pct: Int) -> NSColor {
        if pct >= 90 { return NSColor(red: 255/255, green: 85/255, blue: 85/255, alpha: 1) }
        if pct >= 70 { return NSColor(red: 230/255, green: 200/255, blue: 0/255, alpha: 1) }
        if pct >= 50 { return NSColor(red: 255/255, green: 176/255, blue: 85/255, alpha: 1) }
        return NSColor(red: 74/255, green: 222/255, blue: 128/255, alpha: 1)
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
