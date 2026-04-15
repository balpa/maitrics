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
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .font(.system(size: 11))
                        .foregroundColor(Color(white: 0.35))
                    Text("No OAuth token found")
                        .font(.system(size: 11))
                        .foregroundColor(Color(white: 0.4))
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

    private var barColor: Color {
        if percentage >= 90 { return Color(red: 255/255, green: 85/255, blue: 85/255) }
        if percentage >= 70 { return Color(red: 230/255, green: 200/255, blue: 0/255) }
        if percentage >= 50 { return Color(red: 255/255, green: 176/255, blue: 85/255) }
        return Color(red: 74/255, green: 222/255, blue: 128/255)
    }

    private var pctText: String {
        String(format: "%.0f%%", percentage)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(white: 0.75))
                Text(sublabel)
                    .font(.system(size: 9))
                    .foregroundColor(Color(white: 0.35))
                Spacer()
                Text(pctText)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(barColor)
                if let resetsAt {
                    Text("resets \(Formatting.timeAgo(resetsAt))")
                        .font(.system(size: 9))
                        .foregroundColor(Color(white: 0.3))
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
                                colors: [barColor.opacity(0.8), barColor],
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
