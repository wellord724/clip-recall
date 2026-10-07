import SwiftUI

struct MultilineChoiceView: View {
    let lineCount: Int
    let preview: String
    let onAll: () -> Void
    let onOneByOne: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "text.alignleft")
                    .foregroundStyle(.tint)
                Text("检测到多行文本")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    onCancel()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("取消")
            }
            Text("共 \(lineCount) 行，选择粘贴方式")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(preview)
                .font(.system(size: 12))
                .lineLimit(2)
                .truncationMode(.tail)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button("全部输出") { onAll() }
                    .buttonStyle(.bordered)
                Button("逐行粘贴") { onOneByOne() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .frame(width: 300, height: 142)
    }
}
