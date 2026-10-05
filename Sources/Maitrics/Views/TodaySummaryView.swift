import SwiftUI
import MaitricsCore

struct TodaySummaryView: View {
    let cost: Double
    let tokens: Int
    let sessions: Int
    let monthCost: Double
    let monthTokens: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel(text: "Usage")
                Spacer()
                Text("\(sessions) session\(sessions == 1 ? "" : "s") today")
                    .font(.system(size: 10))
                    .foregroundColor(Color(white: 0.55))
            }
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
                GridRow {
                    SummaryValue(label: "Today", value: Formatting.cost(cost))
                    SummaryValue(label: "Last 30 days cost", value: Formatting.cost(monthCost))
                }
                GridRow {
                    SummaryValue(label: "Today tokens", value: Formatting.tokens(tokens))
                    SummaryValue(label: "Last 30 days tokens", value: Formatting.tokens(monthTokens))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

private struct SummaryValue: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(white: 0.6))
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(Color(white: 0.6))
            .tracking(1)
    }
}
