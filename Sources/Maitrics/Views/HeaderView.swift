import SwiftUI

struct HeaderView: View {
    var onSettingsOpen: () -> Void
    var body: some View {
        HStack {
            Text("MAITRICS")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .tracking(0.5)
            Spacer()
            Button(action: onSettingsOpen) {
                Image(systemName: "gearshape")
                    .font(.system(size: 14))
                    .foregroundColor(Color(white: 0.4))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }
}
