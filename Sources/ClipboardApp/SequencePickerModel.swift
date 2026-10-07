import Combine
import Foundation

@MainActor
final class SequencePickerModel: ObservableObject {
    @Published var items: [ClipboardItem]
    @Published var isConfirmed = false
    var onReorder: (([UUID]) -> Void)?

    init(items: [ClipboardItem]) {
        self.items = items
    }

    func move(_ item: ClipboardItem, by offset: Int) {
        guard let index = items.firstIndex(of: item) else { return }
        let destination = index + offset
        guard items.indices.contains(destination) else { return }
        items.swapAt(index, destination)
        onReorder?(items.map(\.id))
    }

    func moveToEdge(_ item: ClipboardItem, top: Bool) {
        guard let index = items.firstIndex(of: item) else { return }
        let item = items.remove(at: index)
        if top {
            items.insert(item, at: 0)
        } else {
            items.append(item)
        }
        onReorder?(items.map(\.id))
    }

    func move(id: UUID, before targetID: UUID) {
        guard id != targetID,
              let sourceIndex = items.firstIndex(where: { $0.id == id }),
              let targetIndex = items.firstIndex(where: { $0.id == targetID }) else { return }
        let item = items.remove(at: sourceIndex)
        let adjustedTarget = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
        items.insert(item, at: adjustedTarget)
        onReorder?(items.map(\.id))
    }

    func remove(id: UUID) {
        items.removeAll { $0.id == id }
    }

    func update(items newItems: [ClipboardItem]) {
        guard items.map(\.id) != newItems.map(\.id) else { return }
        items = newItems
    }
}
