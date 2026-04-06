import AppKit
import SwiftUI

@MainActor
final class ShortcutRecorderController: ObservableObject {
    @Published private(set) var recordingAction: InputAction?
    @Published private(set) var recordingPreview: String = ""
    @Published private(set) var recordingError: String?

    private var rowFrames: [String: CGRect] = [:]
    private var keyDownMonitor: Any?
    private var flagsMonitor: Any?
    private var clickMonitor: Any?
    private var commitBinding: ((InputAction, String) -> Void)?

    func install(onCommit: @escaping (InputAction, String) -> Void) {
        commitBinding = onCommit
        removeMonitors()

        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self, self.recordingAction != nil else { return event }
            self.recordingPreview = AppShortcutConfig.bindingPreview(from: event.modifierFlags)
            self.recordingError = nil
            return nil
        }

        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let action = self.recordingAction else { return event }
            if event.keyCode == 53 {
                self.cancel()
                return nil
            }
            guard let binding = AppShortcutConfig.bindingString(from: event) else {
                self.recordingError = "Not allowed"
                return nil
            }
            self.recordingPreview = binding
            self.recordingError = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
                guard let self, self.recordingAction == action else { return }
                self.commitBinding?(action, binding)
                self.cancel()
            }
            return nil
        }

        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self, let action = self.recordingAction else { return event }
            guard let frame = self.rowFrames[action.rawValue], let window = event.window else {
                self.cancel()
                return event
            }
            let pointInScreen = window.convertPoint(toScreen: event.locationInWindow)
            if !frame.contains(pointInScreen) {
                self.cancel()
            }
            return event
        }
    }

    func uninstall() {
        removeMonitors()
        cancel()
        commitBinding = nil
    }

    func beginOrToggle(_ action: InputAction) {
        if recordingAction == action {
            cancel()
        } else {
            recordingAction = action
            recordingPreview = ""
            recordingError = nil
        }
    }

    func cancel() {
        recordingAction = nil
        recordingPreview = ""
        recordingError = nil
    }

    func updateRowFrame(action: InputAction, frame: CGRect) {
        if let existing = rowFrames[action.rawValue],
           abs(existing.minX - frame.minX) < 0.5,
           abs(existing.minY - frame.minY) < 0.5,
           abs(existing.width - frame.width) < 0.5,
           abs(existing.height - frame.height) < 0.5 {
            return
        }
        rowFrames[action.rawValue] = frame
    }

    func isRecording(_ action: InputAction) -> Bool {
        recordingAction == action
    }

    func preview(for action: InputAction) -> String? {
        recordingAction == action ? recordingPreview : nil
    }

    func statusMessage(for action: InputAction) -> String? {
        guard recordingAction == action else { return nil }
        return recordingError
    }

    private func removeMonitors() {
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
            self.keyDownMonitor = nil
        }
        if let flagsMonitor {
            NSEvent.removeMonitor(flagsMonitor)
            self.flagsMonitor = nil
        }
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
    }
}
