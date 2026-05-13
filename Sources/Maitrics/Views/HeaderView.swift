import SwiftUI
import MaitricsCore

struct HeaderView: View {
    let profileData: ProfileData?
    let showSettings: Bool
    let isLoading: Bool
    var onToggleSettings: () -> Void

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("MAITRICS")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .tracking(0.5)
                    if isLoading {
                        SpinnerView()
                            .frame(width: 14, height: 14)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.18), value: isLoading)

                if let profile = profileData {
                    HStack(spacing: 6) {
                        Text(profile.planDisplayName)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(planColor(profile.planType))
                        Text("·")
                            .foregroundColor(Color(white: 0.5))
                        Text(profile.name)
                            .foregroundColor(Color(white: 0.6))
                    }
                    .font(.system(size: 10))
                }
            }
            Spacer()
            Button(action: onToggleSettings) {
                Image(systemName: showSettings ? "xmark" : "gearshape")
                    .font(.system(size: 14))
                    .foregroundColor(Color(white: 0.65))
            }
            .buttonStyle(.plain)
            .focusable(false)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private struct SpinnerView: View {
        @State private var rotation: Double = 0
        var body: some View {
            Circle()
                .trim(from: 0.15, to: 0.85)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                .rotationEffect(.degrees(rotation))
                .onAppear {
                    withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                        rotation = 360
                    }
                }
        }
    }

    private func planColor(_ planType: String) -> Color {
        switch planType {
        case "claude_max": return Color(red: 192/255, green: 132/255, blue: 252/255)  // purple
        case "claude_pro": return Color(red: 74/255, green: 222/255, blue: 128/255)   // green
        case "claude_team": return Color(red: 96/255, green: 165/255, blue: 250/255)  // blue
        default: return Color(white: 0.7)
        }
    }
}
