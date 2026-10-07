import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = ClipboardStore()
    private var monitor: ClipboardMonitor!
    private let pasteController = PasteController()
    private let hotKeyManager = HotKeyManager()
    private let settings = AppSettings()
    private var statusItem: NSStatusItem!
    private var panel: NSPanel!
    private var settingsWindow: NSWindow?
    private var desktopStatusPanel: NSPanel!
    private var desktopStatusLabel: NSTextField!
    private var statusSubscription: AnyCancellable?
    private var settingsSubscription: AnyCancellable?
    private var sequenceTask: Task<Void, Never>?
    private var sequencePickerWindow: NSWindow?
    private var sequencePickerModel: SequencePickerModel?
    private var multilineChoiceWindow: NSWindow?
    private var pendingMultilinePayload: ClipboardPayload?
    private var pendingPasteMode: PendingPasteMode?
    private var sequencePickerShownForCurrentSequence = false
    private var targetApplication: NSRunningApplication?
    private var lastExternalApplication: NSRunningApplication?

    private enum PendingPasteMode: Equatable {
        case all
        case next
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(externalApplicationDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        registerHotKeys()
        configureDesktopStatusPanel()
        statusSubscription = store.$isCollecting.combineLatest(store.$sequenceCount).sink { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.sequencePickerModel?.update(items: self.store.sequenceItems())
                self.updateStatusIndicators()
                if self.store.isCollecting {
                    self.resizeSequencePicker()
                    self.positionSequencePicker(at: self.store.latestCaptureLocation)
                }
            }
        }
        settingsSubscription = settings.objectWillChange.sink { [weak self] in
            MainActor.assumeIsolated {
                self?.updateStatusIndicators()
            }
        }
        updateStatusIndicators()
        monitor = ClipboardMonitor(store: store)
        monitor.start()
    }

    private func registerHotKeys() {
        hotKeyManager.register(
            openPanelShortcut: settings.openPanelShortcut,
            toggleCollectionShortcut: settings.toggleCollectionShortcut,
            pasteSequenceShortcut: settings.pasteSequenceShortcut,
            openPanel: { [weak self] in self?.togglePanel() },
            toggleCollection: { [weak self] in self?.toggleSequence() },
            pasteSequence: { [weak self] in self?.pasteSequence() }
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        hotKeyManager.stop()
        statusSubscription?.cancel()
        settingsSubscription?.cancel()
        sequenceTask?.cancel()
        monitor.stop()
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "剪贴板")
        statusItem.button?.title = "剪贴板"
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.toolTip = "打开剪贴板历史"
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.target = self

        let content = ClipboardView(
            store: store,
            onPaste: { [weak self] item in self?.paste(item) },
            onStartSequence: { [weak self] in self?.toggleSequence() },
            onPasteSequence: { [weak self] in self?.requestPaste(.all) },
            onPasteNext: { [weak self] in self?.requestPaste(.next) },
            onClear: { [weak self] in
                self?.store.clear()
                self?.dismissSequencePicker()
            },
            onOpenAccessibility: { [weak self] in self?.openAccessibilitySettings() },
            onOpenSettings: { [weak self] in self?.openSettings() },
            onQuit: { NSApp.terminate(nil) }
        )
        let controller = NSHostingController(rootView: content)
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "剪贴板"
        panel.contentViewController = controller
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.minSize = NSSize(width: 380, height: 420)
    }

    private func configureDesktopStatusPanel() {
        desktopStatusLabel = NSTextField(labelWithString: "未收集")
        desktopStatusLabel.alignment = .center
        desktopStatusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        desktopStatusLabel.textColor = .secondaryLabelColor

        desktopStatusPanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 150, height: 34),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        desktopStatusPanel.level = .floating
        desktopStatusPanel.isOpaque = false
        desktopStatusPanel.backgroundColor = .clear
        desktopStatusPanel.hasShadow = true
        desktopStatusPanel.ignoresMouseEvents = true
        desktopStatusPanel.contentView = NSVisualEffectView()
        guard let effectView = desktopStatusPanel.contentView as? NSVisualEffectView else { return }
        effectView.material = .hudWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 10
        effectView.addSubview(desktopStatusLabel)
        desktopStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            desktopStatusLabel.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 10),
            desktopStatusLabel.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -10),
            desktopStatusLabel.centerYAnchor.constraint(equalTo: effectView.centerYAnchor)
        ])
    }

    private func updateStatusIndicators() {
        let title: String
        if store.isCollecting {
            title = store.sequenceCount == 0 ? "收集 · 待第1条" : "收集 \(store.sequenceCount)"
        } else {
            title = "剪贴板"
        }
        statusItem.button?.title = title
        if store.isCollecting {
            desktopStatusLabel?.stringValue = store.sequenceCount == 0 ? "正在收集 · 等待第 1 条" : "正在收集 · \(store.sequenceCount) 条"
        } else {
            desktopStatusLabel?.stringValue = "未收集"
        }
        guard let desktopStatusPanel else { return }
        if settings.showDesktopStatus {
            positionDesktopStatusPanel()
            desktopStatusPanel.orderFrontRegardless()
        } else {
            desktopStatusPanel.orderOut(nil)
        }
    }

    private func positionDesktopStatusPanel() {
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let size = desktopStatusPanel.frame.size
        desktopStatusPanel.setFrameOrigin(NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.maxY - size.height - 12
        ))
    }

    @objc private func togglePopover() {
        togglePanel()
    }

    private func togglePanel() {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            targetApplication = lastExternalApplication ?? externalFrontmostApplication()
            NSApp.activate(ignoringOtherApps: true)
            if panel.frame.origin == .zero {
                panel.center()
            }
            panel.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func externalApplicationDidActivate(_ notification: Notification) {
        guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              application.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        lastExternalApplication = application
    }

    private func externalFrontmostApplication() -> NSRunningApplication? {
        guard let application = NSWorkspace.shared.frontmostApplication,
              application.bundleIdentifier != Bundle.main.bundleIdentifier else { return nil }
        return application
    }

    private func paste(_ item: ClipboardItem) {
        guard let payload = store.payload(for: item.id) else { return }
        if let text = payload.text, text.contains("\n") {
            switch settings.multilinePasteMode {
            case .ask:
                showMultilineChoice(for: payload)
                return
            case .all:
                break
            case .oneByOne:
                prepareMultilineSequence(from: payload)
                return
            }
        }
        pasteRaw(payload)
    }

    private func pasteRaw(_ payload: ClipboardPayload) {
        let application = targetApplication
        panel.orderOut(nil)
        activateTarget(application)
        sequenceTask?.cancel()
        sequenceTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(180))
                try self?.pasteController.paste(payload)
            } catch is CancellationError {
                return
            } catch {
                self?.showPermissionAlert(error)
            }
        }
    }

    private func showMultilineChoice(for payload: ClipboardPayload) {
        guard let text = payload.text else { return }
        pendingMultilinePayload = payload
        let lines = Self.splitLines(text)
        let preview = lines.prefix(2).joined(separator: " / ")
        let view = MultilineChoiceView(
            lineCount: lines.count,
            preview: preview,
            onAll: { [weak self] in
                self?.settings.multilinePasteMode = .all
                self?.closeMultilineChoice()
                if let payload = self?.pendingMultilinePayload {
                    self?.pendingMultilinePayload = nil
                    self?.pasteRaw(payload)
                }
            },
            onOneByOne: { [weak self] in
                self?.settings.multilinePasteMode = .oneByOne
                guard let payload = self?.pendingMultilinePayload else { return }
                self?.pendingMultilinePayload = nil
                self?.closeMultilineChoice()
                self?.prepareMultilineSequence(from: payload)
            },
            onCancel: { [weak self] in
                self?.pendingMultilinePayload = nil
                self?.closeMultilineChoice()
            }
        )
        let controller = NSHostingController(rootView: view)
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 142),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.contentViewController = controller
        window.center()
        multilineChoiceWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func closeMultilineChoice() {
        multilineChoiceWindow?.orderOut(nil)
        multilineChoiceWindow = nil
    }

    private func prepareMultilineSequence(from payload: ClipboardPayload) {
        guard let text = payload.text else { return }
        let linePayloads = Self.splitLines(text).map { line in
            let data = Data(line.utf8)
            let item = ClipboardItem(
                id: UUID(),
                createdAt: Date(),
                sourceApp: payload.item.sourceApp,
                kind: .text,
                preview: line.prefix(240).description,
                types: ["public.utf8-plain-text"],
                byteSize: data.count
            )
            return ClipboardPayload(item: item, dataByType: ["public.utf8-plain-text": data])
        }
        store.replaceSequence(with: linePayloads)
        sequencePickerShownForCurrentSequence = false
    }

    private static func splitLines(_ text: String) -> [String] {
        var normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        normalized = normalized.replacingOccurrences(of: "\r", with: "\n")
        return normalized.components(separatedBy: "\n")
    }

    private func toggleSequence() {
        if store.isCollecting {
            monitor.captureNow()
            store.finishCollecting()
        } else {
            dismissSequencePicker()
            store.startSequence()
        }
    }

    private func dismissSequencePicker() {
        sequencePickerWindow?.orderOut(nil)
        sequencePickerModel = nil
        sequencePickerShownForCurrentSequence = false
        pendingPasteMode = nil
    }

    private func pasteSequence() {
        if settings.sequencePasteMode == .oneByOne {
            requestPaste(.next)
        } else {
            requestPaste(.all)
        }
    }

    private func requestPaste(_ mode: PendingPasteMode) {
        guard !store.sequencePayloads().isEmpty else { return }
        targetApplication = lastExternalApplication ?? externalFrontmostApplication() ?? targetApplication
        let oneByOne = settings.sequencePasteMode == .oneByOne
        if oneByOne && sequencePickerWindow?.isVisible == true {
            performPaste(.next)
            return
        }
        if (settings.showSequencePicker || oneByOne) && !sequencePickerShownForCurrentSequence {
            pendingPasteMode = mode
            panel.orderOut(nil)
            showSequencePicker(confirmed: oneByOne, oneByOne: oneByOne)
            return
        }
        performPaste(mode)
    }

    private func showSequencePicker(confirmed: Bool = false, oneByOne: Bool? = nil) {
        let items = store.sequenceItems()
        let model = SequencePickerModel(items: items)
        model.isConfirmed = confirmed
        model.onReorder = { [weak self] ids in
            self?.store.reorderSequence(with: ids)
        }
        sequencePickerModel = model
        let view = SequencePickerView(
            model: model,
            isOneByOne: oneByOne ?? (settings.sequencePasteMode == .oneByOne),
            onCancel: { [weak self] in
                self?.dismissSequencePicker()
            },
            onConfirm: { [weak self] ids in
                guard let self else { return }
                self.store.reorderSequence(with: ids)
                model.isConfirmed = true
                self.sequencePickerShownForCurrentSequence = true
                let mode = self.pendingPasteMode ?? .all
                self.pendingPasteMode = nil
                if mode == .all {
                    self.sequencePickerWindow?.orderOut(nil)
                } else {
                    self.sequencePickerWindow?.orderFrontRegardless()
                }
                self.performPaste(mode)
            },
            onPasteNext: { [weak self] in self?.pasteNextSequenceItem() }
        )
        let controller = NSHostingController(rootView: view)
        let height = min(max(128, CGFloat(items.count * 31 + 82)), 340)
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 350, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.contentViewController = controller
        window.isReleasedWhenClosed = false
        sequencePickerWindow = window
        positionSequencePicker(at: NSEvent.mouseLocation)
        window.orderFrontRegardless()
    }

    private func positionSequencePicker(at pointer: NSPoint) {
        guard let window = sequencePickerWindow else { return }
        let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }
        let size = window.frame.size
        let margin: CGFloat = 8
        var x = pointer.x + 14
        if x + size.width > visibleFrame.maxX - margin {
            x = pointer.x - size.width - 14
        }
        x = min(max(x, visibleFrame.minX + margin), visibleFrame.maxX - size.width - margin)

        var y = pointer.y - size.height - 18
        if y < visibleFrame.minY + margin {
            y = pointer.y + 18
        }
        y = min(max(y, visibleFrame.minY + margin), visibleFrame.maxY - size.height - margin)
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func resizeSequencePicker() {
        guard let window = sequencePickerWindow else { return }
        let count = sequencePickerModel?.items.count ?? 0
        let height = min(max(128, CGFloat(count * 31 + 82)), 340)
        var frame = window.frame
        frame.size.height = height
        window.setFrame(frame, display: true, animate: false)
    }

    private func performPaste(_ mode: PendingPasteMode) {
        switch mode {
        case .all:
            pasteAllSequence()
        case .next:
            pasteNextSequenceItem()
        }
    }

    private func pasteAllSequence() {
        let payloads = store.prepareSequenceForPasting()
        guard !payloads.isEmpty else { return }
        let application = targetApplication
        panel.orderOut(nil)
        sequencePickerWindow?.orderOut(nil)
        activateTarget(application)
        sequenceTask?.cancel()
        sequenceTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(250))
                try await self?.pasteController.pasteSequence(payloads, separator: self?.settings.separator ?? "")
                self?.store.clearSequence()
                self?.dismissSequencePicker()
            } catch is CancellationError {
                return
            } catch {
                self?.showPermissionAlert(error)
            }
        }
    }

    private func pasteNextSequenceItem() {
        guard let payload = store.nextSequencePayload() else { return }
        let application = targetApplication
        if !sequencePickerShownForCurrentSequence {
            panel.orderOut(nil)
        }
        activateTarget(application)
        sequenceTask?.cancel()
        sequenceTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(120))
                try self?.pasteController.paste(payload)
                let completed = self?.store.advanceSequence() == true
                self?.sequencePickerModel?.remove(id: payload.item.id)
                if completed {
                    self?.store.clearSequence()
                    self?.dismissSequencePicker()
                } else {
                    self?.sequencePickerWindow?.orderFrontRegardless()
                }
            } catch is CancellationError {
                return
            } catch {
                self?.showPermissionAlert(error)
            }
        }
    }

    private func activateTarget(_ application: NSRunningApplication?) {
        application?.activate(options: [.activateAllWindows])
    }

    private func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    private func openSettings() {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = SettingsView(settings: settings) { [weak self] in
            self?.registerHotKeys()
        }
        let controller = NSHostingController(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 430),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "剪贴板设置"
        window.contentViewController = controller
        window.isReleasedWhenClosed = false
        window.center()
        settingsWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func showPermissionAlert(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "无法完成粘贴"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "打开设置")
        alert.addButton(withTitle: "稍后")
        if alert.runModal() == .alertFirstButtonReturn {
            openAccessibilitySettings()
        }
    }
}
