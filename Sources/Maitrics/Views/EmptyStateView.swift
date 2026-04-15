import SwiftUI
import MaitricsCore

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "gauge.with.dots.needle.0percent")
                .font(.system(size: 48))
                .foregroundColor(Color(white: 0.4))

            if UsageAPIClient.hasToken {
                Text("No usage data yet")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color(white: 0.7))
                Text("Start a Claude Code session to see your usage stats.")
                    .font(.system(size: 12))
                    .foregroundColor(Color(white: 0.55))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            } else {
                Text("Connect to Claude")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color(white: 0.7))

                VStack(alignment: .leading, spacing: 10) {
                    Text("Maitrics needs Claude Code CLI to work.")
                        .font(.system(size: 12))
                        .foregroundColor(Color(white: 0.55))

                    stepRow(number: "1", text: "Install Claude Code CLI")
                    codeBlock("brew install claude-code")

                    stepRow(number: "2", text: "Sign in with your Claude account")
                    codeBlock("claude")

                    stepRow(number: "3", text: "Reopen Maitrics")
                }
                .frame(maxWidth: 280)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func stepRow(number: String, text: String) -> some View {
        HStack(spacing: 8) {
            Text(number)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 16, height: 16)
                .background(Color.blue.opacity(0.5))
                .cornerRadius(8)
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(Color(white: 0.7))
        }
    }

    private func codeBlock(_ code: String) -> some View {
        Text(code)
            .font(.system(size: 10, design: .monospaced))
            .foregroundColor(Color(white: 0.8))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.06))
            .cornerRadius(4)
            .padding(.leading, 24)
    }
}
