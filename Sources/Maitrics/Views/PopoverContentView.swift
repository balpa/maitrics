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
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
