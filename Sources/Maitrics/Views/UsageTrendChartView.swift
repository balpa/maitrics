import SwiftUI
import Charts
import MaitricsCore

struct UsageTrendChartView: View {
    let dailyTotals: [(date: Date, tokens: Int)]
    let allDailyTotals: [(date: Date, tokens: Int)]
    @State private var selectedRange = 0

    private var displayData: [(date: Date, tokens: Int)] {
        switch selectedRange {
        case 0:
            let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date.distantPast
            return allDailyTotals.filter { $0.date >= cutoff }
        case 1:
            let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date.distantPast
            return allDailyTotals.filter { $0.date >= cutoff }
        default:
            return allDailyTotals
        }
    }

    private var todayString: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(text: "Usage Trend")
                Spacer()
                Picker("", selection: $selectedRange) {
                    Text("7d").tag(0)
                    Text("30d").tag(1)
                    Text("All").tag(2)
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
                .scaleEffect(0.85)
            }

            Chart(displayData, id: \.date) { item in
                let f = DateFormatter()
                let _ = f.dateFormat = "yyyy-MM-dd"
                let isToday = f.string(from: item.date) == todayString

                BarMark(
                    x: .value("Date", item.date, unit: .day),
                    y: .value("Tokens", item.tokens)
                )
                .foregroundStyle(
                    isToday
                        ? Color(red: 74/255, green: 222/255, blue: 128/255)
                        : Color(red: 59/255, green: 130/255, blue: 246/255)
                )
                .cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                        .foregroundStyle(Color(white: 0.35))
                        .font(.system(size: 8))
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let intVal = value.as(Int.self) {
                            Text(Formatting.tokens(intVal))
                                .font(.system(size: 8))
                                .foregroundColor(Color(white: 0.35))
                        }
                    }
                }
            }
            .frame(height: 100)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}
