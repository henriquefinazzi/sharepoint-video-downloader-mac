import AppKit
import Foundation
import Observation
import UserNotifications

enum DownloadStatus: Equatable {
    case downloading
    case merging
    case finished
    case failed(String)
    case cancelled
}

@MainActor
@Observable
final class DownloadItem: Identifiable {
    let id = UUID()
    let sourceURL: String
    /// Title from Safari; nil for pasted links (yt-dlp names the file then).
    let requestedTitle: String?
    var displayTitle: String
    var status: DownloadStatus = .downloading
    var progress: Double = 0
    var detail = "Starting…"
    var outputPath: String?

    @ObservationIgnored var process: Process?
    @ObservationIgnored var userCancelled = false

    init(sourceURL: String, title: String?) {
        self.sourceURL = sourceURL
        self.requestedTitle = title
        self.displayTitle = title.map(FileNaming.cleanTitle) ?? sourceURL
    }

    var isActive: Bool { status == .downloading || status == .merging }
}

@MainActor
@Observable
final class DownloadManager {
    static let shared = DownloadManager()

    var items: [DownloadItem] = []

    static let defaultOutputDirectory: URL = FileManager.default
        .urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("SharePoint Videos", isDirectory: true)
    private static let outputDirectoryKey = "outputDirectory"

    /// Where new downloads are saved. Chosen by the user and remembered between launches.
    private(set) var outputDirectory: URL = {
        if let path = UserDefaults.standard.string(forKey: outputDirectoryKey) {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return defaultOutputDirectory
    }()

    var isUsingDefaultOutputDirectory: Bool {
        outputDirectory.standardizedFileURL == Self.defaultOutputDirectory.standardizedFileURL
    }

    /// Shows a folder picker; downloads already running keep their original folder.
    func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Choose Download Folder"
        panel.prompt = "Use This Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.fileExists(atPath: outputDirectory.path)
            ? outputDirectory : outputDirectory.deletingLastPathComponent()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setOutputDirectory(url)
    }

    func resetOutputDirectory() {
        UserDefaults.standard.removeObject(forKey: Self.outputDirectoryKey)
        outputDirectory = Self.defaultOutputDirectory
    }

    private func setOutputDirectory(_ url: URL) {
        outputDirectory = url
        UserDefaults.standard.set(url.path, forKey: Self.outputDirectoryKey)
    }

    var hasActiveDownloads: Bool { items.contains { $0.isActive } }

    /// Required command-line tools that aren't installed. Refreshed on launch,
    /// when the app becomes active, and after an install.
    private(set) var missingTools: [String] = []
    private(set) var toolInstall: ToolInstallState = .idle

    private init() { refreshTools() }

    func refreshTools() {
        missingTools = ["yt-dlp", "ffmpeg"].filter { Tools.find($0) == nil }
    }

    // MARK: Installing tools

    /// Runs `brew install` for the missing tools, or opens brew.sh if Homebrew isn't there.
    func installMissingTools() {
        guard !missingTools.isEmpty else { return }
        if case .installing = toolInstall { return }
        guard let brew = Tools.find("brew") else {
            toolInstall = .failed("Homebrew isn't installed. Install it from brew.sh, then come back and click Install again.")
            NSWorkspace.shared.open(URL(string: "https://brew.sh")!)
            return
        }

        toolInstall = .installing("Starting Homebrew…")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: brew)
        process.arguments = ["install"] + missingTools
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = Tools.searchDirectories.joined(separator: ":") + ":" + (env["PATH"] ?? "")
        env["HOMEBREW_NO_ENV_HINTS"] = "1"
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let lines = LineBuffer()
        let log = InstallLog()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let new = lines.append(data)
            log.add(new)
            if let last = new.last {
                Task { @MainActor in
                    if case .installing = self.toolInstall { self.toolInstall = .installing(last) }
                }
            }
        }
        process.terminationHandler = { proc in
            pipe.fileHandleForReading.readabilityHandler = nil
            log.add(lines.append(pipe.fileHandleForReading.readDataToEndOfFile()) + lines.flush())
            let code = proc.terminationStatus
            let tail = log.tail
            Task { @MainActor in
                self.refreshTools()
                if code == 0 && self.missingTools.isEmpty {
                    self.toolInstall = .idle
                    self.notify(title: "Tools installed", body: "yt-dlp and ffmpeg are ready.")
                } else {
                    self.toolInstall = .failed("Homebrew couldn't finish (exit code \(code)).\n\(tail)")
                }
            }
        }

        do {
            try process.run()
        } catch {
            toolInstall = .failed("Couldn't run Homebrew: \(error.localizedDescription)")
        }
    }

    // MARK: Entry points

    func handle(appURL: URL) {
        guard appURL.scheme == "spvd", appURL.host == "download",
              let query = URLComponents(url: appURL, resolvingAgainstBaseURL: false)?.queryItems,
              let source = query.first(where: { $0.name == "url" })?.value, !source.isEmpty
        else { return }
        let title = query.first(where: { $0.name == "title" })?.value
        enqueue(sourceURL: source, title: title)
    }

    func enqueue(sourceURL: String, title: String?) {
        let item = DownloadItem(sourceURL: sourceURL, title: title)
        items.insert(item, at: 0)
        start(item)
    }

    // MARK: Actions

    func retry(_ item: DownloadItem) {
        guard !item.isActive else { return }
        item.status = .downloading
        item.progress = 0
        item.detail = "Starting…"
        item.userCancelled = false
        start(item)
    }

    func cancel(_ item: DownloadItem) {
        guard item.isActive else { return }
        item.userCancelled = true
        item.process?.terminate()
    }

    func cancelAll() { items.forEach(cancel) }

    func remove(_ item: DownloadItem) {
        cancel(item)
        items.removeAll { $0.id == item.id }
    }

    func clearFinished() {
        items.removeAll { !$0.isActive }
    }

    func reveal(_ item: DownloadItem) {
        guard let path = item.outputPath, FileManager.default.fileExists(atPath: path) else {
            openOutputFolder()
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func openOutputFolder() {
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(outputDirectory)
    }

    // MARK: Running yt-dlp

    private func start(_ item: DownloadItem) {
        guard let ytdlp = Tools.find("yt-dlp"), let ffmpeg = Tools.find("ffmpeg") else {
            refreshTools()
            item.status = .failed("yt-dlp and ffmpeg are required. Click Install at the top of the window, then Retry.")
            return
        }
        do {
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        } catch {
            item.status = .failed("Can't create \(outputDirectory.path): \(error.localizedDescription)")
            return
        }

        let nameTemplate = item.requestedTitle
            .map { FileNaming.safeFileName($0).replacingOccurrences(of: "%", with: "%%") }
            ?? "%(title).150B"
        let outputTemplate = outputDirectory.appendingPathComponent(nameTemplate).path + ".%(ext)s"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ytdlp)
        process.arguments = [
            "--newline", "--no-color", "--no-playlist",
            "--ffmpeg-location", ffmpeg,
            "--concurrent-fragments", "4",
            "--retry-sleep", "fragment:exp=1:20",
            "--merge-output-format", "mp4",
            "--no-simulate", "--progress",
            "--print", "video:SPVDFMT|%(format_id)s",
            "--print", "after_move:SPVDFILE|%(filepath)s",
            "--progress-template",
            "download:SPVDPROG|%(info.format_id)s|%(progress.downloaded_bytes)s|%(progress.total_bytes)s|%(progress.total_bytes_estimate)s",
            "-o", outputTemplate,
            "--", item.sourceURL,  // "--" so a URL can never be read as an option
        ]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = Tools.searchDirectories.joined(separator: ":") + ":" + (env["PATH"] ?? "")
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let parser = ProgressParser()
        let lines = LineBuffer()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            for line in lines.append(data) {
                Task { @MainActor in parser.consume(line, into: item) }
            }
        }

        process.terminationHandler = { proc in
            pipe.fileHandleForReading.readabilityHandler = nil
            let rest = pipe.fileHandleForReading.readDataToEndOfFile()
            let tail = lines.append(rest) + lines.flush()
            let code = proc.terminationStatus
            Task { @MainActor in
                tail.forEach { parser.consume($0, into: item) }
                self.finish(item, exitCode: code, lastError: parser.lastError)
            }
        }

        item.process = process
        do {
            try process.run()
        } catch {
            item.status = .failed("Couldn't start yt-dlp: \(error.localizedDescription)")
        }
    }

    private func finish(_ item: DownloadItem, exitCode: Int32, lastError: String?) {
        item.process = nil
        if item.userCancelled {
            item.status = .cancelled
            item.detail = "Cancelled"
        } else if exitCode == 0 {
            item.status = .finished
            item.progress = 1
            var folder = outputDirectory.lastPathComponent
            if let path = item.outputPath {
                let file = URL(fileURLWithPath: path)
                item.displayTitle = file.lastPathComponent
                folder = file.deletingLastPathComponent().lastPathComponent
            }
            item.detail = "Saved to \(folder)"
            notify(title: "Download finished", body: item.displayTitle)
        } else {
            let message = lastError ?? "yt-dlp stopped with exit code \(exitCode)."
            item.status = .failed(Self.explain(message))
            notify(title: "Download failed", body: item.displayTitle)
        }
    }

    /// Adds a hint for the most common failure: the page's access token expired.
    private static func explain(_ error: String) -> String {
        if error.contains("401") || error.contains("403") {
            return error + "\nThe link has probably expired. Reload the video page in Safari and click the extension again."
        }
        return error
    }

    func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - yt-dlp output parsing

/// Turns yt-dlp's tagged output lines into item progress.
/// Video and audio download one after another, so overall progress is
/// (finished parts + current part fraction) / number of parts.
@MainActor
final class ProgressParser {
    private var expectedParts = 1
    private var seenFormats: [String] = []
    private(set) var lastError: String?

    func consume(_ line: String, into item: DownloadItem) {
        let fields = line.components(separatedBy: "|")
        switch fields.first {
        case "SPVDFMT" where fields.count >= 2:
            expectedParts = max(1, fields[1].split(separator: "+").count)

        case "SPVDPROG" where fields.count >= 5:
            let format = fields[1]
            if !seenFormats.contains(format) { seenFormats.append(format) }
            let index = seenFormats.firstIndex(of: format) ?? 0
            let done = Double(fields[2]) ?? 0
            let total = Double(fields[3]) ?? Double(fields[4]) ?? 0
            let fraction = total > 0 ? min(1, done / total) : 0
            let parts = Double(max(expectedParts, seenFormats.count))
            item.progress = min(1, (Double(index) + fraction) / parts)

            let isLastPart = index + 1 >= max(expectedParts, seenFormats.count)
            if fraction >= 1 && isLastPart && expectedParts > 1 {
                item.status = .merging
                item.detail = "Merging video and audio…"
            } else {
                let part = expectedParts > 1 ? "Part \(index + 1) of \(expectedParts) · " : ""
                let size = total > 0
                    ? "\(Self.bytes(done)) of \(Self.bytes(total))"
                    : Self.bytes(done)
                item.detail = part + size
            }

        case "SPVDFILE" where fields.count >= 2:
            item.outputPath = fields.dropFirst().joined(separator: "|")

        default:
            if line.hasPrefix("ERROR:") {
                lastError = String(line.dropFirst("ERROR:".count)).trimmingCharacters(in: .whitespaces)
            }
        }
    }

    private static func bytes(_ value: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file)
    }
}

/// Splits a byte stream into lines. Only touched from the pipe's handler queue
/// and then its termination handler, never concurrently.
final class LineBuffer: @unchecked Sendable {
    private var pending = Data()

    func append(_ data: Data) -> [String] {
        pending.append(data)
        var lines: [String] = []
        while let newline = pending.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
            let lineData = pending[pending.startIndex..<newline]
            pending.removeSubrange(pending.startIndex...newline)
            if let line = String(data: lineData, encoding: .utf8), !line.isEmpty { lines.append(line) }
        }
        return lines
    }

    func flush() -> [String] {
        defer { pending.removeAll() }
        guard let line = String(data: pending, encoding: .utf8), !line.isEmpty else { return [] }
        return [line]
    }
}

// MARK: - Helpers

enum ToolInstallState: Equatable {
    case idle
    case installing(String)  // latest line of Homebrew output
    case failed(String)
}

/// Keeps the last few lines of Homebrew output for error messages.
final class InstallLog: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []

    func add(_ new: [String]) {
        lock.lock(); defer { lock.unlock() }
        lines.append(contentsOf: new)
        if lines.count > 6 { lines.removeFirst(lines.count - 6) }
    }

    var tail: String {
        lock.lock(); defer { lock.unlock() }
        return lines.joined(separator: "\n")
    }
}

enum Tools {
    static let searchDirectories = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        NSHomeDirectory() + "/.local/bin",
        "/usr/bin",
    ]

    static func find(_ name: String) -> String? {
        searchDirectories
            .map { $0 + "/" + name }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

enum FileNaming {
    private static let pageSuffixes = [" - Microsoft Stream", " - SharePoint", " - Stream"]
    private static let videoExtensions = [".mp4", ".m4v", ".mkv", ".webm", ".mov", ".avi", ".ts", ".wmv"]

    /// Strips site suffixes and a trailing video extension from a tab title.
    static func cleanTitle(_ title: String) -> String {
        var name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        for suffix in pageSuffixes where name.hasSuffix(suffix) {
            name = String(name.dropLast(suffix.count))
        }
        for ext in videoExtensions where name.lowercased().hasSuffix(ext) {
            name = String(name.dropLast(ext.count))
        }
        return name.isEmpty ? "SharePoint Video" : name
    }

    static func safeFileName(_ title: String) -> String {
        let cleaned = cleanTitle(title)
            .components(separatedBy: CharacterSet(charactersIn: "/:\\").union(.controlCharacters))
            .joined(separator: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        let name = String(cleaned.prefix(150))
        return name.isEmpty ? "SharePoint Video" : name
    }
}
