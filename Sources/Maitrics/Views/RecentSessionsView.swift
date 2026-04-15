import SwiftUI
import MaitricsCore

struct RecentSessionsView: View {
    let sessions: [RecentSession]

    private var displaySessions: [RecentSession] {
        Array(sessions.prefix(5))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(text: "Recent Sessions").padding(.bottom, 2)
            if displaySessions.isEmpty {
                Text("No recent sessions")
                    .font(.system(size: 12))
                    .foregroundColor(Color(white: 0.65))
                    .padding(.vertical, 4)
            } else {
                ForEach(displaySessions) { session in
                    SessionRow(session: session)
                    if session.id != displaySessions.last?.id {
                        Divider().opacity(0.04)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
}

struct SessionRow: View {
    let session: RecentSession
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(session.firstPrompt)
                    .font(.system(size: 11))
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
            VStack(alignment: .trailing, spacing: 1) {
                Text(Formatting.tokens(session.totalTokens))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color(red: 96/255, green: 165/255, blue: 250/255))
                Text("~\(Formatting.cost(session.estimatedCost))")
                    .font(.system(size: 9))
                    .foregroundColor(Color(white: 0.6))
            }
        }
        .padding(.vertical, 2)
    }
}
