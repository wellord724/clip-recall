import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class ClipboardStore: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []
    @Published private(set) var isCollecting = false
    @Published private(set) var sequenceCount = 0
    @Published private(set) var sequencePosition = 0
    @Published private(set) var latestCaptureLocation: NSPoint = NSEvent.mouseLocation
    @Published var searchText = ""

    private var payloads: [UUID: ClipboardPayload] = [:]
    private var sequence: [UUID] = []

    var filteredItems: [ClipboardItem] {
        guard !searchText.isEmpty else { return items }
        return items.filter { item in
            item.preview.localizedCaseInsensitiveContains(searchText) ||
            item.typeSummary.localizedCaseInsensitiveContains(searchText)
        }
    }

    func add(payload: ClipboardPayload) {
        guard !payload.dataByType.isEmpty else { return }
        if let existingIndex = items.firstIndex(where: { $0.preview == payload.item.preview && $0.kind == payload.item.kind }) {
            let existingID = items[existingIndex].id
            payloads[existingID] = payload
            // Move the existing item to the top so recency reflects the latest copy
            let existing = items.remove(at: existingIndex)
            items.insert(existing, at: 0)
            if isCollecting && !sequence.contains(existingID) {
                sequence.append(existingID)
                sequenceCount = sequence.count
            }
            return
        }

        items.insert(payload.item, at: 0)
        payloads[payload.item.id] = payload
        if items.count > 500 {
            let removeCount = items.count - 500
            let toRemove = Array(items.suffix(removeCount))
            items.removeLast(removeCount)
            for item in toRemove {
                payloads.removeValue(forKey: item.id)
            }
        }

        if isCollecting {
            sequence.append(payload.item.id)
            sequenceCount = sequence.count
        }
    }

    func recordCaptureLocation(_ location: NSPoint) {
        latestCaptureLocation = location
    }

    func payload(for id: UUID) -> ClipboardPayload? {
        payloads[id]
    }

    func remove(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
        payloads.removeValue(forKey: item.id)
        sequence.removeAll { $0 == item.id }
        sequenceCount = sequence.count
    }

    func clear() {
        items.removeAll()
        payloads.removeAll()
        sequence.removeAll()
        sequenceCount = 0
        sequencePosition = 0
    }

    func startSequence() {
        sequence.removeAll()
        sequenceCount = 0
        sequencePosition = 0
        isCollecting = true
    }

    func stopSequence() {
        isCollecting = false
        sequence.removeAll()
        sequenceCount = 0
        sequencePosition = 0
    }

    func finishCollecting() {
        isCollecting = false
        sequencePosition = 0
    }

    func prepareSequenceForPasting() -> [ClipboardPayload] {
        let payloads = sequencePayloads()
        isCollecting = false
        sequenceCount = 0
        sequencePosition = 0
        return payloads
    }

    func nextSequencePayload() -> ClipboardPayload? {
        guard sequencePosition < sequence.count else { return nil }
        return payloads[sequence[sequencePosition]]
    }

    @discardableResult
    func advanceSequence() -> Bool {
        sequencePosition += 1
        sequenceCount = max(sequence.count - sequencePosition, 0)
        if sequencePosition >= sequence.count {
            clearSequence()
            return true
        }
        return false
    }

    func clearSequence() {
        sequence.removeAll()
        sequenceCount = 0
        sequencePosition = 0
    }

    func replaceSequence(with payloads: [ClipboardPayload]) {
        let payloadItems = payloads.map(\.item)
        let payloadIDs = Set(payloadItems.map(\.id))
        for payload in payloads {
            self.payloads[payload.item.id] = payload
        }
        // Remove existing duplicates, then prepend new items in input order
        items = payloadItems + items.filter { !payloadIDs.contains($0.id) }
        if items.count > 500 {
            let removeCount = items.count - 500
            let toRemove = Array(items.suffix(removeCount))
            items.removeLast(removeCount)
            for item in toRemove {
                self.payloads.removeValue(forKey: item.id)
            }
        }
        sequence = payloads.map(\.item.id)
        sequencePosition = 0
        sequenceCount = sequence.count
        isCollecting = false
    }

    func sequencePayloads() -> [ClipboardPayload] {
        sequence.dropFirst(sequencePosition).compactMap { payloads[$0] }
    }

    func sequenceItems() -> [ClipboardItem] {
        guard sequencePosition < sequence.count else { return [] }
        let itemByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        return sequence.dropFirst(sequencePosition).compactMap { itemByID[$0] }
    }

    func reorderSequence(with ids: [UUID]) {
        let consumed = Array(sequence.prefix(sequencePosition))
        let remaining = Array(sequence.dropFirst(sequencePosition))
        let available = Set(remaining)
        let reordered = ids.filter { available.contains($0) }
        let missing = remaining.filter { !reordered.contains($0) }
        sequence = consumed + reordered + missing
        sequenceCount = remaining.count
    }
}
