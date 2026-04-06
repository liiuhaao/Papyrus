import AppKit

@MainActor
final class SingleKeyShortcutMonitor: ObservableObject {
    var handleBinding: ((String) -> Bool)?

    private var monitor: Any?

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let binding = AppShortcutConfig.bindingString(from: event) else { return event }
        guard handleBinding?(binding) == true else { return event }
        return nil
    }
}
