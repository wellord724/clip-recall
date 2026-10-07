import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class ClipboardMonitor {
    private var timer: Timer?
    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private weak var store: ClipboardStore?

    init(store: ClipboardStore) {
        self.store = store
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.poll()
            }
        }
        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func captureNow() {
        poll()
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        guard let payload = makePayload(from: pasteboard) else { return }
        store?.recordCaptureLocation(NSEvent.mouseLocation)
        store?.add(payload: payload)
    }

    private func makePayload(from pasteboard: NSPasteboard) -> ClipboardPayload? {
        let supportedTypes: [NSPasteboard.PasteboardType] = [
            .string,
            .html,
            .rtf,
            .rtfd,
            .tiff,
            .png
        ]
        var dataByType: [String: Data] = [:]
        var availableTypes: [String] = []

        for type in supportedTypes {
            guard let data = pasteboard.data(forType: type) else { continue }
            dataByType[type.rawValue] = data
            availableTypes.append(type.rawValue)
        }

        guard !dataByType.isEmpty else { return nil }
        let kind: ClipboardItem.ContentKind
        let preview: String

        if let textData = dataByType[NSPasteboard.PasteboardType.string.rawValue],
           let text = String(data: textData, encoding: .utf8) {
            preview = text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(240).description
            if dataByType[NSPasteboard.PasteboardType.html.rawValue] != nil ||
                dataByType[NSPasteboard.PasteboardType.rtf.rawValue] != nil ||
                dataByType[NSPasteboard.PasteboardType.rtfd.rawValue] != nil {
                kind = .richText
            } else {
                kind = .text
            }
        } else if let rtfData = dataByType[NSPasteboard.PasteboardType.rtf.rawValue] ??
                    dataByType[NSPasteboard.PasteboardType.rtfd.rawValue],
                  let attributed = NSAttributedString(rtf: rtfData, documentAttributes: nil) {
            let text = attributed.string
            preview = text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(240).description
            kind = .richText
        } else if dataByType[NSPasteboard.PasteboardType.tiff.rawValue] != nil ||
                    dataByType[NSPasteboard.PasteboardType.png.rawValue] != nil {
            preview = "图片内容"
            kind = .image
        } else {
            preview = "未预览内容"
            kind = .unknown
        }

        let item = ClipboardItem(
            id: UUID(),
            createdAt: Date(),
            sourceApp: NSWorkspace.shared.frontmostApplication?.localizedName,
            kind: kind,
            preview: preview.isEmpty ? "空文本" : preview,
            types: availableTypes,
            byteSize: dataByType.values.reduce(0) { $0 + $1.count }
        )
        return ClipboardPayload(item: item, dataByType: dataByType)
    }
}
