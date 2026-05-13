import SwiftUI
import MaitricsCore

struct PopoverContentView: View {
    @Bindable var dataManager: ClaudeDataManager
    let settings: AppSettings
    @State private var showSettings = false

    var body: some View {
        ZStack {
            VisualEffectBackground()

            if dataManager.statsCache == nil && dataManager.recentSessions.isEmpty && !dataManager.isLoading {
                EmptyStateView()
            } else if showSettings {
                VStack(spacing: 0) {
                    HeaderView(
                        profileData: dataManager.profileData,
                        showSettings: true,
                        isLoading: dataManager.isLoading,
                        onToggleSettings: { showSettings = false }
                    )
                    Divider().opacity(0.06)
                    SettingsView(settings: settings)
                }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        HeaderView(
                            profileData: dataManager.profileData,
                            showSettings: false,
                            isLoading: dataManager.isLoading,
                            onToggleSettings: { showSettings = true }
                        )
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
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
        .clipped()
        .focusable(false)
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(red: 0.07, green: 0.07, blue: 0.11, alpha: 1.0).cgColor
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
