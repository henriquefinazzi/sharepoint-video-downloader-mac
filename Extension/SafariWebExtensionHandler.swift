import AppKit
import SafariServices

/// Receives `browser.runtime.sendNativeMessage` calls from the extension and
/// hands the video to the main app through its `spvd://` URL scheme.
/// (The extension runs sandboxed; the app does the actual downloading.)
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {

    func beginRequest(with context: NSExtensionContext) {
        let item = context.inputItems.first as? NSExtensionItem
        let message = item?.userInfo?[SFExtensionMessageKey] as? [String: Any]

        let reply: [String: Any]
        if let url = message?["url"] as? String, !url.isEmpty {
            let title = (message?["title"] as? String) ?? "SharePoint Video"
            reply = forward(url: url, title: title)
        } else {
            reply = ["ok": false, "error": "No video URL in message."]
        }

        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: reply]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }

    private func forward(url: String, title: String) -> [String: Any] {
        var components = URLComponents()
        components.scheme = "spvd"
        components.host = "download"
        components.queryItems = [
            URLQueryItem(name: "url", value: url),
            URLQueryItem(name: "title", value: title),
        ]
        guard let appURL = components.url else {
            return ["ok": false, "error": "Could not build app URL."]
        }
        let opened = NSWorkspace.shared.open(appURL)
        return opened ? ["ok": true] : ["ok": false, "error": "Could not open the SharePoint Video Downloader app."]
    }
}
