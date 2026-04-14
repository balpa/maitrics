import SwiftUI

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "gauge.with.dots.needle.0percent")
                .font(.system(size: 48))
                .foregroundColor(Color(white: 0.3))
            Text("No Claude Code data found")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Color(white: 0.6))
            Text("Start a Claude Code session to see your usage stats here.")
                .font(.system(size: 12))
                .foregroundColor(Color(white: 0.4))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
