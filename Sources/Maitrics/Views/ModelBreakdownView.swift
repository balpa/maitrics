import SwiftUI
import MaitricsCore

struct ModelBreakdownView: View {
    let models: [(name: String, tokens: Int, color: String)]
    private var maxTokens: Int { models.map(\.tokens).max() ?? 1 }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "By Model").padding(.bottom, 4)
            ForEach(models, id: \.name) { model in
                HStack(spacing: 8) {
                    Text(model.name)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color(white: 0.8))
                        .frame(width: 48, alignment: .trailing)
                    GeometryReader { geo in
                        let fraction = maxTokens > 0 ? CGFloat(model.tokens) / CGFloat(maxTokens) : 0
                        RoundedRectangle(cornerRadius: 3)
                            .fill(LinearGradient(colors: gradientColors(for: model.color), startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * fraction)
                    }
                    .frame(height: 5)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(3)
                    Text(Formatting.tokens(model.tokens))
                        .font(.system(size: 9))
                        .foregroundColor(Color(white: 0.7))
                        .frame(width: 44, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
    private func gradientColors(for color: String) -> [Color] {
        switch color {
        case "orange": return [Color(red: 249/255, green: 115/255, blue: 22/255), Color(red: 251/255, green: 146/255, blue: 60/255)]
        case "blue": return [Color(red: 59/255, green: 130/255, blue: 246/255), Color(red: 96/255, green: 165/255, blue: 250/255)]
        case "purple": return [Color(red: 168/255, green: 85/255, blue: 247/255), Color(red: 192/255, green: 132/255, blue: 252/255)]
        default: return [Color.gray, Color.gray.opacity(0.7)]
        }
    }
}
