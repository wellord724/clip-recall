import SwiftUI

struct ClipboardView: View {
    @ObservedObject var store: ClipboardStore
    let onPaste: (ClipboardItem) -> Void
    let onStartSequence: () -> Void
    let onPasteSequence: () -> Void
    let onPasteNext: () -> Void
    let onClear: () -> Void
    let onOpenAccessibility: () -> Void
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            shortcutGuide
            if store.filteredItems.isEmpty {
                emptyState
            } else {
                itemList
            }
            footer
        }
        .frame(minWidth: 420, idealWidth: 420, maxWidth: .infinity,
               minHeight: 520, idealHeight: 520, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("剪贴板")
                        .font(.system(size: 21, weight: .semibold, design: .rounded))
                    Text(collectionStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Circle()
                    .fill(store.isCollecting ? .orange : .green)
                    .frame(width: 9, height: 9)
            }
            TextField("搜索历史", text: $store.searchText)
                .textFieldStyle(.roundedBorder)
        }
        .padding(18)
    }

    private var itemList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(store.filteredItems) { item in
                    ClipboardRow(item: item, onPaste: { onPaste(item) }, onDelete: { store.remove(item) })
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
    }

    private var collectionStatus: String {
        if !store.isCollecting && store.sequenceCount > 0 {
            return "序列已就绪 · 可全部或逐条粘贴"
        }
        guard store.isCollecting else { return "本机历史" }
        if store.sequenceCount == 0 { return "序列收集中 · 等待第 1 条" }
        return "序列收集中 · 已收集 \(store.sequenceCount) 条"
    }

    private var shortcutGuide: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("快捷键")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ShortcutKey(label: "⌘⇧V", title: "打开面板")
                ShortcutKey(label: "⌘⇧C", title: "开始/结束收集")
                ShortcutKey(label: "⌘⇧P", title: "按序粘贴")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.bottom, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.secondary)
            Text("还没有剪贴板历史")
                .font(.headline)
            Text("复制文本或图片后会显示在这里")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button(store.isCollecting ? "结束收集" : "开始收集") {
                onStartSequence()
            }
            .buttonStyle(.borderedProminent)
            .tint(store.isCollecting ? .orange : .blue)

            if !store.isCollecting && store.sequenceCount > 0 {
                Button("全部粘贴") { onPasteSequence() }
                    .buttonStyle(.bordered)
                Button("粘贴下一条") { onPasteNext() }
                    .buttonStyle(.borderedProminent)
            }

            Spacer()

            Menu {
                Button("打开设置") { onOpenSettings() }
                Divider()
                Button("打开辅助功能设置") { onOpenAccessibility() }
                Divider()
                Button("清空历史", role: .destructive) { onClear() }
                Divider()
                Button("退出程序") { onQuit() }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
        }
        .padding(14)
    }
}

private struct ShortcutKey: View {
    let label: String
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct ClipboardRow: View {
    let item: ClipboardItem
    let onPaste: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.preview)
                    .lineLimit(2)
                    .font(.system(size: 13))
                Text("\(item.typeSummary) · \(item.byteSize.formatted()) bytes")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button(action: onPaste) {
                Image(systemName: "arrow.down.doc")
            }
            .buttonStyle(.borderless)
            .help("粘贴")
            Button(action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("删除")
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private var iconName: String {
        switch item.kind {
        case .image: return "photo"
        case .richText: return "doc.richtext"
        default: return "text.alignleft"
        }
    }
}
