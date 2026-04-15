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
        let calendar = Calendar.current
        let filtered: [(date: Date, tokens: Int)]

        switch selectedRange {
        case 0:
            // 7d view: fill all 7 days so every weekday label shows
            let dataByDate = Dictionary(
                allDailyTotals.map { (Self.dayFormatter.string(from: $0.date), $0.tokens) },
                uniquingKeysWith: { $1 }
            )
            var days: [(date: Date, tokens: Int)] = []
            for i in (0..<7).reversed() {
                if let date = calendar.date(byAdding: .day, value: -i, to: calendar.startOfDay(for: Date())) {
                    let key = Self.dayFormatter.string(from: date)
                    days.append((date: date, tokens: dataByDate[key] ?? 0))
                }
            }
            filtered = days
        case 1:
            let cutoff = calendar.date(byAdding: .day, value: -30, to: Date()) ?? Date.distantPast
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
        // Snap to the closest data point by calendar day
        let cal = Calendar.current
        return displayData.min(by: {
            abs(cal.startOfDay(for: $0.date).timeIntervalSince(cal.startOfDay(for: hoveredDate)))
            < abs(cal.startOfDay(for: $1.date).timeIntervalSince(cal.startOfDay(for: hoveredDate)))
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                SectionLabel(text: "Usage Trend")

                HStack(spacing: 2) {
                    ForEach(["7d", "30d", "All"], id: \.self) { label in
                        let tag = label == "7d" ? 0 : label == "30d" ? 1 : 2
                        Button(action: { selectedRange = tag }) {
                            Text(label)
                                .font(.system(size: 9, weight: selectedRange == tag ? .bold : .regular))
                                .foregroundColor(selectedRange == tag ? .white : Color(white: 0.65))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(selectedRange == tag ? Color.blue.opacity(0.6) : Color.clear)
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                    }
                }

                Spacer()

                if let item = hoveredItem {
                    Text("\(Self.tooltipDateFormatter.string(from: item.date)) · \(Formatting.tokens(item.tokens))")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(Color(white: 0.75))
                        .transition(.opacity)
                }
            }

            if displayData.isEmpty {
                Text("No data for this period")
                    .font(.system(size: 11))
                    .foregroundColor(Color(white: 0.6))
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
                    .opacity(hoveredItem == nil || hoveredItem?.id == item.id ? 1 : 0.4)
                }
                .chartXAxis {
                    AxisMarks(values: xAxisDates) { value in
                        AxisValueLabel(centered: true) {
                            if let date = value.as(Date.self) {
                                Text(xAxisLabel(for: date))
                                    .font(.system(size: 8))
                                    .foregroundColor(
                                        Self.dayFormatter.string(from: date) == Self.dayFormatter.string(from: Date())
                                            ? Color(red: 74/255, green: 222/255, blue: 128/255)
                                            : Color(white: 0.6)
                                    )
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
                                    .foregroundColor(Color(white: 0.6))
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
                                case .active(let hoverLocation):
                                    // Subtract plot area origin to account for y-axis label offset
                                    if let plotFrame = proxy.plotFrame {
                                        let origin = geo[plotFrame].origin
                                        let plotX = hoverLocation.x - origin.x
                                        if let date: Date = proxy.value(atX: plotX) {
                                            hoveredDate = date
                                        }
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
        .padding(.leading, 16)
        .padding(.trailing, 12)
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

    /// Select which dates get x-axis labels to avoid overlapping
    private var xAxisDates: [Date] {
        let dates = displayData.map(\.date)
        guard !dates.isEmpty else { return [] }
        let maxLabels = 6

        switch selectedRange {
        case 0:
            return dates // 7 days — show all
        case 1:
            // 30d — show evenly spaced labels
            let step = max(1, dates.count / maxLabels)
            return dates.enumerated().compactMap { i, d in i % step == 0 ? d : nil }
        default:
            // All — show evenly spaced labels
            let step = max(1, dates.count / maxLabels)
            return dates.enumerated().compactMap { i, d in i % step == 0 ? d : nil
            }
        }
    }

    private func xAxisLabel(for date: Date) -> String {
        switch selectedRange {
        case 0: return Self.weekdayFormatter.string(from: date)
        case 1: return Self.dayMonthFormatter.string(from: date)
        default: return Self.monthYearFormatter.string(from: date)
        }
    }
}
