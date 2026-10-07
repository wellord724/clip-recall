import AppKit
import ApplicationServices
import Foundation

@MainActor
final class PasteController {
    enum PasteError: LocalizedError {
        case accessibilityPermission

        var errorDescription: String? {
            "需要在系统设置中允许辅助功能权限，才能自动发送粘贴快捷键。"
        }
    }

    func paste(_ payload: ClipboardPayload) throws {
        guard requestAccessibilityPermission() else { throw PasteError.accessibilityPermission }
        writeToPasteboard(payload)
        sendCommandV()
    }

    func pasteSequence(
        _ payloads: [ClipboardPayload],
        separator: String = "",
        interval: TimeInterval = 0.04
    ) async throws {
        guard requestAccessibilityPermission() else { throw PasteError.accessibilityPermission }

        if let combinedText = Self.combinedPlainText(from: payloads, separator: separator) {
            writeTextToPasteboard(combinedText)
            sendCommandV()
            return
        }

        for (index, payload) in payloads.enumerated() {
            try Task.checkCancellation()
            writeToPasteboard(payload)
            sendCommandV()
            if index < payloads.count - 1 {
                try await Task.sleep(for: .milliseconds(Int(interval * 1000)))
                if !separator.isEmpty {
                    writeTextToPasteboard(separator)
                    sendCommandV()
                    try await Task.sleep(for: .milliseconds(Int(interval * 1000)))
                }
            }
        }
    }

    static func combinedPlainText(from payloads: [ClipboardPayload], separator: String) -> String? {
        guard !payloads.isEmpty,
              payloads.allSatisfy({ $0.item.kind == .text }) else { return nil }
        let texts = payloads.compactMap(\.text)
        guard texts.count == payloads.count else { return nil }
        return texts.joined(separator: separator)
    }

    private func requestAccessibilityPermission() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private static let pasteboardTypePriority: [String] = [
        NSPasteboard.PasteboardType.string.rawValue,
        NSPasteboard.PasteboardType.html.rawValue,
        NSPasteboard.PasteboardType.rtf.rawValue,
        NSPasteboard.PasteboardType.rtfd.rawValue,
        NSPasteboard.PasteboardType.tiff.rawValue,
        NSPasteboard.PasteboardType.png.rawValue
    ]

    private func writeToPasteboard(_ payload: ClipboardPayload) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let orderedTypes = payload.dataByType.keys.sorted { lhs, rhs in
            let lhsPriority = Self.pasteboardTypePriority.firstIndex(of: lhs) ?? Int.max
            let rhsPriority = Self.pasteboardTypePriority.firstIndex(of: rhs) ?? Int.max
            return lhsPriority < rhsPriority
        }
        for rawType in orderedTypes {
            guard let data = payload.dataByType[rawType] else { continue }
            pasteboard.setData(data, forType: NSPasteboard.PasteboardType(rawValue: rawType))
        }
    }

    private func writeTextToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func sendCommandV() {
        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false) else { return }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
