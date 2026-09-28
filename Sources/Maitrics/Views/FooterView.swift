import SwiftUI
import MaitricsCore

struct FooterView: View {
    let lastRefresh: Date?
    let refreshMode: RefreshMode
    let onRefresh: () -> Void

    var body: some View {
        HStack {
            HStack(spacing: 4) {
                Circle()
                    .fill(refreshMode == .manual ? Color(white: 0.55) : Color(red: 74/255, green: 222/255, blue: 128/255))
                    .frame(width: 5, height: 5)
                Text(refreshLabel)
                    .font(.system(size: 9))
                    .foregroundColor(Color(white: 0.55))
            }

            Spacer()

            Button(action: onRefresh) {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.clockwise")
                    Text("Last: \(lastRefreshText)")
                }
            }
            .buttonStyle(.plain)
            .focusable(false)
            .font(.system(size: 9))
            .foregroundColor(Color(white: 0.55))
            .help("Refresh now")

            Text("·")
                .font(.system(size: 9))
                .foregroundColor(Color(white: 0.5))
                .padding(.horizontal, 2)

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(Color(red: 255/255, green: 85/255, blue: 85/255))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private var refreshLabel: String {
        switch refreshMode {
        case .adaptive: return "Auto-refresh · adaptive"
        case .manual: return "Auto-refresh off"
        default: return "Auto-refresh · every \(refreshMode.rawValue)"
        }
    }

    private var lastRefreshText: String {
        guard let lastRefresh else { return "never" }
        let seconds = Date().timeIntervalSince(lastRefresh)
        if seconds < 5 { return "just now" }
        return Formatting.timeAgo(lastRefresh)
    }
}
