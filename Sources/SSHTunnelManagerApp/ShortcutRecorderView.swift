import AppKit
import SSHTunnelCore
import SwiftUI

struct ShortcutRecorderView: NSViewRepresentable {
    let isRecording: Bool
    let onCapture: (GlobalShortcut) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> ShortcutRecorderNSView {
        let view = ShortcutRecorderNSView()
        view.onCapture = onCapture
        view.onCancel = onCancel
        return view
    }

    func updateNSView(_ nsView: ShortcutRecorderNSView, context: Context) {
        nsView.onCapture = onCapture
        nsView.onCancel = onCancel
        nsView.isRecording = isRecording
        guard isRecording else {
            return
        }
        DispatchQueue.main.async { [weak nsView] in
            guard let nsView, nsView.isRecording else {
                return
            }
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}

final class ShortcutRecorderNSView: NSView {
    private static let modifierKeyCodes: Set<UInt32> = [
        0x36, 0x37, // Command
        0x38, 0x3C, // Shift
        0x39,       // Caps Lock
        0x3A, 0x3D, // Option
        0x3B, 0x3E, // Control
        0x3F        // Function
    ]

    var isRecording = false {
        didSet {
            guard isRecording != oldValue else {
                return
            }
            if isRecording {
                startCapturing()
            } else {
                stopCapturing()
            }
        }
    }
    var onCapture: ((GlobalShortcut) -> Void)?
    var onCancel: (() -> Void)?
    private var localMonitor: Any?
    private var keyStateTimer: Timer?
    private var previouslyPressedKeyCodes: Set<UInt32> = []

    override var acceptsFirstResponder: Bool { true }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            isRecording = false
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        capture(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording, event.type == .keyDown else {
            return super.performKeyEquivalent(with: event)
        }
        capture(event)
        return true
    }

    static func newlyPressedPrimaryKey(
        current: Set<UInt32>,
        previous: Set<UInt32>
    ) -> UInt32? {
        current
            .subtracting(previous)
            .filter { !modifierKeyCodes.contains($0) }
            .sorted()
            .first
    }

    static func modifiers(from flags: CGEventFlags) -> Set<GlobalShortcutModifier> {
        var modifiers: Set<GlobalShortcutModifier> = []
        if flags.contains(.maskControl) { modifiers.insert(.control) }
        if flags.contains(.maskAlternate) { modifiers.insert(.option) }
        if flags.contains(.maskShift) { modifiers.insert(.shift) }
        if flags.contains(.maskCommand) { modifiers.insert(.command) }
        return modifiers
    }

    private func startCapturing() {
        previouslyPressedKeyCodes = pressedKeyCodes()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isRecording else {
                return event
            }
            self.capture(event)
            return nil
        }

        let timer = Timer(
            timeInterval: 1.0 / 120.0,
            target: self,
            selector: #selector(pollKeyStateTimerFired),
            userInfo: nil,
            repeats: true
        )
        keyStateTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopCapturing() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        keyStateTimer?.invalidate()
        keyStateTimer = nil
        previouslyPressedKeyCodes = []
    }

    private func capture(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: Set<GlobalShortcutModifier> = []
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }
        finishCapture(keyCode: UInt32(event.keyCode), modifiers: modifiers)
    }

    private func pollKeyState() {
        guard isRecording else {
            return
        }
        let currentKeyCodes = pressedKeyCodes()
        let primaryKeyCode = Self.newlyPressedPrimaryKey(
            current: currentKeyCodes,
            previous: previouslyPressedKeyCodes
        )
        previouslyPressedKeyCodes = currentKeyCodes
        guard let primaryKeyCode else {
            return
        }
        finishCapture(
            keyCode: primaryKeyCode,
            modifiers: Self.modifiers(from: CGEventSource.flagsState(.combinedSessionState))
        )
    }

    @objc private func pollKeyStateTimerFired() {
        pollKeyState()
    }

    private func pressedKeyCodes() -> Set<UInt32> {
        Set(
            (UInt32(0)...UInt32(0x7F)).filter {
                CGEventSource.keyState(.combinedSessionState, key: CGKeyCode($0))
            }
        )
    }

    private func finishCapture(
        keyCode: UInt32,
        modifiers: Set<GlobalShortcutModifier>
    ) {
        guard isRecording else {
            return
        }
        isRecording = false
        if keyCode == 0x35 {
            onCancel?()
            return
        }

        onCapture?(GlobalShortcut(keyCode: keyCode, modifiers: modifiers))
    }
}
