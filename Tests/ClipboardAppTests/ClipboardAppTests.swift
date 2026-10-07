import XCTest
@testable import ClipboardApp

@MainActor
final class ClipboardAppTests: XCTestCase {
    func testClipboardItemTypeSummary() {
        let item = ClipboardItem(
            id: UUID(),
            createdAt: Date(),
            sourceApp: nil,
            kind: .text,
            preview: "hello",
            types: [],
            byteSize: 5
        )

        XCTAssertEqual(item.typeSummary, "文本")
    }

    func testPreparingSequenceStopsCollectionWithoutChangingSnapshot() {
        let store = ClipboardStore()
        store.startSequence()

        for text in ["first", "second", "third"] {
            let data = Data(text.utf8)
            let item = ClipboardItem(
                id: UUID(),
                createdAt: Date(),
                sourceApp: nil,
                kind: .text,
                preview: text,
                types: ["public.utf8-plain-text"],
                byteSize: data.count
            )
            store.add(payload: ClipboardPayload(
                item: item,
                dataByType: ["public.utf8-plain-text": data]
            ))
        }

        let payloads = store.prepareSequenceForPasting()

        XCTAssertEqual(payloads.map { $0.item.preview }, ["first", "second", "third"])
        XCTAssertFalse(store.isCollecting)
        XCTAssertEqual(store.sequenceCount, 0)
    }

    func testCombinesPlainTextWithConfiguredSeparator() {
        let payloads = ["one", "two", "three"].map { text in
            let data = Data(text.utf8)
            let item = ClipboardItem(
                id: UUID(),
                createdAt: Date(),
                sourceApp: nil,
                kind: .text,
                preview: text,
                types: ["public.utf8-plain-text"],
                byteSize: data.count
            )
            return ClipboardPayload(item: item, dataByType: ["public.utf8-plain-text": data])
        }

        XCTAssertEqual(
            PasteController.combinedPlainText(from: payloads, separator: "\n"),
            "one\ntwo\nthree"
        )
    }

    func testSequenceItemsAdvanceOneByOne() {
        let store = ClipboardStore()
        store.startSequence()
        for text in ["first", "second", "third"] {
            let data = Data(text.utf8)
            let item = ClipboardItem(
                id: UUID(),
                createdAt: Date(),
                sourceApp: nil,
                kind: .text,
                preview: text,
                types: ["public.utf8-plain-text"],
                byteSize: data.count
            )
            store.add(payload: ClipboardPayload(
                item: item,
                dataByType: ["public.utf8-plain-text": data]
            ))
        }
        store.finishCollecting()

        XCTAssertEqual(store.nextSequencePayload()?.item.preview, "first")
        XCTAssertFalse(store.advanceSequence())
        XCTAssertEqual(store.nextSequencePayload()?.item.preview, "second")
        XCTAssertFalse(store.advanceSequence())
        XCTAssertEqual(store.nextSequencePayload()?.item.preview, "third")
        XCTAssertTrue(store.advanceSequence())
        XCTAssertNil(store.nextSequencePayload())
    }

    func testSequenceCanBeReorderedBeforePasting() {
        let store = ClipboardStore()
        store.startSequence()
        for text in ["first", "second", "third"] {
            let data = Data(text.utf8)
            let item = ClipboardItem(
                id: UUID(),
                createdAt: Date(),
                sourceApp: nil,
                kind: .text,
                preview: text,
                types: ["public.utf8-plain-text"],
                byteSize: data.count
            )
            store.add(payload: ClipboardPayload(
                item: item,
                dataByType: ["public.utf8-plain-text": data]
            ))
        }
        store.finishCollecting()
        let reversedIDs = store.sequenceItems().map(\.id).reversed()
        store.reorderSequence(with: Array(reversedIDs))

        XCTAssertEqual(store.nextSequencePayload()?.item.preview, "third")
    }

    func testDuplicateCopyMovesExistingItemToTop() {
        let store = ClipboardStore()
        let firstID = UUID()
        let firstData = Data("apple".utf8)
        store.add(payload: ClipboardPayload(
            item: ClipboardItem(
                id: firstID,
                createdAt: Date(),
                sourceApp: nil,
                kind: .text,
                preview: "apple",
                types: ["public.utf8-plain-text"],
                byteSize: firstData.count
            ),
            dataByType: ["public.utf8-plain-text": firstData]
        ))

        let secondData = Data("banana".utf8)
        let secondID = UUID()
        store.add(payload: ClipboardPayload(
            item: ClipboardItem(
                id: secondID,
                createdAt: Date(),
                sourceApp: nil,
                kind: .text,
                preview: "banana",
                types: ["public.utf8-plain-text"],
                byteSize: secondData.count
            ),
            dataByType: ["public.utf8-plain-text": secondData]
        ))

        // Recopy apple: existing item should move to the top
        store.add(payload: ClipboardPayload(
            item: ClipboardItem(
                id: UUID(),
                createdAt: Date(),
                sourceApp: nil,
                kind: .text,
                preview: "apple",
                types: ["public.utf8-plain-text"],
                byteSize: firstData.count
            ),
            dataByType: ["public.utf8-plain-text": firstData]
        ))

        XCTAssertEqual(store.items.count, 2)
        XCTAssertEqual(store.items.first?.preview, "apple")
        XCTAssertEqual(store.items.first?.id, firstID)
        XCTAssertEqual(store.items.last?.preview, "banana")
    }

    func testReplaceSequencePreservesOrderInHistory() {
        let store = ClipboardStore()
        let lines = ["alpha", "beta", "gamma"]
        let payloads = lines.map { text in
            let data = Data(text.utf8)
            return ClipboardPayload(
                item: ClipboardItem(
                    id: UUID(),
                    createdAt: Date(),
                    sourceApp: nil,
                    kind: .text,
                    preview: text,
                    types: ["public.utf8-plain-text"],
                    byteSize: data.count
                ),
                dataByType: ["public.utf8-plain-text": data]
            )
        }
        store.replaceSequence(with: payloads)

        XCTAssertEqual(store.items.map(\.preview), ["alpha", "beta", "gamma"])
        XCTAssertEqual(store.sequencePayloads().map { $0.item.preview }, ["alpha", "beta", "gamma"])
    }

    func testHistoryLimitTrimsOldestItems() {
        let store = ClipboardStore()
        for index in 0..<600 {
            let text = "item-\(index)"
            let data = Data(text.utf8)
            store.add(payload: ClipboardPayload(
                item: ClipboardItem(
                    id: UUID(),
                    createdAt: Date(),
                    sourceApp: nil,
                    kind: .text,
                    preview: text,
                    types: ["public.utf8-plain-text"],
                    byteSize: data.count
                ),
                dataByType: ["public.utf8-plain-text": data]
            ))
        }
        XCTAssertEqual(store.items.count, 500)
        XCTAssertEqual(store.items.first?.preview, "item-599")
        XCTAssertEqual(store.items.last?.preview, "item-100")
    }
}
