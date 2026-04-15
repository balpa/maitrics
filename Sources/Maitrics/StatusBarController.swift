import AppKit
import SwiftUI
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
        updateIcon()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "gauge.with.dots.needle.33percent", accessibilityDescription: "Maitrics")
            button.image?.size = NSSize(width: 18, height: 18)
            button.action = #selector(togglePopover)
            button.target = self
        }
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
            self?.updateIcon()
        }
        fileWatcher?.start()
    }

    func updateIcon() {
        guard let button = statusItem.button else { return }
        let color: NSColor
        switch dataManager.iconThresholdLevel {
        case .green: color = NSColor(red: 74/255, green: 222/255, blue: 128/255, alpha: 1)
        case .yellow: color = NSColor(red: 250/255, green: 204/255, blue: 21/255, alpha: 1)
        case .red: color = NSColor(red: 248/255, green: 113/255, blue: 113/255, alpha: 1)
        }
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        var image = NSImage(systemSymbolName: "gauge.with.dots.needle.33percent", accessibilityDescription: "Maitrics")
        image = image?.withSymbolConfiguration(config)
        let tinted = NSImage(size: image?.size ?? NSSize(width: 18, height: 18), flipped: false) { rect in
            image?.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        tinted.isTemplate = false
        button.image = tinted
    }

    @objc private func togglePopover() {
        if popover.isShown {
            closePopover()
        } else {
            dataManager.refresh()
            updateIcon()
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
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 500),
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
