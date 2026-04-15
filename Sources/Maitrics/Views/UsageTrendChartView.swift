import SwiftUI
import Charts
import MaitricsCore

struct ChartDataPoint: Identifiable {
    let id: Date
    let date: Date
    let tokens: Int
    let isToday: Bool

    init(date: Date, tokens: Int, isToday: Bool) {
        self.id = date
        self.date = date
        self.tokens = tokens
        self.isToday = isToday
    }
}

struct UsageTrendChartView: View {
    let allDailyTotals: [(date: Date, tokens: Int)]
    @State private var selectedRange = 0
    @State private var hoveredDate: Date?

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let tooltipDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()

    private var displayData: [ChartDataPoint] {
        let todayStr = Self.dayFormatter.string(from: Date())
        let filtered: [(date: Date, tokens: Int)]

        switch selectedRange {
        case 0:
            let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date.distantPast
            filtered = allDailyTotals.filter { $0.date >= cutoff }
        case 1:
            let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date.distantPast
            filtered = allDailyTotals.filter { $0.date >= cutoff }
        default:
            filtered = allDailyTotals
        }

        return filtered.map { item in
            ChartDataPoint(
                date: item.date,
                tokens: item.tokens,
                isToday: Self.dayFormatter.string(from: item.date) == todayStr
            )
        }
    }

    private var hoveredItem: ChartDataPoint? {
        guard let hoveredDate else { return nil }
        let hoveredStr = Self.dayFormatter.string(from: hoveredDate)
        return displayData.first { Self.dayFormatter.string(from: $0.date) == hoveredStr }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(text: "Usage Trend")
                Spacer()

                if let item = hoveredItem {
                    Text("\(Self.tooltipDateFormatter.string(from: item.date)) · \(Formatting.tokens(item.tokens))")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(Color(white: 0.6))
                        .transition(.opacity)
                }

                Picker("", selection: $selectedRange) {
                    Text("7d").tag(0)
                    Text("30d").tag(1)
                    Text("All").tag(2)
                }
                .pickerStyle(.segmented)
                .frame(width: 110)
                .scaleEffect(0.8)
            }

            if displayData.isEmpty {
                Text("No data for this period")
                    .font(.system(size: 11))
                    .foregroundColor(Color(white: 0.35))
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                Chart(displayData) { item in
                    BarMark(
                        x: .value("Date", item.date, unit: .day),
                        y: .value("Tokens", item.tokens)
                    )
                    .foregroundStyle(
                        item.isToday
                            ? Color(red: 74/255, green: 222/255, blue: 128/255)
                            : Color(red: 59/255, green: 130/255, blue: 246/255)
                    )
                    .cornerRadius(3)
                    .opacity(hoveredDate == nil || hoveredItem?.date == item.date ? 1 : 0.4)
                }
                .chartXAxis {
                    AxisMarks(values: displayData.map(\.date)) { value in
                        AxisValueLabel(centered: true) {
                            if let date = value.as(Date.self) {
                                Text(xAxisLabel(for: date))
                                    .font(.system(size: 8))
                                    .foregroundColor(Color(white: 0.35))
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisValueLabel {
                            if let intVal = value.as(Int.self) {
                                Text(Formatting.tokens(intVal))
                                    .font(.system(size: 8))
                                    .foregroundColor(Color(white: 0.35))
                            }
                        }
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let location):
                                    if let date: Date = proxy.value(atX: location.x) {
                                        hoveredDate = date
                                    }
                                case .ended:
                                    hoveredDate = nil
                                }
                            }
                    }
                }
                .animation(.easeInOut(duration: 0.15), value: hoveredDate)
                .frame(height: 100)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    private static let dayMonthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    private static let monthYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM ''yy"
        return f
    }()

    private func xAxisLabel(for date: Date) -> String {
        switch selectedRange {
        case 0: return Self.weekdayFormatter.string(from: date)
        case 1: return Self.dayMonthFormatter.string(from: date)
        default: return Self.monthYearFormatter.string(from: date)
        }
    }
}
