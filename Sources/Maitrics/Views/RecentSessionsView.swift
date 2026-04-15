import SwiftUI
import MaitricsCore

struct RecentSessionsView: View {
    let sessions: [RecentSession]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Recent Sessions").padding(.bottom, 4)
            if sessions.isEmpty {
                Text("No recent sessions")
                    .font(.system(size: 12))
                    .foregroundColor(Color(white: 0.65))
                    .padding(.vertical, 8)
            } else {
                ForEach(sessions) { session in
                    SessionRow(session: session)
                    if session.id != sessions.last?.id {
                        Divider().opacity(0.03)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

struct SessionRow: View {
    let session: RecentSession
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.firstPrompt)
                    .font(.system(size: 12))
                    .foregroundColor(Color(white: 0.9))
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 4) {
                    Text(session.projectName)
                    if let branch = session.gitBranch {
                        Text("·")
                        Text(branch)
                    }
                    Text("·")
                    Text(Formatting.timeAgo(session.modified))
                }
                .font(.system(size: 9))
                .foregroundColor(Color(white: 0.6))
                .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Formatting.tokens(session.totalTokens))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(red: 96/255, green: 165/255, blue: 250/255))
                Text("~\(Formatting.cost(session.estimatedCost))")
                    .font(.system(size: 9))
                    .foregroundColor(Color(white: 0.6))
            }
        }
        .padding(.vertical, 4)
    }
}
