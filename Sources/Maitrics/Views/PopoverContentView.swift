import SwiftUI
import MaitricsCore

struct PopoverContentView: View {
    let dataManager: ClaudeDataManager
    let settings: AppSettings
    var onSettingsOpen: () -> Void
    var body: some View {
        Text("Maitrics — loading...")
            .frame(width: 420, height: 580)
    }
}
