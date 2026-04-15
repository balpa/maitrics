import SwiftUI
import MaitricsCore

struct TodaySummaryView: View {
    let cost: Double
    let tokens: Int
    let sessions: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Today")
            HStack(spacing: 10) {
                StatCard(value: Formatting.cost(cost), label: "EST. COST",
                         accentColor: Color(red: 74/255, green: 222/255, blue: 128/255))
                StatCard(value: Formatting.tokens(tokens), label: "TOKENS",
                         accentColor: Color(red: 96/255, green: 165/255, blue: 250/255))
                StatCard(value: "\(sessions)", label: "SESSIONS",
                         accentColor: Color(red: 192/255, green: 132/255, blue: 252/255))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

struct StatCard: View {
    let value: String
    let label: String
    let accentColor: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(accentColor)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(Color(white: 0.7))
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.04))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.05), lineWidth: 1))
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
