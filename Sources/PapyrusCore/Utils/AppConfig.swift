// AppConfig.swift
// UserDefaults-based configuration

import Foundation
import SwiftUI
import Combine

enum PDFOpenMode: String, CaseIterable {
    case defaultApp = "system"
    case customApp  = "custom"

    var label: String {
        switch self {
        case .defaultApp: return "Default App"
        case .customApp:  return "Custom…"
        }
    }
}

enum LibraryViewMode: String, CaseIterable {
    case list
    case gallery

    static func parse(_ raw: String?) -> LibraryViewMode {
        guard let raw else { return .list }
        return LibraryViewMode(rawValue: raw.lowercased()) ?? .list
    }
}

enum GalleryCardSize: String, CaseIterable {
    case small
    case medium
    case large

    static func parse(_ raw: String?) -> GalleryCardSize {
        guard let raw else { return .medium }
        let normalized = raw.lowercased()
        if normalized == "xlarge" || normalized == "xl" {
            return .large
        }
        return GalleryCardSize(rawValue: normalized) ?? .medium
    }

    var minCardWidth: CGFloat {
        switch self {
        case .small: return 190
        case .medium: return 250
        case .large: return 330
        }
    }

    var label: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }
}

enum MetadataPreset: String, CaseIterable {
    case general
    case cs
    case physics
    case biomed

    static func parse(_ raw: String?) -> MetadataPreset {
        guard let raw else { return .general }
        return MetadataPreset(rawValue: raw.lowercased()) ?? .general
    }

    var label: String {
        switch self {
        case .general: return "General"
        case .cs: return "Computer Science"
        case .physics: return "Physics"
        case .biomed: return "Biomed"
        }
    }
}

@MainActor
package class AppConfig: ObservableObject {
    package static let shared = AppConfig()

    @Published var appearance: AppAppearance = .system
    @Published var libraryViewMode: LibraryViewMode = .list
    @Published var galleryCardSize: GalleryCardSize = .medium
    @Published var rankBadgeSources: [String] = []
    @Published var tagNamespaces: [String] = TagNamespaceSupport.fallbackNamespaces
    @Published var showTagsInList: Bool = true
    @Published var listTagCount: Int = 2
    @Published var listTagPreferredNamespaces: [String] = ["proj", "task"]
    @Published var listTagFallbackToOther: Bool = true
    @Published var showFlagInList: Bool = true
    @Published var showVenueInList: Bool = true
    @Published var showRankInList: Bool = true
    @Published var showRatingInList: Bool = true
    @Published var showStatusInList: Bool = true
    @Published var filterPanelOrder: [String] = FilterPanelSectionConfig.defaultOrder.map(\.rawValue)
    @Published var visibleFilterSections: [String] = FilterPanelSectionConfig.defaultOrder.map(\.rawValue)
    @Published package var resolvedColorScheme: ColorScheme = .light
    @Published var libraryPath: String = ""
    @Published var customVenues: [String: String] = [:]
    @Published var metadataPreset: MetadataPreset = .general
    @Published var semanticScholarKey: String = ""
    @Published var easyscholarKey: String = ""
    @Published var shortcuts: [String: [String]] = [:]
    @Published var pdfOpenMode: PDFOpenMode = .defaultApp
    @Published var pdfOpenAppPath: String = ""
    @Published var notesOpenMode: PDFOpenMode = .defaultApp
    @Published var notesOpenAppPath: String = ""

    private let defaults = UserDefaults.standard
    private lazy var defaultsStore = AppConfigDefaultsStore(defaults: defaults)
    private var currentConfig = AppStoredConfig.defaultConfig()
    private let appearanceConfig = AppAppearanceConfig()

    init() {
        load()
    }

    func load() {
        apply(defaultsStore.load())
    }

    func setAppearance(_ appearance: AppAppearance) throws {
        try updateConfig { next in
            next.general.appearance = appearance.rawValue
        }
    }

    func setLibraryViewMode(_ mode: LibraryViewMode) throws {
        try updateConfig { next in
            next.general.libraryViewMode = mode.rawValue
        }
    }

    func setGalleryCardSize(_ size: GalleryCardSize) throws {
        try updateConfig { next in
            next.general.galleryCardSize = size.rawValue
        }
    }

    func setRankBadgeSources(_ sources: [String]) throws {
        try updateConfig { next in
            next.general.rankBadgeSources = RankSourceConfig.normalizedKeys(sources)
        }
    }

    func setTagNamespaces(_ namespaces: [String]) throws {
        try updateConfig { next in
            next.general.tagNamespaces = TagNamespaceSupport.normalizedNamespaces(namespaces)
        }
    }

    func setShowTagsInList(_ enabled: Bool) throws {
        try updateConfig { next in
            next.general.showTagsInList = enabled
        }
    }

    func setListTagCount(_ count: Int) throws {
        try updateConfig { next in
            next.general.listTagCount = count
        }
    }

    func setListTagPreferredNamespaces(_ namespaces: [String]) throws {
        try updateConfig { next in
            next.general.listTagPreferredNamespaces = TagNamespaceSupport.normalizedNamespaces(namespaces)
        }
    }

    func setListTagFallbackToOther(_ enabled: Bool) throws {
        try updateConfig { next in
            next.general.listTagFallbackToOther = enabled
        }
    }

    func setShowFlagInList(_ enabled: Bool) throws {
        try updateConfig { next in
            next.general.showFlagInList = enabled
        }
    }

    func setShowVenueInList(_ enabled: Bool) throws {
        try updateConfig { next in
            next.general.showVenueInList = enabled
        }
    }

    func setShowRankInList(_ enabled: Bool) throws {
        try updateConfig { next in
            next.general.showRankInList = enabled
        }
    }

    func setShowRatingInList(_ enabled: Bool) throws {
        try updateConfig { next in
            next.general.showRatingInList = enabled
        }
    }

    func setShowStatusInList(_ enabled: Bool) throws {
        try updateConfig { next in
            next.general.showStatusInList = enabled
        }
    }

    func setFilterPanelOrder(_ order: [String]) throws {
        try updateConfig { next in
            next.general.filterPanelOrder = FilterPanelSectionConfig.normalizedOrder(order)
        }
    }

    func setVisibleFilterSections(_ sections: [String]) throws {
        try updateConfig { next in
            next.general.visibleFilterSections = FilterPanelSectionConfig.normalizedVisible(sections)
        }
    }

    func setLibraryPath(_ path: String?) throws {
        try updateConfig { next in
            next.general.libraryPath = path?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
    }

    /// Updates the stored Core Data location (only called when actually migrating the store).
    static func setDbPath(_ path: String) {
        UserDefaults.standard.set(path, forKey: AppConfigDefaultsKey.dbPath)
    }


    func setSemanticScholarKey(_ key: String) throws {
        try updateConfig { next in
            next.api.semanticScholarKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func setMetadataPreset(_ preset: MetadataPreset) throws {
        try updateConfig { next in
            next.api.metadataPreset = preset.rawValue
        }
    }

    func setEasyScholarKey(_ key: String) throws {
        try updateConfig { next in
            next.api.easyscholarKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func setCustomVenues(_ venues: [String: String]) throws {
        try updateConfig { next in
            next.venues = venues
        }
    }

    func setPDFOpenMode(_ mode: PDFOpenMode) throws {
        try updateConfig { next in next.general.pdfOpenMode = mode.rawValue }
    }

    func setPDFOpenAppPath(_ path: String) throws {
        try updateConfig { next in next.general.pdfOpenAppPath = path.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    func setNotesOpenMode(_ mode: PDFOpenMode) throws {
        try updateConfig { next in next.general.notesOpenMode = mode.rawValue }
    }

    func setNotesOpenAppPath(_ path: String) throws {
        try updateConfig { next in next.general.notesOpenAppPath = path.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    func setShortcuts(_ shortcuts: [String: [String]]) throws {
        try updateConfig { next in
            next.shortcuts = AppShortcutConfig.normalizedBindings(shortcuts)
        }
    }

    func setShortcut(_ binding: String?, for action: InputAction) throws {
        try updateConfig { next in
            var updated = next.shortcuts
            let value = AppShortcutConfig.normalizeBinding(binding ?? "")
            updated[action.rawValue] = value.isEmpty ? [] : [value]
            next.shortcuts = AppShortcutConfig.normalizedBindings(updated)
        }
    }

    func resetShortcutsToDefault() throws {
        try updateConfig { next in
            next.shortcuts = Self.defaultShortcuts
        }
    }

    func applyAllSettings(
        appearance: AppAppearance,
        semanticScholarKey: String,
        easyScholarKey: String,
        venues: [String: String],
        shortcuts: [String: [String]]
    ) throws {
        try updateConfig { next in
            next.general.appearance = appearance.rawValue
            next.api.semanticScholarKey = semanticScholarKey.trimmingCharacters(in: .whitespacesAndNewlines)
            next.api.easyscholarKey = easyScholarKey.trimmingCharacters(in: .whitespacesAndNewlines)
            next.venues = venues
            next.shortcuts = shortcuts
        }
    }

    private func updateConfig(_ mutate: (inout AppStoredConfig) -> Void) throws {
        var next = currentConfig
        mutate(&next)
        let normalizedConfig = AppConfigNormalizer.normalized(next)
        guard normalizedConfig != currentConfig else { return }
        defaultsStore.save(normalizedConfig)
        apply(normalizedConfig)
    }

    private func apply(_ config: AppStoredConfig) {
        currentConfig = config
        appearance = AppAppearance.parse(config.general.appearance)
        libraryViewMode = LibraryViewMode.parse(config.general.libraryViewMode)
        galleryCardSize = GalleryCardSize.parse(config.general.galleryCardSize)
        rankBadgeSources = RankSourceConfig.normalizedKeys(config.general.rankBadgeSources)
        tagNamespaces = TagNamespaceSupport.normalizedNamespaces(config.general.tagNamespaces)
        showTagsInList = config.general.showTagsInList
        listTagCount = config.general.listTagCount
        listTagPreferredNamespaces = TagNamespaceSupport.normalizedNamespaces(config.general.listTagPreferredNamespaces)
        listTagFallbackToOther = config.general.listTagFallbackToOther
        showFlagInList = config.general.showFlagInList
        showVenueInList = config.general.showVenueInList
        showRankInList = config.general.showRankInList
        showRatingInList = config.general.showRatingInList
        showStatusInList = config.general.showStatusInList
        filterPanelOrder = FilterPanelSectionConfig.normalizedOrder(config.general.filterPanelOrder)
        visibleFilterSections = FilterPanelSectionConfig.normalizedVisible(config.general.visibleFilterSections)
        applyAppAppearance(appearance)
        libraryPath = config.general.libraryPath
        customVenues = config.venues
        semanticScholarKey = config.api.semanticScholarKey
        metadataPreset = MetadataPreset.parse(config.api.metadataPreset)
        easyscholarKey = config.api.easyscholarKey
        shortcuts = config.shortcuts
        pdfOpenMode = PDFOpenMode(rawValue: config.general.pdfOpenMode) ?? .defaultApp
        pdfOpenAppPath = config.general.pdfOpenAppPath
        notesOpenMode = PDFOpenMode(rawValue: config.general.notesOpenMode) ?? .defaultApp
        notesOpenAppPath = config.general.notesOpenAppPath

        FileStorageConfig.libraryPath = libraryPath
        VenueFormatterConfig.customVenues = customVenues
        TagNamespaceConfig.configuredNamespaces = tagNamespaces
    }

    private func applyAppAppearance(_ appearance: AppAppearance) {
        appearanceConfig.apply(appearance: appearance, resolvedColorScheme: &resolvedColorScheme)
        if appearance == .system {
            appearanceConfig.startSystemAppearanceObservation { [weak self] in
                guard let self else { return }
                self.resolvedColorScheme = self.appearanceConfig.currentSystemColorScheme()
            }
        } else {
            appearanceConfig.stopSystemAppearanceObservation()
        }
    }

    // MARK: - Shortcut Helpers

    /// Returns a SwiftUI KeyboardShortcut for the given action.
    /// Prefers cmd-based keys; also accepts special keys (return, delete, space…) with no modifiers.
    package func keyboardShortcut(for action: InputAction) -> KeyboardShortcut? {
        AppShortcutConfig.keyboardShortcut(action: action, shortcuts: shortcuts)
    }

    // Shared default shortcuts for the limited keyboard customization panel.
    static let defaultShortcuts: [String: [String]] = AppShortcutConfig.defaultShortcuts
    static let allShortcutActions: [InputAction] = AppShortcutConfig.allActions

    static func parseShortcut(_ str: String) -> KeyboardShortcut? {
        AppShortcutConfig.parseShortcut(str)
    }

    func keyboardShortcut(for action: String) -> KeyboardShortcut? {
        guard let action = InputAction(rawValue: action) else { return nil }
        return keyboardShortcut(for: action)
    }

}

// Thread-safe mirror for non-MainActor access
enum VenueFormatterConfig {
    static var customVenues: [String: String] = [:]
}

enum TagNamespaceConfig {
    static var configuredNamespaces: [String] = TagNamespaceSupport.fallbackNamespaces
}
