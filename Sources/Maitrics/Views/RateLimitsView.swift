import SwiftUI
import MaitricsCore

struct RateLimitsView: View {
    let usageData: UsageData?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Rate Limits")
                .padding(.bottom, 2)

            if let usage = usageData {
                UsageBarRow(
                    label: "Session",
                    sublabel: "5-hour window",
                    percentage: usage.fiveHour.utilization,
                    resetsAt: usage.fiveHour.resetsAt
                )
                UsageBarRow(
                    label: "Weekly",
                    sublabel: "7-day window",
                    percentage: usage.sevenDay.utilization,
                    resetsAt: usage.sevenDay.resetsAt
                )

                // Per-model quotas (if available)
                if usage.sevenDayOpus != nil || usage.sevenDaySonnet != nil {
                    Divider().opacity(0.06).padding(.vertical, 4)

                    if let opus = usage.sevenDayOpus {
                        UsageBarRow(
                            label: "Opus",
                            sublabel: "weekly",
                            percentage: opus.utilization,
                            resetsAt: opus.resetsAt,
                            barColors: (Color(red: 249/255, green: 115/255, blue: 22/255).opacity(0.8),
                                        Color(red: 249/255, green: 115/255, blue: 22/255))
                        )
                    }
                    if let sonnet = usage.sevenDaySonnet {
                        UsageBarRow(
                            label: "Sonnet",
                            sublabel: "weekly",
                            percentage: sonnet.utilization,
                            resetsAt: sonnet.resetsAt,
                            barColors: (Color(red: 59/255, green: 130/255, blue: 246/255).opacity(0.8),
                                        Color(red: 59/255, green: 130/255, blue: 246/255))
                        )
                    }
                }

                // Extra usage credits
                if let extra = usage.extraUsage, extra.isEnabled {
                    Divider().opacity(0.06).padding(.vertical, 4)
                    HStack {
                        Text("Extra Credits")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(white: 0.85))
                        Spacer()
                        if let used = extra.usedCredits, let limit = extra.monthlyLimit {
                            Text(String(format: "$%.2f / $%.2f", used, limit))
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(Color(red: 192/255, green: 132/255, blue: 252/255))
                        }
                    }
                    if let pct = extra.utilization {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.white.opacity(0.06))
                                    .frame(height: 6)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color(red: 192/255, green: 132/255, blue: 252/255))
                                    .frame(width: geo.size.width * min(CGFloat(pct) / 100, 1), height: 6)
                            }
                        }
                        .frame(height: 6)
                    }
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .font(.system(size: 11))
                        .foregroundColor(Color(white: 0.6))
                    Text("No OAuth token found")
                        .font(.system(size: 11))
                        .foregroundColor(Color(white: 0.65))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

struct UsageBarRow: View {
    let label: String
    let sublabel: String
    let percentage: Double
    let resetsAt: Date?
    var barColors: (Color, Color)? = nil

    private var barColor: Color {
        if percentage >= 90 { return Color(red: 255/255, green: 85/255, blue: 85/255) }
        if percentage >= 70 { return Color(red: 230/255, green: 200/255, blue: 0/255) }
        if percentage >= 50 { return Color(red: 255/255, green: 176/255, blue: 85/255) }
        return Color(red: 74/255, green: 222/255, blue: 128/255)
    }

    private var resolvedBarColors: (Color, Color) {
        barColors ?? (barColor.opacity(0.8), barColor)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(white: 0.85))
                Text(sublabel)
                    .font(.system(size: 9))
                    .foregroundColor(Color(white: 0.6))
                Spacer()
                Text(String(format: "%.0f%%", percentage))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(barColors != nil ? barColors!.1 : barColor)
                if let resetsAt {
                    Text("resets in \(Formatting.timeUntil(resetsAt))")
                        .font(.system(size: 9))
                        .foregroundColor(Color(white: 0.55))
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            LinearGradient(
                                colors: [resolvedBarColors.0, resolvedBarColors.1],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * min(CGFloat(percentage) / 100, 1), height: 6)
                }
            }
            .frame(height: 6)
        }
    }
}
