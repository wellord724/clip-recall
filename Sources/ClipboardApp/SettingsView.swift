import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    let onShortcutsChanged: () -> Void

    var body: some View {
        Form {
            Section("快捷键") {
                shortcutRow("打开面板", binding: $settings.openPanelShortcut)
                shortcutRow("开始/结束收集", binding: $settings.toggleCollectionShortcut)
                shortcutRow("按序粘贴", binding: $settings.pasteSequenceShortcut)
                Button("恢复默认快捷键") {
                    settings.resetShortcuts()
                    onShortcutsChanged()
                }
            }

            Section("序列粘贴") {
                Picker("粘贴模式", selection: $settings.sequencePasteMode) {
                    ForEach(SequencePasteMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                Picker("内容分隔符", selection: $settings.separatorMode) {
                    ForEach(SeparatorMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                if settings.separatorMode == .custom {
                    TextField("输入分隔符", text: $settings.customSeparator)
                        .textFieldStyle(.roundedBorder)
                }
                Text(settings.separator.isEmpty ? "当前条目之间不插入任何内容" : "当前分隔符：\(visibleSeparator)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("粘贴前显示顺序候选框", isOn: $settings.showSequencePicker)
                Text("开启后，第一次粘贴前可以调整本轮内容顺序；默认顺序仍是复制顺序。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("多行文本粘贴", selection: $settings.multilinePasteMode) {
                    ForEach(MultilinePasteMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                Text("复制内容含换行符时，首次询问后会记住你的选择。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("快捷状态") {
                Toggle("显示桌面快捷状态栏", isOn: $settings.showDesktopStatus)
                Text("开启后会在桌面显示一个小型浮动状态栏，展示当前是否正在收集以及已收集数量。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 430)
        .padding(.top, 8)
        .onChange(of: settings.openPanelShortcut) { _, _ in onShortcutsChanged() }
        .onChange(of: settings.toggleCollectionShortcut) { _, _ in onShortcutsChanged() }
        .onChange(of: settings.pasteSequenceShortcut) { _, _ in onShortcutsChanged() }
    }

    private func shortcutRow(_ title: String, binding: Binding<ShortcutBinding>) -> some View {
        HStack {
            Text(title)
            Spacer()
            ShortcutRecorder(binding: binding)
                .frame(width: 135, height: 26)
        }
    }

    private var visibleSeparator: String {
        settings.separator
            .replacingOccurrences(of: "\n", with: "换行符")
            .replacingOccurrences(of: " ", with: "空格")
    }
}
