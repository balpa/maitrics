import SwiftUI
import MaitricsCore

struct FooterView: View {
    let lastRefresh: Date?
    let isWatching: Bool
    var body: some View {
        HStack {
            HStack(spacing: 4) {
                Circle()
                    .fill(isWatching ? Color(red: 74/255, green: 222/255, blue: 128/255) : Color(white: 0.3))
                    .frame(width: 5, height: 5)
                Text(isWatching ? "Live · watching ~/.claude" : "Paused")
                    .font(.system(size: 9))
                    .foregroundColor(Color(white: 0.3))
            }
            Spacer()
            Text("Last: \(lastRefreshText)")
                .font(.system(size: 9))
                .foregroundColor(Color(white: 0.3))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
    private var lastRefreshText: String {
        guard let lastRefresh else { return "never" }
        let seconds = Date().timeIntervalSince(lastRefresh)
        if seconds < 5 { return "just now" }
        return Formatting.timeAgo(lastRefresh)
    }
}
