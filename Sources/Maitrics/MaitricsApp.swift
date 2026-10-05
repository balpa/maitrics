import AppKit

/// AppKit entry point. A SwiftUI `App` needs a scene, and its empty `Settings` scene opened a blank window at launch.
@main
enum MaitricsApp {
    private static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusBarController = StatusBarController()
    }
}
