// SettingsView.swift
// Preferences window

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CoreServices

package struct SettingsView: View {
    @StateObject private var config = AppConfig.shared
    @State private var pathError: String?
    @State private var venuesError: String?
    @State private var isRefreshingVenues = false
    @State private var metadataPreset: MetadataPreset = .general
    @State private var semanticScholarKey: String = ""
    @State private var easyScholarKey: String = ""
    @State private var rankSourceText: String = ""
    @State private var tagNamespaceText: String = ""
    @State private var listTagNamespaceText: String = ""
    @State private var venuesText: String = ""
    @State private var keyboardBindings: [String: String] = [:]
    @StateObject private var shortcutRecorder = ShortcutRecorderController()
    @State private var selectedTab: SettingsTab = .general
    @State private var pdfAppPath: String = ""
    @State private var notesAppPath: String = ""
    @State private var pendingLibraryURL: URL? = nil
    @State private var showMigrationPrompt = false
    @State private var isMigrating = false
    @State private var migrationProgress: (done: Int, total: Int)? = nil

    @FocusState private var apiFieldFocused: SettingsAPIField?
    @FocusState private var rankSourcesFocused: Bool
    @FocusState private var tagNamespacesFocused: Bool
    @FocusState private var listTagNamespacesFocused: Bool
    @FocusState private var venuesFocused: Bool

    package init() {}

    package var body: some View {
        interactionSyncedBody
    }

    private var interactionSyncedBody: some View {
        configSyncedBody
            .onChange(of: apiFieldFocused) { old, _ in
                if old == .semantic { applySemanticScholarKey() }
                if old == .easy { applyEasyScholarKey() }
            }
            .onChange(of: venuesFocused) { _, focused in
                if !focused { applyVenues() }
            }
            .onChange(of: rankSourcesFocused) { _, focused in
                if !focused { applyRankSources() }
            }
            .onChange(of: tagNamespacesFocused) { _, focused in
                if !focused { applyTagNamespaces() }
            }
            .onChange(of: listTagNamespacesFocused) { _, focused in
                if !focused { applyListTagNamespaces() }
            }
            .onChange(of: keyboardBindings) { _, _ in
                applyKeyboardBindings()
            }
            .onChange(of: selectedTab) { _, _ in
                flushDraftSettings()
                shortcutRecorder.cancel()
            }
    }

    private var configSyncedBody: some View {
        lifecycleBody
            .onChange(of: config.semanticScholarKey) { _, newValue in
                if semanticScholarKey != newValue { semanticScholarKey = newValue }
            }
            .onChange(of: config.metadataPreset) { _, newValue in
                if metadataPreset != newValue { metadataPreset = newValue }
            }
            .onChange(of: config.easyscholarKey) { _, newValue in
                if easyScholarKey != newValue { easyScholarKey = newValue }
            }
            .onChange(of: config.customVenues) { _, _ in
                venuesText = venuesTextFromConfig()
            }
            .onChange(of: config.rankBadgeSources) { _, _ in
                rankSourceText = RankSourceConfig.formatText(config.rankBadgeSources)
            }
            .onChange(of: config.tagNamespaces) { _, _ in
                tagNamespaceText = TagNamespaceSupport.formatText(config.tagNamespaces)
            }
            .onChange(of: config.listTagPreferredNamespaces) { _, _ in
                listTagNamespaceText = TagNamespaceSupport.formatText(config.listTagPreferredNamespaces)
            }
    }

    private var lifecycleBody: some View {
        dialogBody
            .onAppear(perform: handleAppear)
            .onDisappear(perform: handleDisappear)
    }

    private var dialogBody: some View {
        settingsRoot
            .frame(width: 660, height: 640)
            .overlay {
                SettingsMigrationOverlay(progress: isMigrating ? migrationProgress : nil)
            }
            .appDialog(isPresented: $showMigrationPrompt) {
                if let url = pendingLibraryURL {
                    LibraryMigrationDialog(
                        destinationName: url.lastPathComponent,
                        onMigrate:    { showMigrationPrompt = false; migrateLibrary(to: url, migrate: true) },
                        onUpdatePath: { showMigrationPrompt = false; migrateLibrary(to: url, migrate: false) },
                        onCancel:     { showMigrationPrompt = false; pendingLibraryURL = nil }
                    )
                }
            }
    }

    private var settingsRoot: some View {
        VStack(spacing: 0) {
            SettingsTopTabBar(selectedTab: $selectedTab)

            Divider()

            ScrollView {
                tabContent
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(AppMetrics.panelPadding)
                    .id(selectedTab)
            }
        }
    }

    private func handleAppear() {
        reloadDraftsFromConfig()
        shortcutRecorder.install { action, binding in
            keyboardBindings[action.rawValue] = binding
        }
    }

    private func handleDisappear() {
        flushDraftSettings()
        shortcutRecorder.uninstall()
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .general:    generalTab
        case .library:    libraryTab
        case .metadata:   metadataTab
        case .feed:       FeedSettingsPanel()
        case .extensions: ExtensionsSettingsPanel()
        case .keyboard:   keyboardTab
        }
    }

    // MARK: - General Tab

    private var generalTab: some View {
        GeneralSettingsPanel(
            config: config,
            pdfOpenModeDisplay: pdfOpenModeDisplay,
            pdfOpenModeIcon: pdfOpenModeIcon,
            notesOpenModeDisplay: notesOpenModeDisplay,
            notesOpenModeIcon: notesOpenModeIcon,
            onChoosePDFApp: choosePDFApp,
            onChooseNotesApp: chooseNotesApp
        )
    }

    private var libraryTab: some View {
        LibrarySettingsPanel(
            config: config,
            currentLibraryPath: currentLibraryPath,
            pathError: pathError,
            onChooseLibraryFolder: chooseLibraryFolder,
            onResetLibraryPath: {
                pendingLibraryURL = defaultLibraryURL()
                showMigrationPrompt = true
            },
            tagNamespaceText: $tagNamespaceText,
            listTagNamespaceText: $listTagNamespaceText,
            tagNamespacesFocused: $tagNamespacesFocused,
            listTagNamespacesFocused: $listTagNamespacesFocused,
            onApplyTagNamespaces: applyTagNamespaces,
            onApplyListTagNamespaces: applyListTagNamespaces
        )
    }


    private var keyboardTab: some View {
        KeyboardSettingsPanel(
            actions: AppConfig.allShortcutActions,
            bindingForAction: keyboardBinding(for:),
            shortcutLabel: { $0.displayName },
            validationMessage: keyboardValidationMessage(for:value:),
            recordingStatusMessage: { shortcutRecorder.statusMessage(for: $0) },
            isRecording: { shortcutRecorder.isRecording($0) },
            recordingPreview: { shortcutRecorder.preview(for: $0) },
            onToggleRecording: shortcutRecorder.beginOrToggle(_:),
            onClear: clearShortcut(for:),
            onRestoreDefaults: restoreDefaultKeyboardBindings,
            onRowFrameChange: shortcutRecorder.updateRowFrame(action:frame:)
        )
    }

    // MARK: - Metadata Tab

    private var metadataTab: some View {
        MetadataSettingsPanel(
            config: config,
            semanticScholarKey: $semanticScholarKey,
            easyScholarKey: $easyScholarKey,
            rankSourceText: $rankSourceText,
            venuesText: $venuesText,
            venuesError: venuesError,
            apiFieldFocused: $apiFieldFocused,
            rankSourcesFocused: $rankSourcesFocused,
            venuesFocused: $venuesFocused,
            isRefreshingVenues: isRefreshingVenues,
            onApplySemanticScholarKey: applySemanticScholarKey,
            onApplyEasyScholarKey: applyEasyScholarKey,
            onApplyRankSources: applyRankSources,
            onRefreshVenueRankings: refreshVenueRankings
        )
    }

    // MARK: - Apply

    private func applySemanticScholarKey() { try? config.setSemanticScholarKey(semanticScholarKey) }
    private func applyMetadataPreset()     { try? config.setMetadataPreset(metadataPreset) }
    private func applyEasyScholarKey()     { try? config.setEasyScholarKey(easyScholarKey) }
    private func applyRankSources()        { try? config.setRankBadgeSources(RankSourceConfig.parseText(rankSourceText)) }
    private func applyTagNamespaces()      { try? config.setTagNamespaces(TagNamespaceSupport.parseText(tagNamespaceText)) }
    private func applyListTagNamespaces()  { try? config.setListTagPreferredNamespaces(TagNamespaceSupport.parseText(listTagNamespaceText)) }

    private func refreshVenueRankings() {
        isRefreshingVenues = true
        NotificationCenter.default.post(name: .refreshVenueRankings, object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            isRefreshingVenues = false
        }
    }

    private func applyVenues() {
        do {
            let parsed = try parseVenues(from: venuesText)
            try config.setCustomVenues(parsed)
            venuesError = nil
        } catch {
            venuesError = error.localizedDescription
        }
    }

    private func flushDraftSettings() {
        applyMetadataPreset()
        applySemanticScholarKey()
        applyEasyScholarKey()
        applyRankSources()
        applyTagNamespaces()
        applyListTagNamespaces()
        applyVenues()
        applyKeyboardBindings()
    }

    // MARK: - Reload

    private func reloadDraftsFromConfig() {
        metadataPreset      = config.metadataPreset
        semanticScholarKey  = config.semanticScholarKey
        easyScholarKey      = config.easyscholarKey
        rankSourceText      = RankSourceConfig.formatText(config.rankBadgeSources)
        tagNamespaceText    = TagNamespaceSupport.formatText(config.tagNamespaces)
        listTagNamespaceText = TagNamespaceSupport.formatText(config.listTagPreferredNamespaces)
        venuesText          = venuesTextFromConfig()
        keyboardBindings    = keyboardBindingsFromConfig()
        pdfAppPath          = config.pdfOpenAppPath
        notesAppPath        = config.notesOpenAppPath
    }

    private var pdfOpenModeDisplay: String {
        switch config.pdfOpenMode {
        case .defaultApp:
            if let name = defaultPDFHandlerName() {
                return "\(name) (Default App)"
            }
            return "System Default"
        case .customApp:
            guard !config.pdfOpenAppPath.isEmpty else { return "No app selected" }
            return URL(fileURLWithPath: config.pdfOpenAppPath).deletingPathExtension().lastPathComponent
        }
    }

    private var notesOpenModeDisplay: String {
        switch config.notesOpenMode {
        case .defaultApp:
            if let name = defaultMarkdownHandlerName() {
                return "\(name) (Default App)"
            }
            return "System Default"
        case .customApp:
            guard !config.notesOpenAppPath.isEmpty else { return "No app selected" }
            return URL(fileURLWithPath: config.notesOpenAppPath).deletingPathExtension().lastPathComponent
        }
    }

    private var pdfOpenModeIcon: NSImage? {
        switch config.pdfOpenMode {
        case .customApp:
            let path = config.pdfOpenAppPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else { return nil }
            return NSWorkspace.shared.icon(forFile: path)
        case .defaultApp:
            return defaultPDFHandlerIcon()
        }
    }

    private var notesOpenModeIcon: NSImage? {
        switch config.notesOpenMode {
        case .customApp:
            let path = config.notesOpenAppPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else { return nil }
            return NSWorkspace.shared.icon(forFile: path)
        case .defaultApp:
            return defaultMarkdownHandlerIcon()
        }
    }

    private func defaultPDFHandlerIcon() -> NSImage? {
        if let appURL = defaultPDFHandlerURL() {
            return NSWorkspace.shared.icon(forFile: appURL.path)
        }

        let placeholder = FileManager.default.temporaryDirectory.appendingPathComponent("papyrus-placeholder.pdf")
        if let appURL = NSWorkspace.shared.urlForApplication(toOpen: placeholder) {
            return NSWorkspace.shared.icon(forFile: appURL.path)
        }
        return nil
    }

    private func defaultPDFHandlerName() -> String? {
        if let appURL = defaultPDFHandlerURL() {
            return appURL.deletingPathExtension().lastPathComponent
        }
        let placeholder = FileManager.default.temporaryDirectory.appendingPathComponent("papyrus-placeholder.pdf")
        if let appURL = NSWorkspace.shared.urlForApplication(toOpen: placeholder) {
            return appURL.deletingPathExtension().lastPathComponent
        }
        return nil
    }

    private func defaultPDFHandlerURL() -> URL? {
        if let bundleId = LSCopyDefaultRoleHandlerForContentType(UTType.pdf.identifier as CFString, .all)?
            .takeRetainedValue() as String? {
            return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)
        }
        return nil
    }

    private func defaultMarkdownHandlerIcon() -> NSImage? {
        if let appURL = defaultMarkdownHandlerURL() {
            return NSWorkspace.shared.icon(forFile: appURL.path)
        }

        let placeholder = FileManager.default.temporaryDirectory.appendingPathComponent("papyrus-placeholder.md")
        if let appURL = NSWorkspace.shared.urlForApplication(toOpen: placeholder) {
            return NSWorkspace.shared.icon(forFile: appURL.path)
        }
        return nil
    }

    private func defaultMarkdownHandlerName() -> String? {
        if let appURL = defaultMarkdownHandlerURL() {
            return appURL.deletingPathExtension().lastPathComponent
        }
        let placeholder = FileManager.default.temporaryDirectory.appendingPathComponent("papyrus-placeholder.md")
        if let appURL = NSWorkspace.shared.urlForApplication(toOpen: placeholder) {
            return appURL.deletingPathExtension().lastPathComponent
        }
        return nil
    }

    private func defaultMarkdownHandlerURL() -> URL? {
        if let markdownUTI = UTType(filenameExtension: "md")?.identifier,
           let bundleId = LSCopyDefaultRoleHandlerForContentType(markdownUTI as CFString, .all)?
            .takeRetainedValue() as String? {
            return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)
        }
        // Fallback when md UTI lookup is unavailable.
        let placeholder = FileManager.default.temporaryDirectory.appendingPathComponent("papyrus-placeholder.md")
        if let appURL = NSWorkspace.shared.urlForApplication(toOpen: placeholder) {
            return appURL
        }
        return nil
    }

    private func choosePDFApp() {
        let panel = NSOpenPanel()
        panel.title = "Choose Application"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            pdfAppPath = url.path
            try? config.setPDFOpenAppPath(url.path)
            try? config.setPDFOpenMode(.customApp)
        }
    }

    private func chooseNotesApp() {
        let panel = NSOpenPanel()
        panel.title = "Choose Notes Editor Application"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            notesAppPath = url.path
            try? config.setNotesOpenAppPath(url.path)
            try? config.setNotesOpenMode(.customApp)
        }
    }

    private func clearShortcut(for action: InputAction) {
        keyboardBindings[action.rawValue] = ""
        if shortcutRecorder.isRecording(action) { shortcutRecorder.cancel() }
    }

    private func restoreDefaultKeyboardBindings() {
        keyboardBindings = keyboardBindingsFromDefaults()
    }

    private func keyboardBinding(for action: InputAction) -> String {
        keyboardBindings[action.rawValue] ?? ""
    }

    private func keyboardValidationMessage(for action: InputAction, value: String) -> String? {
        let normalized = AppShortcutConfig.normalizeBinding(value)
        guard !normalized.isEmpty else { return nil }
        if !AppShortcutConfig.isValidBinding(normalized) {
            return "Use modifier or allowed key"
        }
        if let conflict = conflictingAction(for: action, binding: normalized) {
            return "Used by \(conflict.displayName)"
        }
        return nil
    }

    private func conflictingAction(for action: InputAction, binding: String) -> InputAction? {
        guard !binding.isEmpty else { return nil }
        for candidate in AppConfig.allShortcutActions where candidate != action {
            if keyboardBindings[candidate.rawValue] == binding {
                return candidate
            }
        }
        return nil
    }

    private func keyboardBindingsFromDefaults() -> [String: String] {
        var out: [String: String] = [:]
        for action in AppConfig.allShortcutActions {
            out[action.rawValue] = AppConfig.defaultShortcuts[action.rawValue]?.first ?? ""
        }
        return out
    }

    private func keyboardBindingsFromConfig() -> [String: String] {
        var out = keyboardBindingsFromDefaults()
        for action in AppConfig.allShortcutActions {
            out[action.rawValue] = config.shortcuts[action.rawValue]?.first ?? out[action.rawValue] ?? ""
        }
        return out
    }

    private func applyKeyboardBindings() {
        var updated: [String: [String]] = [:]
        for action in AppConfig.allShortcutActions {
            let value = AppShortcutConfig.normalizeBinding(keyboardBindings[action.rawValue] ?? "")
            if value.isEmpty {
                updated[action.rawValue] = []
                continue
            }
            guard AppShortcutConfig.isValidBinding(value) else { continue }
            guard conflictingAction(for: action, binding: value) == nil else { continue }
            updated[action.rawValue] = [value]
        }
        try? config.setShortcuts(updated)
    }

    // MARK: - Venues helpers

    private func parseVenues(from text: String) throws -> [String: String] {
        var parsed: [String: String] = [:]
        for (index, rawLine) in text.components(separatedBy: .newlines).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let sep = line.firstIndex(of: "=") else {
                throw NSError(domain: "SettingsView", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Line \(index + 1): expected 'Name = Abbreviation'"
                ])
            }
            let key   = String(line[..<sep]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(line[line.index(after: sep)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty && !value.isEmpty else {
                throw NSError(domain: "SettingsView", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "Line \(index + 1): name or abbreviation is empty"
                ])
            }
            parsed[key] = value
        }
        return parsed
    }

    private func venuesTextFromConfig() -> String {
        config.customVenues
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { "\($0.key) = \($0.value)" }
            .joined(separator: "\n")
    }

    // MARK: - Library folder

    private var currentLibraryPath: String {
        if config.libraryPath.isEmpty { return defaultLibraryURL().path }
        return (config.libraryPath as NSString).expandingTildeInPath
    }

    private func defaultLibraryURL() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("Papyrus Library")
    }

    private func chooseLibraryFolder() {
        // Reset any stale state from a previous attempt.
        showMigrationPrompt = false
        pendingLibraryURL = nil

        let panel = NSOpenPanel()
        panel.title = "Choose Paper Storage Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"

        // Use async sheet modal — runModal() can deadlock when SwiftUI is mid-update.
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            let newPath = url.standardizedFileURL.path
            let oldPath = PaperFileManager.shared.libraryURL.standardizedFileURL.path
            guard newPath != oldPath else { return }
            self.pendingLibraryURL = url
            self.showMigrationPrompt = true
        }
    }

    private func migrateLibrary(to newURL: URL, migrate: Bool) {
        let newStoreURL = newURL.appendingPathComponent("Papyrus.sqlite")

        if !migrate {
            do {
                try PersistenceController.shared.switchStore(to: newStoreURL)
                AppConfig.setDbPath(newStoreURL.path)
            } catch {
                pathError = "Database error: \(error.localizedDescription)"
                pendingLibraryURL = nil
                return
            }
            do {
                let isDefault = newURL.path == defaultLibraryURL().path
                try config.setLibraryPath(isDefault ? nil : newURL.path)
                pathError = nil
            } catch {
                pathError = error.localizedDescription
            }
            pendingLibraryURL = nil
            return
        }

        // Migrate path: record old store URL before migration so we can clean it up.
        let oldStoreURL = PersistenceController.desiredStoreURL
        do {
            try PersistenceController.shared.migrateStore(to: newStoreURL)
            AppConfig.setDbPath(newStoreURL.path)
            // Delete old database files (data is now in the new location).
            for suffix in ["", "-wal", "-shm"] {
                let oldFile = URL(fileURLWithPath: oldStoreURL.path + suffix)
                try? FileManager.default.removeItem(at: oldFile)
            }
        } catch {
            pathError = "Database error: \(error.localizedDescription)"
            pendingLibraryURL = nil
            return
        }
        do {
            let isDefault = newURL.path == defaultLibraryURL().path
            try config.setLibraryPath(isDefault ? nil : newURL.path)
            pathError = nil
        } catch {
            pathError = error.localizedDescription
            pendingLibraryURL = nil
            return
        }

        let ctx = PersistenceController.shared.container.viewContext
        let req = NSFetchRequest<Paper>(entityName: "Paper")
        let papers = ((try? ctx.fetch(req)) ?? []).filter { $0.filePath != nil }
        guard !papers.isEmpty else { pendingLibraryURL = nil; return }

        isMigrating = true
        migrationProgress = (0, papers.count)

        Task {
            try? FileManager.default.createDirectory(at: newURL, withIntermediateDirectories: true)
            var done = 0
            for paper in papers {
                guard let oldPath = paper.filePath else { continue }
                let filename = URL(fileURLWithPath: oldPath).lastPathComponent
                let newPath = newURL.appendingPathComponent(filename).path
                if FileManager.default.fileExists(atPath: oldPath) && oldPath != newPath {
                    try? FileManager.default.moveItem(atPath: oldPath, toPath: newPath)
                }
                done += 1
                let finalPath = FileManager.default.fileExists(atPath: newPath) ? newPath : oldPath
                await MainActor.run {
                    paper.filePath = finalPath
                    migrationProgress = (done, papers.count)
                }
            }
            await MainActor.run {
                try? ctx.save()
                isMigrating = false
                migrationProgress = nil
                pendingLibraryURL = nil
            }
        }
    }
}
