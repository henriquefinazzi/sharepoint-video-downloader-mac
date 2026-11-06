import SwiftUI

struct ContentView: View {
    @Bindable var manager: DownloadManager
    @State private var link = ""

    private var trimmedLink: String { link.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Paste a video link…", text: $link)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addLink)
                Button("Download", action: addLink)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedLink.isEmpty)
            }
            .padding()

            if !manager.missingTools.isEmpty {
                ToolsBanner(manager: manager)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }

            Divider()

            if manager.items.isEmpty {
                ContentUnavailableView(
                    "No downloads yet",
                    systemImage: "arrow.down.circle",
                    description: Text("Open a SharePoint or Stream video in Safari and click the downloader button in the toolbar, or paste a link above.")
                )
            } else {
                List(manager.items) { item in
                    DownloadRow(item: item, manager: manager)
                }
            }

            Divider()

            HStack {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                Text(manager.outputDirectory.path(percentEncoded: false))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(manager.outputDirectory.path(percentEncoded: false))
                Menu("Change…") {
                    Button("Choose Folder…") { manager.chooseOutputDirectory() }
                    Button("Reset to Downloads/SharePoint Videos") { manager.resetOutputDirectory() }
                        .disabled(manager.isUsingDefaultOutputDirectory)
                } primaryAction: {
                    manager.chooseOutputDirectory()
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Spacer()
                Button("Clear Finished") { manager.clearFinished() }
                    .disabled(!manager.items.contains { !$0.isActive })
                Button("Open Folder") { manager.openOutputFolder() }
            }
            .padding(10)
        }
        .frame(minWidth: 520, minHeight: 320)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            manager.refreshTools()
        }
    }

    private func addLink() {
        guard !trimmedLink.isEmpty else { return }
        manager.enqueue(sourceURL: trimmedLink, title: nil)
        link = ""
    }
}

/// Shown when yt-dlp or ffmpeg is missing; installs them with Homebrew.
struct ToolsBanner: View {
    let manager: DownloadManager

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text("Missing \(manager.missingTools.joined(separator: " and ")), needed to download videos.")
                    .font(.callout.weight(.medium))
                switch manager.toolInstall {
                case .idle:
                    Text("Install it with Homebrew. This can take a few minutes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .installing(let line):
                    Text(line)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                case .failed(let message):
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .lineLimit(8)
                }
            }

            Spacer()

            if case .installing = manager.toolInstall {
                ProgressView().controlSize(.small)
                Text("Installing…").font(.callout).foregroundStyle(.secondary)
            } else {
                Button("Install") { manager.installMissingTools() }
            }
        }
        .padding(10)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct DownloadRow: View {
    let item: DownloadItem
    let manager: DownloadManager

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            statusIcon
                .font(.title2)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayTitle)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if item.isActive {
                    ProgressView(value: item.progress)
                }
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(statusColor)
                    .textSelection(.enabled)
                    .lineLimit(4)
            }

            Spacer()

            buttons
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder private var statusIcon: some View {
        switch item.status {
        case .downloading: Image(systemName: "arrow.down.circle").foregroundStyle(.blue)
        case .merging: Image(systemName: "gearshape.2").foregroundStyle(.blue)
        case .finished: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
        case .cancelled: Image(systemName: "xmark.circle").foregroundStyle(.secondary)
        }
    }

    private var statusText: String {
        switch item.status {
        case .downloading, .merging:
            return "\(Int(item.progress * 100))% · \(item.detail)"
        case .finished, .cancelled:
            return item.detail
        case .failed(let message):
            return message
        }
    }

    private var statusColor: Color {
        if case .failed = item.status { return .red }
        return .secondary
    }

    @ViewBuilder private var buttons: some View {
        switch item.status {
        case .downloading, .merging:
            Button("Cancel") { manager.cancel(item) }
        case .finished:
            Button("Show in Finder") { manager.reveal(item) }
            Button { manager.remove(item) } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .help("Remove from list")
        case .failed, .cancelled:
            Button("Retry") { manager.retry(item) }
            Button { manager.remove(item) } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .help("Remove from list")
        }
    }
}
