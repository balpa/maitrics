import SwiftUI
import MaitricsCore

struct PopoverContentView: View {
    @Bindable var dataManager: ClaudeDataManager
    let settings: AppSettings
    var onSettingsOpen: () -> Void
    var body: some View {
        ZStack {
            VisualEffectBackground()
            if dataManager.statsCache == nil && dataManager.usageData == nil && !dataManager.isLoading {
                EmptyStateView()
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        HeaderView(onSettingsOpen: onSettingsOpen)
                        Divider().opacity(0.06)
                        RateLimitsView(usageData: dataManager.usageData)
                        Divider().opacity(0.06)
                        TodaySummaryView(
                            cost: dataManager.todayEstimatedCost,
                            tokens: dataManager.todayTokens,
                            sessions: dataManager.todaySessionCount
                        )
                        ModelBreakdownView(models: dataManager.modelBreakdown)
                        Divider().opacity(0.06)
                        UsageTrendChartView(
                            allDailyTotals: dataManager.dailyTotals(days: nil)
                        )
                        Divider().opacity(0.06)
                        RecentSessionsView(sessions: dataManager.recentSessions)
                        Divider().opacity(0.06)
                        FooterView(lastRefresh: dataManager.lastRefresh, isWatching: true)
                    }
                }
            }
        }
        .frame(width: 400, height: 700)
        .clipped()
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let wrapper = NSView()
        wrapper.wantsLayer = true

        // Dark opaque base to prevent wallpaper bleed-through
        let bgLayer = CALayer()
        bgLayer.backgroundColor = NSColor(red: 0.08, green: 0.08, blue: 0.12, alpha: 0.92).cgColor
        wrapper.layer = bgLayer

        // Subtle vibrancy on top
        let vibrancy = NSVisualEffectView()
        vibrancy.material = .hudWindow
        vibrancy.blendingMode = .behindWindow
        vibrancy.state = .active
        vibrancy.appearance = NSAppearance(named: .darkAqua)
        vibrancy.alphaValue = 0.3
        vibrancy.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(vibrancy)
        NSLayoutConstraint.activate([
            vibrancy.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            vibrancy.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            vibrancy.topAnchor.constraint(equalTo: wrapper.topAnchor),
            vibrancy.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
        ])

        return wrapper
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
