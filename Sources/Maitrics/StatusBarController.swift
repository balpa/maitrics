import AppKit
import SwiftUI
import Observation
import MaitricsCore

final class StatusBarController {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var fileWatcher: FileWatcher?
    private var eventMonitor: Any?
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
        popover.contentSize = NSSize(width: 400, height: 700)
        popover.behavior = .transient
        popover.animates = true
        let hostingController = NSHostingController(
            rootView: PopoverContentView(
                dataManager: dataManager,
                settings: settings
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
            let sessionPct = usage.fiveHour.utilization
            let weeklyPct = usage.sevenDay.utilization

            let barImage = renderBarImage(sessionPct: sessionPct, weeklyPct: weeklyPct)
            button.attributedTitle = NSAttributedString(string: "")
            button.image = barImage
            button.imagePosition = .imageOnly
        } else {
            button.attributedTitle = NSAttributedString(string: "")
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            let image = NSImage(systemSymbolName: "gauge.with.dots.needle.33percent", accessibilityDescription: "Maitrics")?.withSymbolConfiguration(config)
            image?.isTemplate = true
            button.image = image
        }
    }

    private func renderBarImage(sessionPct: Double, weeklyPct: Double) -> NSImage {
        let barWidth: CGFloat = 50
        let barHeight: CGFloat = 5
        let spacing: CGFloat = 3
        let labelWidth: CGFloat = 11
        let totalWidth = labelWidth + 2 + barWidth
        let totalHeight = barHeight * 2 + spacing
        let cornerRadius: CGFloat = 2.5

        let image = NSImage(size: NSSize(width: totalWidth, height: totalHeight), flipped: false) { bounds in
            let topBarY = spacing + barHeight  // session bar (top)
            let bottomBarY: CGFloat = 0        // weekly bar (bottom)

            // "S" and "W" labels — white with dark outline for visibility
            let labelFont = NSFont.systemFont(ofSize: 8, weight: .heavy)
            let outlineAttrs: [NSAttributedString.Key: Any] = [
                .font: labelFont,
                .foregroundColor: NSColor.black,
                .strokeColor: NSColor.black,
                .strokeWidth: -3.0
            ]
            let labelAttrs: [NSAttributedString.Key: Any] = [
                .font: labelFont,
                .foregroundColor: NSColor.white
            ]
            // Draw outline first, then white text on top
            NSString("S").draw(at: NSPoint(x: 0, y: topBarY - 4.5), withAttributes: outlineAttrs)
            NSString("S").draw(at: NSPoint(x: 0, y: topBarY - 4.5), withAttributes: labelAttrs)
            NSString("W").draw(at: NSPoint(x: 0, y: bottomBarY - 4.5), withAttributes: outlineAttrs)
            NSString("W").draw(at: NSPoint(x: 0, y: bottomBarY - 4.5), withAttributes: labelAttrs)

            let barX = labelWidth + 2

            // Session bar background
            let sessionBg = NSBezierPath(roundedRect: NSRect(x: barX, y: topBarY, width: barWidth, height: barHeight), xRadius: cornerRadius, yRadius: cornerRadius)
            NSColor(white: 0.3, alpha: 0.4).setFill()
            sessionBg.fill()

            // Session bar fill
            let sessionFillWidth = barWidth * min(CGFloat(sessionPct) / 100, 1)
            if sessionFillWidth > 0 {
                let sessionFill = NSBezierPath(roundedRect: NSRect(x: barX, y: topBarY, width: sessionFillWidth, height: barHeight), xRadius: cornerRadius, yRadius: cornerRadius)
                self.gradientForPct(sessionPct, width: sessionFillWidth, height: barHeight).draw(in: sessionFill, angle: 0)
            }

            // Weekly bar background
            let weeklyBg = NSBezierPath(roundedRect: NSRect(x: barX, y: bottomBarY, width: barWidth, height: barHeight), xRadius: cornerRadius, yRadius: cornerRadius)
            NSColor(white: 0.3, alpha: 0.4).setFill()
            weeklyBg.fill()

            // Weekly bar fill
            let weeklyFillWidth = barWidth * min(CGFloat(weeklyPct) / 100, 1)
            if weeklyFillWidth > 0 {
                let weeklyFill = NSBezierPath(roundedRect: NSRect(x: barX, y: bottomBarY, width: weeklyFillWidth, height: barHeight), xRadius: cornerRadius, yRadius: cornerRadius)
                self.gradientForPct(weeklyPct, width: weeklyFillWidth, height: barHeight).draw(in: weeklyFill, angle: 0)
            }

            return true
        }
        image.isTemplate = false
        return image
    }

    private func gradientForPct(_ pct: Double, width: CGFloat, height: CGFloat) -> NSGradient {
        // Gradient goes from green → yellow → orange → red based on the fill percentage
        if pct >= 90 {
            return NSGradient(colors: [
                NSColor(red: 1.0, green: 0.55, blue: 0.0, alpha: 1),   // orange
                NSColor(red: 1.0, green: 0.25, blue: 0.25, alpha: 1)   // red
            ])!
        } else if pct >= 70 {
            return NSGradient(colors: [
                NSColor(red: 0.9, green: 0.8, blue: 0.0, alpha: 1),    // yellow
                NSColor(red: 1.0, green: 0.55, blue: 0.0, alpha: 1)    // orange
            ])!
        } else if pct >= 50 {
            return NSGradient(colors: [
                NSColor(red: 0.29, green: 0.87, blue: 0.50, alpha: 1), // green
                NSColor(red: 0.9, green: 0.8, blue: 0.0, alpha: 1)    // yellow
            ])!
        }
        return NSGradient(colors: [
            NSColor(red: 0.2, green: 0.75, blue: 0.45, alpha: 1),      // darker green
            NSColor(red: 0.29, green: 0.87, blue: 0.50, alpha: 1)      // green
        ])!
    }

    @objc private func togglePopover() {
        if popover.isShown {
            closePopover()
        } else {
            dataManager.refresh()
            updateStatusText()
            if let button = statusItem.button {
                // Shift anchor leftward so the popover doesn't clip at the right screen edge
                var rect = button.bounds
                rect.origin.x -= 60
                popover.show(relativeTo: rect, of: button, preferredEdge: .minY)
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

}
