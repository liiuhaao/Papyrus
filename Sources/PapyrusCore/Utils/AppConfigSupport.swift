import Foundation

enum FilterPanelSection: String, CaseIterable, Identifiable {
    case flagged
    case status
    case year
    case tags
    case ranks
    case venue
    case publicationType = "publication_type"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .flagged: return "Flagged"
        case .status: return "Status"
        case .year: return "Year"
        case .tags: return "Tags"
        case .ranks: return "Ranks"
        case .venue: return "Venue"
        case .publicationType: return "Publication Type"
        }
    }
}

enum FilterPanelSectionConfig {
    static let defaultOrder = FilterPanelSection.allCases

    static func normalizedOrder(_ rawValues: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []

        for raw in rawValues {
            guard let section = FilterPanelSection(rawValue: raw), !seen.contains(section.rawValue) else { continue }
            seen.insert(section.rawValue)
            ordered.append(section.rawValue)
        }

        for section in defaultOrder where !seen.contains(section.rawValue) {
            ordered.append(section.rawValue)
        }

        return ordered
    }

    static func normalizedVisible(_ rawValues: [String]) -> [String] {
        let allowed = Set(FilterPanelSection.allCases.map(\.rawValue))
        var seen = Set<String>()
        var ordered: [String] = []

        for raw in rawValues where allowed.contains(raw) && !seen.contains(raw) {
            seen.insert(raw)
            ordered.append(raw)
        }
        return ordered
    }
}

enum AppConfigDefaultsKey {
    static let appearance = "settings.general.appearance"
    static let libraryPath = "settings.general.library_path"
    static let dbPath = "settings.general.db_path"
    static let libraryViewMode = "settings.general.library_view_mode"
    static let galleryCardSize = "settings.general.gallery_card_size"
    static let rankBadgeSources = "settings.general.rank_badge_sources"
    static let tagNamespaces = "settings.general.tag_namespaces"
    static let showTagsInList = "settings.general.show_tags_in_list"
    static let listTagCount = "settings.general.list_tag_count"
    static let listTagPreferredNamespaces = "settings.general.list_tag_preferred_namespaces"
    static let listTagFallbackToOther = "settings.general.list_tag_fallback_to_other"
    static let showFlagInList = "settings.general.show_flag_in_list"
    static let showVenueInList = "settings.general.show_venue_in_list"
    static let showRankInList = "settings.general.show_rank_in_list"
    static let showRatingInList = "settings.general.show_rating_in_list"
    static let showStatusInList = "settings.general.show_status_in_list"
    static let filterPanelOrder = "settings.general.filter_panel_order"
    static let visibleFilterSections = "settings.general.visible_filter_sections"
    static let customVenues = "settings.venues"
    static let metadataPreset = "settings.api.metadata_preset"
    static let semanticScholarKey = "settings.api.semantic_scholar_key"
    static let easyscholarKey = "settings.api.easyscholar_key"
    static let shortcuts = "settings.shortcuts"
    static let pdfOpenMode = "settings.general.pdf_open_mode"
    static let pdfOpenAppPath = "settings.general.pdf_open_app_path"
    static let notesOpenMode = "settings.general.notes_open_mode"
    static let notesOpenAppPath = "settings.general.notes_open_app_path"
}

struct AppStoredConfig: Equatable {
    struct General: Equatable {
        var appearance: String
        var libraryViewMode: String = LibraryViewMode.list.rawValue
        var galleryCardSize: String = GalleryCardSize.medium.rawValue
        var rankBadgeSources: [String] = []
        var tagNamespaces: [String] = TagNamespaceSupport.fallbackNamespaces
        var showTagsInList: Bool = true
        var listTagCount: Int = 2
        var listTagPreferredNamespaces: [String] = ["proj", "task"]
        var listTagFallbackToOther: Bool = true
        var showFlagInList: Bool = true
        var showVenueInList: Bool = true
        var showRankInList: Bool = true
        var showRatingInList: Bool = true
        var showStatusInList: Bool = true
        var filterPanelOrder: [String] = FilterPanelSectionConfig.defaultOrder.map(\.rawValue)
        var visibleFilterSections: [String] = FilterPanelSectionConfig.defaultOrder.map(\.rawValue)
        var libraryPath: String
        var pdfOpenMode: String = "system"
        var pdfOpenAppPath: String = ""
        var notesOpenMode: String = "system"
        var notesOpenAppPath: String = ""
    }

    struct API: Equatable {
        var metadataPreset: String
        var semanticScholarKey: String
        var easyscholarKey: String
    }

    var general: General
    var venues: [String: String]
    var api: API
    var shortcuts: [String: [String]]

    static func defaultConfig() -> AppStoredConfig {
        AppStoredConfig(
            general: .init(appearance: AppAppearance.system.rawValue, libraryPath: ""),
            venues: [:],
            api: .init(
                metadataPreset: MetadataPreset.general.rawValue,
                semanticScholarKey: "",
                easyscholarKey: ""
            ),
            shortcuts: AppShortcutConfig.defaultShortcuts
        )
    }
}

enum AppConfigNormalizer {
    static func normalized(_ config: AppStoredConfig) -> AppStoredConfig {
        var output = config
        output.general.appearance = AppAppearance.parse(output.general.appearance).rawValue
        output.general.libraryViewMode = LibraryViewMode.parse(output.general.libraryViewMode).rawValue
        output.general.galleryCardSize = GalleryCardSize.parse(output.general.galleryCardSize).rawValue
        output.general.rankBadgeSources = RankSourceConfig.normalizedKeys(output.general.rankBadgeSources)
        output.general.tagNamespaces = TagNamespaceSupport.normalizedNamespaces(output.general.tagNamespaces)
        output.general.listTagCount = min(max(output.general.listTagCount, 0), 5)
        output.general.listTagPreferredNamespaces = TagNamespaceSupport.normalizedNamespaces(output.general.listTagPreferredNamespaces)
        output.general.showFlagInList = output.general.showFlagInList
        output.general.showVenueInList = output.general.showVenueInList
        output.general.showRankInList = output.general.showRankInList
        output.general.showRatingInList = output.general.showRatingInList
        output.general.showStatusInList = output.general.showStatusInList
        output.general.filterPanelOrder = FilterPanelSectionConfig.normalizedOrder(output.general.filterPanelOrder)
        let normalizedVisible = FilterPanelSectionConfig.normalizedVisible(output.general.visibleFilterSections)
        output.general.visibleFilterSections = normalizedVisible.isEmpty
            ? FilterPanelSectionConfig.defaultOrder.map(\.rawValue)
            : normalizedVisible
        output.general.libraryPath = output.general.libraryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        output.general.pdfOpenMode = (PDFOpenMode(rawValue: output.general.pdfOpenMode) ?? .defaultApp).rawValue
        output.general.pdfOpenAppPath = output.general.pdfOpenAppPath.trimmingCharacters(in: .whitespacesAndNewlines)
        output.general.notesOpenMode = (PDFOpenMode(rawValue: output.general.notesOpenMode) ?? .defaultApp).rawValue
        output.general.notesOpenAppPath = output.general.notesOpenAppPath.trimmingCharacters(in: .whitespacesAndNewlines)

        output.api.metadataPreset = MetadataPreset.parse(output.api.metadataPreset).rawValue
        output.api.semanticScholarKey = output.api.semanticScholarKey.trimmingCharacters(in: .whitespacesAndNewlines)
        output.api.easyscholarKey = output.api.easyscholarKey.trimmingCharacters(in: .whitespacesAndNewlines)

        output.venues = output.venues.reduce(into: [:]) { partial, pair in
            let key = pair.key.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = pair.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty else { return }
            partial[key] = value
        }

        output.shortcuts = AppShortcutConfig.normalizedBindings(output.shortcuts)

        return output
    }
}

struct AppConfigDefaultsStore {
    let defaults: UserDefaults

    func load() -> AppStoredConfig {
        var config = AppStoredConfig.defaultConfig()

        if let raw = defaults.string(forKey: AppConfigDefaultsKey.appearance) {
            config.general.appearance = raw
        }
        if let raw = defaults.string(forKey: AppConfigDefaultsKey.libraryViewMode) {
            config.general.libraryViewMode = raw
        }
        if let raw = defaults.string(forKey: AppConfigDefaultsKey.galleryCardSize) {
            config.general.galleryCardSize = raw
        }
        if let raw = defaults.array(forKey: AppConfigDefaultsKey.rankBadgeSources) as? [String] {
            config.general.rankBadgeSources = raw
        }
        if let raw = defaults.array(forKey: AppConfigDefaultsKey.tagNamespaces) as? [String] {
            config.general.tagNamespaces = raw
        }
        if defaults.object(forKey: AppConfigDefaultsKey.showTagsInList) != nil {
            config.general.showTagsInList = defaults.bool(forKey: AppConfigDefaultsKey.showTagsInList)
        }
        if defaults.object(forKey: AppConfigDefaultsKey.listTagCount) != nil {
            config.general.listTagCount = defaults.integer(forKey: AppConfigDefaultsKey.listTagCount)
        }
        if let raw = defaults.array(forKey: AppConfigDefaultsKey.listTagPreferredNamespaces) as? [String] {
            config.general.listTagPreferredNamespaces = raw
        }
        if defaults.object(forKey: AppConfigDefaultsKey.listTagFallbackToOther) != nil {
            config.general.listTagFallbackToOther = defaults.bool(forKey: AppConfigDefaultsKey.listTagFallbackToOther)
        }
        if defaults.object(forKey: AppConfigDefaultsKey.showFlagInList) != nil {
            config.general.showFlagInList = defaults.bool(forKey: AppConfigDefaultsKey.showFlagInList)
        }
        if defaults.object(forKey: AppConfigDefaultsKey.showVenueInList) != nil {
            config.general.showVenueInList = defaults.bool(forKey: AppConfigDefaultsKey.showVenueInList)
        }
        if defaults.object(forKey: AppConfigDefaultsKey.showRankInList) != nil {
            config.general.showRankInList = defaults.bool(forKey: AppConfigDefaultsKey.showRankInList)
        }
        if defaults.object(forKey: AppConfigDefaultsKey.showRatingInList) != nil {
            config.general.showRatingInList = defaults.bool(forKey: AppConfigDefaultsKey.showRatingInList)
        }
        if defaults.object(forKey: AppConfigDefaultsKey.showStatusInList) != nil {
            config.general.showStatusInList = defaults.bool(forKey: AppConfigDefaultsKey.showStatusInList)
        }
        if let raw = defaults.array(forKey: AppConfigDefaultsKey.filterPanelOrder) as? [String] {
            config.general.filterPanelOrder = raw
        }
        if let raw = defaults.array(forKey: AppConfigDefaultsKey.visibleFilterSections) as? [String] {
            config.general.visibleFilterSections = raw
        }
        config.general.libraryPath = defaults.string(forKey: AppConfigDefaultsKey.libraryPath) ?? ""

        if let venues = defaults.dictionary(forKey: AppConfigDefaultsKey.customVenues) as? [String: String] {
            config.venues = venues
        }

        config.api.metadataPreset = defaults.string(forKey: AppConfigDefaultsKey.metadataPreset) ?? MetadataPreset.general.rawValue
        config.api.semanticScholarKey = defaults.string(forKey: AppConfigDefaultsKey.semanticScholarKey) ?? ""
        config.api.easyscholarKey = defaults.string(forKey: AppConfigDefaultsKey.easyscholarKey) ?? ""
        config.general.pdfOpenMode = defaults.string(forKey: AppConfigDefaultsKey.pdfOpenMode) ?? "system"
        config.general.pdfOpenAppPath = defaults.string(forKey: AppConfigDefaultsKey.pdfOpenAppPath) ?? ""
        config.general.notesOpenMode = defaults.string(forKey: AppConfigDefaultsKey.notesOpenMode) ?? "system"
        config.general.notesOpenAppPath = defaults.string(forKey: AppConfigDefaultsKey.notesOpenAppPath) ?? ""

        if let shortcuts = defaults.dictionary(forKey: AppConfigDefaultsKey.shortcuts) as? [String: [String]] {
            config.shortcuts = shortcuts
        }

        return AppConfigNormalizer.normalized(config)
    }

    func save(_ config: AppStoredConfig) {
        defaults.set(config.general.appearance, forKey: AppConfigDefaultsKey.appearance)
        defaults.set(config.general.libraryViewMode, forKey: AppConfigDefaultsKey.libraryViewMode)
        defaults.set(config.general.galleryCardSize, forKey: AppConfigDefaultsKey.galleryCardSize)
        defaults.set(config.general.rankBadgeSources, forKey: AppConfigDefaultsKey.rankBadgeSources)
        defaults.set(config.general.tagNamespaces, forKey: AppConfigDefaultsKey.tagNamespaces)
        defaults.set(config.general.showTagsInList, forKey: AppConfigDefaultsKey.showTagsInList)
        defaults.set(config.general.listTagCount, forKey: AppConfigDefaultsKey.listTagCount)
        defaults.set(config.general.listTagPreferredNamespaces, forKey: AppConfigDefaultsKey.listTagPreferredNamespaces)
        defaults.set(config.general.listTagFallbackToOther, forKey: AppConfigDefaultsKey.listTagFallbackToOther)
        defaults.set(config.general.showFlagInList, forKey: AppConfigDefaultsKey.showFlagInList)
        defaults.set(config.general.showVenueInList, forKey: AppConfigDefaultsKey.showVenueInList)
        defaults.set(config.general.showRankInList, forKey: AppConfigDefaultsKey.showRankInList)
        defaults.set(config.general.showRatingInList, forKey: AppConfigDefaultsKey.showRatingInList)
        defaults.set(config.general.showStatusInList, forKey: AppConfigDefaultsKey.showStatusInList)
        defaults.set(config.general.filterPanelOrder, forKey: AppConfigDefaultsKey.filterPanelOrder)
        defaults.set(config.general.visibleFilterSections, forKey: AppConfigDefaultsKey.visibleFilterSections)
        defaults.set(config.general.libraryPath, forKey: AppConfigDefaultsKey.libraryPath)
        defaults.set(config.venues, forKey: AppConfigDefaultsKey.customVenues)
        defaults.set(config.api.metadataPreset, forKey: AppConfigDefaultsKey.metadataPreset)
        defaults.set(config.api.semanticScholarKey, forKey: AppConfigDefaultsKey.semanticScholarKey)
        defaults.set(config.api.easyscholarKey, forKey: AppConfigDefaultsKey.easyscholarKey)
        defaults.set(config.shortcuts, forKey: AppConfigDefaultsKey.shortcuts)
        defaults.set(config.general.pdfOpenMode, forKey: AppConfigDefaultsKey.pdfOpenMode)
        defaults.set(config.general.pdfOpenAppPath, forKey: AppConfigDefaultsKey.pdfOpenAppPath)
        defaults.set(config.general.notesOpenMode, forKey: AppConfigDefaultsKey.notesOpenMode)
        defaults.set(config.general.notesOpenAppPath, forKey: AppConfigDefaultsKey.notesOpenAppPath)
    }
}
