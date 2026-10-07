import SwiftUI
import UniformTypeIdentifiers

struct SequencePickerView: View {
    @ObservedObject var model: SequencePickerModel
    let isOneByOne: Bool
    let onCancel: () -> Void
    let onConfirm: ([UUID]) -> Void
    let onPasteNext: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "list.number")
                    .foregroundStyle(.tint)
                Text(model.isConfirmed && isOneByOne ? "逐条粘贴" : "粘贴顺序")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("剩余 \(model.items.count) 条")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if model.items.isEmpty {
                Text("已全部粘贴")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 10)
            } else {
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                            candidateRow(index: index, item: item)
                        }
                    }
                }
                .frame(maxHeight: 250)
            }

            Divider()

            HStack(spacing: 8) {
                Button("取消") { onCancel() }
                    .buttonStyle(.borderless)
                Spacer()
                if model.isConfirmed && isOneByOne {
                    Button("粘贴下一条") { onPasteNext() }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("按此顺序粘贴") {
                        onConfirm(model.items.map(\.id))
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .frame(width: 330, height: modelHeight)
    }

    private var modelHeight: CGFloat {
        min(max(128, CGFloat(model.items.count * 31 + 82)), 340)
    }

    private func candidateRow(index: Int, item: ClipboardItem) -> some View {
        HStack(spacing: 6) {
            Text("\(index + 1)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.tint)
                .frame(width: 18, alignment: .trailing)

            Text("[\(item.typeSummary)] \(item.preview)")
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 2)

            Menu {
                Button("上移") { model.move(item, by: -1) }
                    .disabled(index == 0)
                Button("下移") { model.move(item, by: 1) }
                    .disabled(index == model.items.count - 1)
                Divider()
                Button("移到顶部") { model.moveToEdge(item, top: true) }
                Button("移到底部") { model.moveToEdge(item, top: false) }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 11, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .help("调整顺序")

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
                .help("上下拖动排序")
        }
        .padding(.horizontal, 6)
        .frame(height: 28)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onDrag { NSItemProvider(object: item.id.uuidString as NSString) }
        .onDrop(of: [UTType.plainText], delegate: SequenceRowDropDelegate(item: item, model: model))
    }
}

private struct SequenceRowDropDelegate: DropDelegate {
    let item: ClipboardItem
    let model: SequencePickerModel

    func dropEntered(info: DropInfo) {
        guard let provider = info.itemProviders(for: [UTType.plainText]).first else { return }
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let value = object as? String, let draggedID = UUID(uuidString: value) else { return }
            DispatchQueue.main.async {
                model.move(id: draggedID, before: item.id)
            }
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        true
    }
}
