import AppKit
import SwiftUI

struct ShortcutFocusObserver: NSViewRepresentable {
    let onUpdate: () -> Void

    init(onUpdate: @escaping () -> Void) {
        self.onUpdate = onUpdate
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onUpdate: onUpdate)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.installIfNeeded()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onUpdate = onUpdate
        context.coordinator.installIfNeeded()
        // Avoid mutating SwiftUI state during the current view update pass.
        context.coordinator.refreshAsync()
    }

    final class Coordinator: NSObject {
        var onUpdate: () -> Void
        private var monitor: Any?
        private var observers: [NSObjectProtocol] = []
        private var isRefreshScheduled = false

        init(onUpdate: @escaping () -> Void) {
            self.onUpdate = onUpdate
        }

        func installIfNeeded() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
                self?.refreshAsync()
                return event
            }

            let center = NotificationCenter.default
            observers.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] _ in
                self?.refresh()
            })
            observers.append(center.addObserver(forName: NSWindow.didResignKeyNotification, object: nil, queue: .main) { [weak self] _ in
                self?.refresh()
            })
        }

        func refresh() {
            refreshAsync()
        }

        func refreshAsync() {
            guard !isRefreshScheduled else { return }
            isRefreshScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isRefreshScheduled = false
                self.onUpdate()
            }
        }

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            let center = NotificationCenter.default
            for observer in observers {
                center.removeObserver(observer)
            }
        }
    }
}
