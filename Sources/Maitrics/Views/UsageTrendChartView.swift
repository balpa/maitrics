import SwiftUI
import Charts
import MaitricsCore

struct UsageTrendChartView: View {
    let allDailyTotals: [(date: Date, tokens: Int)]
    @State private var selectedRange = 0

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

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
        Self.dayFormatter.string(from: Date())
    }

    private var xAxisFormat: Date.FormatStyle {
        switch selectedRange {
        case 0: return .dateTime.weekday(.abbreviated)
        case 1: return .dateTime.day().month(.abbreviated)
        default: return .dateTime.month(.abbreviated).year(.twoDigits)
        }
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

            if displayData.isEmpty {
                Text("No data for this period")
                    .font(.system(size: 11))
                    .foregroundColor(Color(white: 0.35))
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                Chart(displayData, id: \.date) { item in
                    let isToday = Self.dayFormatter.string(from: item.date) == todayString

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
                    AxisMarks(values: .automatic) { _ in
                        AxisValueLabel(format: xAxisFormat)
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
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}
