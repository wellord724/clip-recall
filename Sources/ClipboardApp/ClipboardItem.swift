import Foundation
import UniformTypeIdentifiers

struct ClipboardItem: Identifiable, Hashable {
    enum ContentKind: String {
        case text
        case image
        case richText
        case mixed
        case unknown
    }

    let id: UUID
    let createdAt: Date
    let sourceApp: String?
    let kind: ContentKind
    let preview: String
    let types: [String]
    let byteSize: Int

    var typeSummary: String {
        switch kind {
        case .text: return "文本"
        case .image: return "图片"
        case .richText: return "富文本"
        case .mixed: return "多格式"
        case .unknown: return "未知"
        }
    }
}

struct ClipboardPayload {
    let item: ClipboardItem
    let dataByType: [String: Data]

    var text: String? {
        guard let data = dataByType[UTType.utf8PlainText.identifier] else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
