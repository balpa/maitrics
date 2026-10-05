import SwiftUI
import MaitricsCore

struct PopoverContentView: View {
    @Bindable var dataManager: ClaudeDataManager
    let settings: AppSettings
    @Bindable var state: PopoverState
    var onHeightChange: (CGFloat) -> Void = { _ in }
    @State private var showSettings = false
    @State private var dashboardHeight: CGFloat = 700

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
                    SettingsView(settings: settings, apiError: dataManager.apiError, onCostModeChange: { dataManager.refresh() })
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
                        let month = dataManager.usageSummary(days: 30)
                        TodaySummaryView(
                            cost: dataManager.todayEstimatedCost,
                            tokens: dataManager.todayTokens,
                            sessions: dataManager.todaySessionCount,
                            monthCost: month.totalCost,
                            monthTokens: month.totalTokens
                        )
                        DetailsToggle(isExpanded: $state.showDetails)
                        if state.showDetails {
                            ModelBreakdownView(models: dataManager.modelBreakdown)
                            Divider().opacity(0.06)
                            UsageTrendChartView(
                                allDaily: dataManager.dailyUsage(days: nil),
                                hourly: dataManager.hourlyUsage(hours: 24),
                                summary: trendSummary
                            )
                            Divider().opacity(0.06)
                            ProjectBreakdownView(breakdown: { dataManager.projectBreakdown(days: $0.days) })
                            Divider().opacity(0.06)
                            RecentSessionsView(sessions: dataManager.recentSessions)
                        }
                        Divider().opacity(0.06)
                        FooterView(
                            lastRefresh: dataManager.lastRefresh,
                            refreshMode: settings.refreshMode,
                            onRefresh: { dataManager.refresh() }
                        )
                    }
                    .background(GeometryReader { geo in
                        Color.clear.preference(key: ContentHeightKey.self, value: geo.size.height)
                    })
                }
                .onPreferenceChange(ContentHeightKey.self) { height in
                    dashboardHeight = height
                    onHeightChange(popoverHeight)
                }
            }
        }
        .frame(width: 400, height: popoverHeight)
        .clipped()
        .focusable(false)
    }

    private var popoverHeight: CGFloat {
        min(dashboardHeight, (NSScreen.main?.visibleFrame.height ?? 800) - 40)
    }

    private func trendSummary(_ range: TrendRange) -> UsageSummary {
        guard range == .day else { return dataManager.usageSummary(days: range.days) }
        let hourly = dataManager.hourlyUsage(hours: 24)
        var summary = UsageSummary()
        summary.totalCost = hourly.reduce(0) { $0 + $1.cost }
        summary.totalTokens = hourly.reduce(0) { $0 + $1.tokens }
        return summary
    }
}

@Observable
final class PopoverState {
    var showDetails = false
}

private struct DetailsToggle: View {
    @Binding var isExpanded: Bool

    var body: some View {
        Button(action: { isExpanded.toggle() }) {
            HStack(spacing: 6) {
                Text(isExpanded ? "Hide details" : "Show details")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(white: 0.85))
                Text("Models · Trend · Projects · Sessions")
                    .font(.system(size: 10))
                    .foregroundColor(Color(white: 0.5))
                Spacer()
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color(white: 0.6))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.03))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
