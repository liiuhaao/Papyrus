// PapyrusApp.swift
// Papyrus - Academic Paper Manager for macOS

import SwiftUI
import AppKit
import Carbon
import PapyrusCore

private struct PapyrusCommandMenus: Commands {
    @ObservedObject var config: AppConfig

    var body: some Commands {
        CommandMenu(AppShortcutConfig.keyboardGroups[0].title) {
            commandItems(AppShortcutConfig.keyboardGroups[0].actions)
        }
        CommandMenu(AppShortcutConfig.keyboardGroups[1].title) {
            commandItems(AppShortcutConfig.keyboardGroups[1].actions)
        }
        CommandMenu(AppShortcutConfig.keyboardGroups[2].title) {
            commandItems(AppShortcutConfig.keyboardGroups[2].actions)
        }
        CommandMenu(AppShortcutConfig.keyboardGroups[3].title) {
            commandItems(AppShortcutConfig.keyboardGroups[3].actions)
        }
    }

    @ViewBuilder
    private func commandItems(_ actions: [InputAction]) -> some View {
        ForEach(actions) { action in
            Button(action.displayName) {
                guard let command = AppCommand(inputAction: action) else { return }
                NotificationCenter.default.post(
                    name: .executeLibraryCommand,
                    object: nil,
                    userInfo: [
                        "command": command.rawValue,
                        "action": action.rawValue,
                    ]
                )
            }
            .keyboardShortcut(config.keyboardShortcut(for: action))
        }
    }
}

// AppDelegate to handle window focus
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var hasAttemptedCLIInstall = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )

        BrowserImportServer.shared.start()

        // Ensure window is properly configured
        if let window = NSApplication.shared.windows.first {
            configureWindow(window)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        BrowserImportServer.shared.stop()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Bring window to front when app becomes active
        if let window = NSApplication.shared.windows.first {
            window.makeKeyAndOrderFront(nil)
        }

        guard !hasAttemptedCLIInstall else { return }
        hasAttemptedCLIInstall = true
        CommandLineToolInstaller.ensureInstalledIfNeeded()
    }
    
    func windowDidBecomeKey(_ notification: Notification) {
        // Keep window at normal level (not floating)
        if let window = notification.object as? NSWindow {
            window.level = .normal
        }
    }
    
    private func configureWindow(_ window: NSWindow) {
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        window.center()
        window.acceptsMouseMovedEvents = true

        window.titlebarAppearsTransparent = false
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarSeparatorStyle = .line
    }

    @objc private func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        guard let rawURL = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: rawURL) else {
            return
        }

        Task { @MainActor in
            BrowserImportURLDispatcher.shared.enqueue(url)
        }
    }
}

@main
struct PapyrusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var config = AppConfig.shared

    init() {
        // Must be called before run loop starts to get Dock icon + proper window focus
        NSApplication.shared.setActivationPolicy(.regular)
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
                .preferredColorScheme(config.resolvedColorScheme)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) { }
            PapyrusCommandMenus(config: config)
        }
        Settings {
            SettingsView()
                .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
                .preferredColorScheme(config.resolvedColorScheme)
        }
    }
}
