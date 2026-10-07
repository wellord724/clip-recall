import AppKit
import Carbon.HIToolbox
import Combine
import Foundation
import SwiftUI

struct ShortcutBinding: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var label: String

    static let openPanel = ShortcutBinding(keyCode: 9, modifiers: UInt32(cmdKey | shiftKey), label: "⌘⇧V")
    static let toggleCollection = ShortcutBinding(keyCode: 8, modifiers: UInt32(cmdKey | shiftKey), label: "⌘⇧C")
    static let pasteSequence = ShortcutBinding(keyCode: 35, modifiers: UInt32(cmdKey | shiftKey), label: "⌘⇧P")
}

enum SeparatorMode: String, CaseIterable, Codable, Identifiable {
    case none
    case space
    case newline
    case custom

    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: return "无分隔符"
        case .space: return "空格"
        case .newline: return "换行"
        case .custom: return "自定义"
        }
    }
}

enum SequencePasteMode: String, CaseIterable, Codable, Identifiable {
    case all
    case oneByOne

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "全部粘贴"
        case .oneByOne: return "逐条粘贴"
        }
    }
}

enum MultilinePasteMode: String, CaseIterable, Codable, Identifiable {
    case ask
    case all
    case oneByOne

    var id: String { rawValue }
    var title: String {
        switch self {
        case .ask: return "首次询问"
        case .all: return "全部输出"
        case .oneByOne: return "逐行粘贴"
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    @Published var openPanelShortcut: ShortcutBinding { didSet { save() } }
    @Published var toggleCollectionShortcut: ShortcutBinding { didSet { save() } }
    @Published var pasteSequenceShortcut: ShortcutBinding { didSet { save() } }
    @Published var separatorMode: SeparatorMode { didSet { save() } }
    @Published var customSeparator: String { didSet { save() } }
    @Published var sequencePasteMode: SequencePasteMode { didSet { save() } }
    @Published var showSequencePicker: Bool { didSet { save() } }
    @Published var multilinePasteMode: MultilinePasteMode { didSet { save() } }
    @Published var showDesktopStatus: Bool { didSet { save() } }

    var separator: String {
        switch separatorMode {
        case .none: return ""
        case .space: return " "
        case .newline: return "\n"
        case .custom: return customSeparator
        }
    }

    init() {
        let defaults = UserDefaults.standard
        openPanelShortcut = Self.load(ShortcutBinding.self, key: "openPanelShortcut") ?? .openPanel
        toggleCollectionShortcut = Self.load(ShortcutBinding.self, key: "toggleCollectionShortcut") ?? .toggleCollection
        pasteSequenceShortcut = Self.load(ShortcutBinding.self, key: "pasteSequenceShortcut") ?? .pasteSequence
        separatorMode = SeparatorMode(rawValue: defaults.string(forKey: "separatorMode") ?? "none") ?? .none
        customSeparator = defaults.string(forKey: "customSeparator") ?? ""
        sequencePasteMode = SequencePasteMode(rawValue: defaults.string(forKey: "sequencePasteMode") ?? "all") ?? .all
        showSequencePicker = defaults.bool(forKey: "showSequencePicker")
        multilinePasteMode = MultilinePasteMode(rawValue: defaults.string(forKey: "multilinePasteMode") ?? "ask") ?? .ask
        showDesktopStatus = defaults.bool(forKey: "showDesktopStatus")
    }

    func resetShortcuts() {
        openPanelShortcut = .openPanel
        toggleCollectionShortcut = .toggleCollection
        pasteSequenceShortcut = .pasteSequence
    }

    private func save() {
        let defaults = UserDefaults.standard
        Self.store(openPanelShortcut, key: "openPanelShortcut")
        Self.store(toggleCollectionShortcut, key: "toggleCollectionShortcut")
        Self.store(pasteSequenceShortcut, key: "pasteSequenceShortcut")
        defaults.set(separatorMode.rawValue, forKey: "separatorMode")
        defaults.set(customSeparator, forKey: "customSeparator")
        defaults.set(sequencePasteMode.rawValue, forKey: "sequencePasteMode")
        defaults.set(showSequencePicker, forKey: "showSequencePicker")
        defaults.set(multilinePasteMode.rawValue, forKey: "multilinePasteMode")
        defaults.set(showDesktopStatus, forKey: "showDesktopStatus")
    }

    private static func store<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

@MainActor
struct ShortcutRecorder: NSViewRepresentable {
    @Binding var binding: ShortcutBinding

    func makeNSView(context: Context) -> ShortcutRecorderField {
        let field = ShortcutRecorderField()
        field.onChange = { newBinding in
            binding = newBinding
        }
        field.stringValue = binding.label
        return field
    }

    func updateNSView(_ nsView: ShortcutRecorderField, context: Context) {
        nsView.stringValue = binding.label
    }
}

@MainActor
final class ShortcutRecorderField: NSTextField {
    var onChange: ((ShortcutBinding) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isEditable = false
        isSelectable = false
        alignment = .center
        bezelStyle = .roundedBezel
        font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        placeholderString = "点击后按快捷键"
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        stringValue = "请按快捷键"
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.contains(.command) || modifiers.contains(.control) || modifiers.contains(.option) else {
            NSSound.beep()
            return
        }

        let binding = ShortcutBinding(
            keyCode: UInt32(event.keyCode),
            modifiers: carbonModifiers(from: modifiers),
            label: shortcutLabel(for: event)
        )
        onChange?(binding)
        stringValue = binding.label
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        return modifiers
    }

    private func shortcutLabel(for event: NSEvent) -> String {
        var label = ""
        let flags = event.modifierFlags
        if flags.contains(.control) { label += "⌃" }
        if flags.contains(.option) { label += "⌥" }
        if flags.contains(.shift) { label += "⇧" }
        if flags.contains(.command) { label += "⌘" }
        label += event.charactersIgnoringModifiers?.uppercased() ?? "按键"
        return label
    }
}
