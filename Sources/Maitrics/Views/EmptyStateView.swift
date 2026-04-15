import SwiftUI
import MaitricsCore

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            if UsageAPIClient.hasToken {
                Image(systemName: "gauge.with.dots.needle.0percent")
                    .font(.system(size: 48))
                    .foregroundColor(Color(white: 0.4))
                Text("No usage data yet")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color(white: 0.7))
                Text("Start a Claude Code session to see your usage stats.")
                    .font(.system(size: 12))
                    .foregroundColor(Color(white: 0.55))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            } else {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 42))
                    .foregroundColor(Color(red: 255/255, green: 176/255, blue: 85/255))

                Text("Claude Code Required")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)

                Text("Maitrics requires Claude Code CLI to be installed and signed in. Please install Claude Code and authenticate before using this app.")
                    .font(.system(size: 12))
                    .foregroundColor(Color(white: 0.55))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
