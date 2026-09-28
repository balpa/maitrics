import SwiftUI
import Charts
import MaitricsCore

enum TrendRange: String, CaseIterable {
    case day = "24h", week = "7d", month = "30d", all = "All"

    var days: Int? {
        switch self {
        case .day: return 1
        case .week: return 7
        case .month: return 30
        case .all: return nil
        }
    }
}

enum TrendMetric: String, CaseIterable {
    case tokens = "Tokens", cost = "Cost"
}

struct UsageTrendChartView: View {
    let allDaily: [UsagePoint]
    let hourly: [UsagePoint]
    let summary: (TrendRange) -> UsageSummary
    @State private var range: TrendRange = .week
    @State private var metric: TrendMetric = .tokens
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

    private static let tooltipHourFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, HH:00"
        return f
    }()

    private var isHourly: Bool { range == .day }

    private var displayData: [UsagePoint] {
        let calendar = Calendar.current
        switch range {
        case .day:
            return hourly
        case .week:
            // Fill all 7 days so every weekday label shows
            let byDate = Dictionary(allDaily.map { (Self.dayFormatter.string(from: $0.date), $0) }, uniquingKeysWith: { $1 })
            return (0..<7).reversed().compactMap { i in
                guard let date = calendar.date(byAdding: .day, value: -i, to: calendar.startOfDay(for: Date())) else { return nil }
                return byDate[Self.dayFormatter.string(from: date)] ?? UsagePoint(date: date, tokens: 0, cost: 0)
            }
        case .month:
            let cutoff = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: Date())) ?? .distantPast
            return allDaily.filter { $0.date >= cutoff }
        case .all:
            return allDaily
        }
    }

    private func value(_ point: UsagePoint) -> Double {
        metric == .tokens ? Double(point.tokens) : point.cost
    }

    private func isCurrent(_ date: Date) -> Bool {
        Calendar.current.isDate(date, equalTo: Date(), toGranularity: isHourly ? .hour : .day)
    }

    private var hoveredItem: UsagePoint? {
        guard let hoveredDate else { return nil }
        return displayData.min(by: {
            abs($0.date.timeIntervalSince(hoveredDate)) < abs($1.date.timeIntervalSince(hoveredDate))
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                SectionLabel(text: "Usage Trend")
                ChipPicker(options: TrendRange.allCases, selection: $range, label: \.rawValue)
                Spacer()
                ChipPicker(options: TrendMetric.allCases, selection: $metric, label: \.rawValue)
            }

            if displayData.allSatisfy({ value($0) == 0 }) {
                Text("No data for this period")
                    .font(.system(size: 11))
                    .foregroundColor(Color(white: 0.6))
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                chart
            }

            summaryLine
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .padding(.vertical, 14)
    }

    private var chart: some View {
        Chart(displayData) { item in
            BarMark(
                x: .value("Date", item.date, unit: isHourly ? .hour : .day),
                y: .value(metric.rawValue, value(item))
            )
            .foregroundStyle(
                isCurrent(item.date)
                    ? Color(red: 74/255, green: 222/255, blue: 128/255)
                    : Color(red: 59/255, green: 130/255, blue: 246/255)
            )
            .cornerRadius(isHourly ? 2 : 3)
            .opacity(hoveredItem == nil || hoveredItem?.id == item.id ? 1 : 0.4)
        }
        .chartXAxis {
            AxisMarks(values: xAxisDates) { value in
                AxisValueLabel(anchor: .top) {
                    if let date = value.as(Date.self) {
                        Text(xAxisLabel(for: date))
                            .font(.system(size: 8))
                            .foregroundColor(isCurrent(date) ? Color(red: 74/255, green: 222/255, blue: 128/255) : Color(white: 0.6))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(metric == .tokens ? Formatting.tokens(Int(v)) : Formatting.cost(v))
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
                                let plotX = hoverLocation.x - geo[plotFrame].origin.x
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

    private var summaryLine: some View {
        HStack(spacing: 4) {
            if let item = hoveredItem {
                Text((isHourly ? Self.tooltipHourFormatter : Self.tooltipDateFormatter).string(from: item.date))
                    .foregroundColor(Color(white: 0.75))
                Text("·")
                Text(Formatting.tokens(item.tokens))
                Text("·")
                Text(Formatting.cost(item.cost))
            } else {
                let s = summary(range)
                Text(Formatting.cost(s.totalCost))
                    .fontWeight(.semibold)
                    .foregroundColor(Color(red: 74/255, green: 222/255, blue: 128/255))
                Text("·")
                Text("\(Formatting.tokens(s.totalTokens)) tokens")
                if range != .day {
                    Text("·")
                    Text("\(Formatting.cost(s.averageDailyCost))/day")
                }
                if let top = s.topModel {
                    Text("·")
                    Text(String(format: "%@ %.0f%%", top, s.topModelShare * 100))
                }
            }
            Spacer()
        }
        .font(.system(size: 9, weight: .medium))
        .foregroundColor(Color(white: 0.6))
        .lineLimit(1)
    }

    private static let hourFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:00"
        return f
    }()

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

    /// Select which dates get x-axis labels to avoid overlapping.
    /// A label is at the middle of its bar. A `centered` label needs a next tick, so the last label was not shown.
    private var xAxisDates: [Date] {
        let dates = displayData.map(\.date)
        guard !dates.isEmpty else { return [] }
        let step = range == .week ? 1 : max(1, dates.count / 6)
        let halfBar: TimeInterval = isHourly ? 1800 : 43200
        return dates.enumerated().compactMap { i, d in i % step == 0 ? d.addingTimeInterval(halfBar) : nil }
    }

    private func xAxisLabel(for date: Date) -> String {
        switch range {
        case .day: return Self.hourFormatter.string(from: date)
        case .week: return Self.weekdayFormatter.string(from: date)
        case .month: return Self.dayMonthFormatter.string(from: date)
        case .all: return Self.monthYearFormatter.string(from: date)
        }
    }
}

struct ChipPicker<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> String

    init(options: [Option], selection: Binding<Option>, label: @escaping (Option) -> String) {
        self.options = options
        self._selection = selection
        self.label = label
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button(action: { selection = option }) {
                    Text(label(option))
                        .font(.system(size: 9, weight: selected ? .bold : .regular))
                        .foregroundColor(selected ? .white : Color(white: 0.65))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(selected ? Color.blue.opacity(0.6) : Color.clear)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
        }
    }
}
