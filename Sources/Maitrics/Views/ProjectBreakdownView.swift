import SwiftUI
import MaitricsCore

enum ProjectRange: String, CaseIterable {
    case today = "Today", week = "7d", month = "30d"

    var days: Int {
        switch self {
        case .today: return 1
        case .week: return 7
        case .month: return 30
        }
    }
}

struct ProjectBreakdownView: View {
    let breakdown: (ProjectRange) -> [ProjectUsage]
    @State private var range: ProjectRange = .week
    private let maxRows = 5

    var body: some View {
        let projects = breakdown(range)
        let shown = Array(projects.prefix(maxRows))
        let maxCost = shown.map(\.cost).max() ?? 0

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                SectionLabel(text: "Projects")
                Spacer()
                ChipPicker(options: ProjectRange.allCases, selection: $range, label: \.rawValue)
            }
            .padding(.bottom, 2)

            if shown.isEmpty {
                Text("No project activity")
                    .font(.system(size: 11))
                    .foregroundColor(Color(white: 0.6))
                    .padding(.vertical, 4)
            } else {
                ForEach(shown) { project in
                    ProjectRow(project: project, fraction: maxCost > 0 ? project.cost / maxCost : 0)
                }
                if projects.count > maxRows {
                    Text("+\(projects.count - maxRows) more")
                        .font(.system(size: 9))
                        .foregroundColor(Color(white: 0.5))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

private struct ProjectRow: View {
    let project: ProjectUsage
    let fraction: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(project.name)
                    .font(.system(size: 11))
                    .foregroundColor(Color(white: 0.9))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(project.sessions) session\(project.sessions == 1 ? "" : "s")")
                    .font(.system(size: 9))
                    .foregroundColor(Color(white: 0.55))
                Spacer()
                Text(Formatting.tokens(project.tokens))
                    .font(.system(size: 9))
                    .foregroundColor(Color(white: 0.6))
                Text(Formatting.cost(project.cost))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color(red: 74/255, green: 222/255, blue: 128/255))
                    .frame(minWidth: 44, alignment: .trailing)
            }
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 2)
                    .fill(LinearGradient(colors: [Color(red: 59/255, green: 130/255, blue: 246/255),
                                                  Color(red: 96/255, green: 165/255, blue: 250/255)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: geo.size.width * CGFloat(fraction))
            }
            .frame(height: 3)
            .background(Color.white.opacity(0.06))
            .cornerRadius(2)
        }
    }
}
