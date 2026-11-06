import AppKit
import SwiftUI
import UserNotifications

@main
struct SPVideoDownloaderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("SharePoint Video Downloader", id: "main") {
            ContentView(manager: DownloadManager.shared)
        }
        .defaultSize(width: 640, height: 440)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Change Download Folder…") { DownloadManager.shared.chooseOutputDirectory() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Called for `spvd://download?url=…&title=…` sent by the Safari extension.
    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated {
            for url in urls { DownloadManager.shared.handle(appURL: url) }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let active = MainActor.assumeIsolated { DownloadManager.shared.hasActiveDownloads }
        guard active else { return .terminateNow }

        let alert = NSAlert()
        alert.messageText = "Downloads are still running"
        alert.informativeText = "Quitting now will cancel them."
        alert.addButton(withTitle: "Keep Downloading")
        alert.addButton(withTitle: "Quit Anyway")
        guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
        MainActor.assumeIsolated { DownloadManager.shared.cancelAll() }
        return .terminateNow
    }
}
