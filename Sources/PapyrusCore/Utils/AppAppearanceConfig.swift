import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

@MainActor
final class AppAppearanceConfig {
    private var systemAppearanceObserver: NSObjectProtocol?

    func apply(
        appearance: AppAppearance,
        resolvedColorScheme: inout ColorScheme
    ) {
        #if canImport(AppKit)
        let app = NSApp
        switch appearance {
        case .system:
            app?.appearance = nil
            resolvedColorScheme = systemColorScheme()
        case .light:
            removeSystemAppearanceObserver()
            app?.appearance = NSAppearance(named: .aqua)
            resolvedColorScheme = .light
        case .dark:
            removeSystemAppearanceObserver()
            app?.appearance = NSAppearance(named: .darkAqua)
            resolvedColorScheme = .dark
        }
        #else
        resolvedColorScheme = appearance.colorScheme ?? .light
        #endif
    }

    func startSystemAppearanceObservation(onChange: @escaping @MainActor () -> Void) {
        #if canImport(AppKit)
        if systemAppearanceObserver == nil {
            systemAppearanceObserver = DistributedNotificationCenter.default().addObserver(
                forName: .init("AppleInterfaceThemeChangedNotification"),
                object: nil,
                queue: .main
            ) { _ in
                Task { @MainActor in onChange() }
            }
        }
        #endif
    }

    func stopSystemAppearanceObservation() {
        removeSystemAppearanceObserver()
    }

    func currentSystemColorScheme() -> ColorScheme {
        systemColorScheme()
    }

    private func systemColorScheme() -> ColorScheme {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark" ? .dark : .light
    }

    private func removeSystemAppearanceObserver() {
        #if canImport(AppKit)
        if let observer = systemAppearanceObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            systemAppearanceObserver = nil
        }
        #endif
    }
}
