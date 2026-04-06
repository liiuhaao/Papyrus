import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
import SafariServices

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case library
    case metadata
    case feed
    case extensions
    case keyboard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:    return "General"
        case .library:    return "Library"
        case .metadata:   return "Sources"
        case .feed:       return "Feed"
        case .extensions: return "Extensions"
        case .keyboard:   return "Keyboard"
        }
    }

    var icon: String {
        switch self {
        case .general:    return "gearshape"
        case .library:    return "books.vertical"
        case .metadata:   return "externaldrive.badge.wifi"
        case .feed:       return "dot.radiowaves.up.forward"
        case .extensions: return "puzzlepiece.extension"
        case .keyboard:   return "keyboard"
        }
    }
}

enum SettingsAPIField: Hashable {
    case semantic
    case easy
}

struct SettingsTopTabBar: View {
    @Binding var selectedTab: SettingsTab

    var body: some View {
        HStack(spacing: 2) {
            ForEach(SettingsTab.allCases) { tab in
                topTabButton(tab)
            }
        }
        .padding(.horizontal, AppMetrics.tabBarHorizontal)
        .padding(.top, AppMetrics.tabBarTop)
        .padding(.bottom, AppMetrics.tabBarBottom)
        .frame(maxWidth: .infinity)
    }

    private func topTabButton(_ tab: SettingsTab) -> some View {
        let selected = selectedTab == tab
        return Button { selectedTab = tab } label: {
            VStack(spacing: 5) {
                Image(systemName: tab.icon)
                    .font(.system(size: 19 * AppStyleConfig.fontScale, weight: .light))
                Text(tab.title)
                    .font(AppTypography.labelStrong)
            }
            .foregroundStyle(selected ? Color.accentColor : .secondary)
            .frame(width: AppMetrics.tabButtonWidth, height: AppMetrics.tabButtonHeight)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: AppMetrics.controlCornerRadius)
                    .fill(selected ? Color.accentColor.opacity(0.10) : .clear)
            )
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: max(10, AppMetrics.inlineRowVertical * 2.2)) {
            Text(title)
                .font(AppTypography.labelStrong)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(0.5)
            content
        }
    }
}

struct SettingsMigrationOverlay: View {
    let progress: (done: Int, total: Int)?

    var body: some View {
        if let progress {
            ZStack {
                Color.black.opacity(0.3).ignoresSafeArea()
            VStack(spacing: 14) {
                    ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                        .progressViewStyle(.linear)
                        .frame(width: 220)
                    Text("Moving \(progress.done) / \(progress.total) files…")
                        .font(AppTypography.label)
                        .foregroundStyle(.secondary)
                }
                .padding(28)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppMetrics.cardCornerRadius + 4))
            }
        }
    }
}

private struct SettingsPanelCard<Content: View>: View {
    let title: String
    let caption: String
    let trailingAccessory: AnyView?
    @ViewBuilder let content: Content

    init(_ title: String, caption: String, trailingAccessory: AnyView? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.caption = caption
        self.trailingAccessory = trailingAccessory
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Text(title)
                    .font(AppTypography.bodySmallMedium)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                if let trailingAccessory {
                    trailingAccessory
                }
            }
            Text(caption)
                .font(AppTypography.label)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            content
        }
        .padding(AppMetrics.cardPadding)
        .appCardSurface(
            fill: Color.primary.opacity(0.025),
            stroke: Color.primary.opacity(0.05)
        )
    }
}

private struct SettingsInsetGroup<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(0)
        .background(Color.primary.opacity(0.018), in: RoundedRectangle(cornerRadius: AppMetrics.controlCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppMetrics.controlCornerRadius)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }
}

private struct SettingsCheckboxRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title)
                .font(AppTypography.bodySmall)
                .foregroundStyle(.primary)
        }
        .toggleStyle(.checkbox)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: AppMetrics.controlCornerRadius - 2))
    }
}

private struct SettingsPillTextField: View {
    let placeholder: String
    @Binding var text: String
    let onSubmit: () -> Void
    let isFocused: FocusState<Bool>.Binding

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(AppTypography.bodySmall)
            .focused(isFocused)
            .onSubmit(onSubmit)
            .padding(.horizontal, AppMetrics.pillHorizontal + 4)
            .padding(.vertical, AppMetrics.pillVertical + 5)
            .appInsetInputSurface(
                fill: Color.primary.opacity(0.05),
                stroke: Color.primary.opacity(0.06),
                cornerRadius: AppMetrics.controlCornerRadius
            )
    }
}

private struct SettingsMonoTextField: View {
    let placeholder: String
    @Binding var text: String
    let onSubmit: () -> Void
    let focus: SettingsAPIField
    let isFocused: FocusState<SettingsAPIField?>.Binding

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(AppTypography.mono)
            .focused(isFocused, equals: focus)
            .onSubmit(onSubmit)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .appInsetInputSurface(
                fill: Color.primary.opacity(0.05),
                stroke: Color.primary.opacity(0.06),
                cornerRadius: AppMetrics.controlCornerRadius
            )
    }
}

private struct SettingsSecondaryButton: ViewModifier {
    func body(content: Content) -> some View {
        content
            .buttonStyle(.plain)
            .font(AppTypography.label)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: AppMetrics.controlCornerRadius - 2))
            .overlay(
                RoundedRectangle(cornerRadius: AppMetrics.controlCornerRadius - 2)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
            )
    }
}

private struct SettingsIconButton: ViewModifier {
    func body(content: Content) -> some View {
        content
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .frame(width: 28, height: 28)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: AppMetrics.controlCornerRadius - 4))
    }
}

private extension View {
    func settingsSecondaryButtonStyle() -> some View {
        modifier(SettingsSecondaryButton())
    }

    func settingsIconButtonStyle() -> some View {
        modifier(SettingsIconButton())
    }
}

struct GeneralSettingsPanel: View {
    @ObservedObject var config: AppConfig
    let pdfOpenModeDisplay: String
    let pdfOpenModeIcon: NSImage?
    let notesOpenModeDisplay: String
    let notesOpenModeIcon: NSImage?
    let onChoosePDFApp: () -> Void
    let onChooseNotesApp: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppMetrics.sectionSpacing) {
            SettingsSection("Overview") {
                SettingsPanelCard("Library Snapshot", caption: "A quick read on the size and shape of your current library.") {
                    LibraryStatsView()
                }
            }

            SettingsSection("Appearance") {
                VStack(alignment: .leading, spacing: 10) {
                    SettingsPanelCard("Theme", caption: "Choose how Papyrus matches the system appearance.") {
                        HStack(spacing: 12) {
                            settingChoiceCard(title: "System", symbol: "circle.lefthalf.filled", selected: config.appearance == .system) {
                                try? config.setAppearance(.system)
                            }
                            settingChoiceCard(title: "Light", symbol: "sun.max", selected: config.appearance == .light) {
                                try? config.setAppearance(.light)
                            }
                            settingChoiceCard(title: "Dark", symbol: "moon", selected: config.appearance == .dark) {
                                try? config.setAppearance(.dark)
                            }
                        }
                    }
                }
            }

            SettingsSection("Behavior") {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsPanelCard("PDF Opening", caption: "Choose how PDFs are opened from the library.") {
                        AppInlineValueRow(
                            symbol: "doc.fill",
                            value: pdfOpenModeDisplay,
                            isMonospaced: false,
                            leadingImage: pdfOpenModeIcon
                        )

                        HStack(spacing: 8) {
                            Button("Default App") { try? config.setPDFOpenMode(.defaultApp) }
                                .settingsSecondaryButtonStyle()
                            Button("Choose App…", action: onChoosePDFApp)
                                .settingsSecondaryButtonStyle()
                        }
                    }

                    SettingsPanelCard("Notes Opening", caption: "Choose how Markdown notes are opened from the notes panel.") {
                        AppInlineValueRow(
                            symbol: "note.text",
                            value: notesOpenModeDisplay,
                            isMonospaced: false,
                            leadingImage: notesOpenModeIcon
                        )

                        HStack(spacing: 8) {
                            Button("Default App") { try? config.setNotesOpenMode(.defaultApp) }
                                .settingsSecondaryButtonStyle()
                            Button("Choose App…", action: onChooseNotesApp)
                                .settingsSecondaryButtonStyle()
                        }
                    }
                }
            }
        }
    }

    private func settingChoiceCard(
        title: String,
        symbol: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 16 * AppStyleConfig.fontScale, weight: .medium))
                    .foregroundStyle(selected ? Color.accentColor : .secondary)

                Text(title)
                    .font(selected ? AppTypography.bodySmallMedium : AppTypography.bodySmall)
                    .foregroundStyle(selected ? .primary : .secondary)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .appCardSurface(
                fill: selected ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.025),
                stroke: selected ? Color.accentColor.opacity(0.28) : Color.primary.opacity(0.05)
            )
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
    }
}

struct LibrarySettingsPanel: View {
    @ObservedObject var config: AppConfig
    let currentLibraryPath: String
    let pathError: String?
    let onChooseLibraryFolder: () -> Void
    let onResetLibraryPath: () -> Void
    @Binding var tagNamespaceText: String
    @Binding var listTagNamespaceText: String
    let tagNamespacesFocused: FocusState<Bool>.Binding
    let listTagNamespacesFocused: FocusState<Bool>.Binding
    let onApplyTagNamespaces: () -> Void
    let onApplyListTagNamespaces: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppMetrics.sectionSpacing) {
            SettingsSection("Files") {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsPanelCard("Storage", caption: "Choose where Papyrus stores its database and PDFs.") {
                        AppInlineValueRow(
                            symbol: "folder.fill",
                            value: currentLibraryPath,
                            trailingAction: {
                                Button {
                                    NSWorkspace.shared.open(PaperFileManager.shared.libraryURL)
                                } label: {
                                    Image(systemName: "arrow.up.right.square")
                                        .foregroundStyle(.tertiary)
                                }
                                .buttonStyle(.plain)
                                .help("Open in Finder")
                            }
                        )

                        HStack(alignment: .center, spacing: 8) {
                            Button("Default Folder", action: onResetLibraryPath)
                                .settingsSecondaryButtonStyle()
                            Button("Choose Folder…", action: onChooseLibraryFolder)
                                .settingsSecondaryButtonStyle()
                            Spacer(minLength: 0)
                        }

                        if let pathError {
                            Text(pathError)
                                .font(AppTypography.label)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }

            SettingsSection("Tags") {
                VStack(alignment: .leading, spacing: 10) {
                    SettingsPanelCard("Tag Namespaces", caption: "Configure the namespace prefixes suggested in tag editors.") {
                        SettingsPillTextField(
                            placeholder: "e.g. proj, topic, method, task",
                            text: $tagNamespaceText,
                            onSubmit: onApplyTagNamespaces,
                            isFocused: tagNamespacesFocused
                        )

                        let namespaces = TagNamespaceSupport.parseText(tagNamespaceText)
                        if !namespaces.isEmpty {
                            FlowLayout(spacing: 8) {
                                ForEach(namespaces, id: \.self) { namespace in
                                    Text("\(namespace):")
                                        .appBadgePill(AppColors.namespaceColor(namespace), horizontal: 9, vertical: 4)
                                }
                            }
                        }
                    }

                    SettingsPanelCard("List Tags", caption: "Choose whether tags appear in list rows and how they are selected.") {
                        VStack(alignment: .leading, spacing: 10) {
                            SettingsCheckboxRow(title: "Show tags in list rows", isOn: Binding(
                                get: { config.showTagsInList },
                                set: { try? config.setShowTagsInList($0) }
                            ))

                            HStack(spacing: 10) {
                                Text("Count")
                                    .font(AppTypography.label)
                                    .foregroundStyle(.secondary)
                                Picker("", selection: Binding(
                                    get: { config.listTagCount },
                                    set: { try? config.setListTagCount($0) }
                                )) {
                                    Text("0").tag(0)
                                    Text("1").tag(1)
                                    Text("2").tag(2)
                                    Text("3").tag(3)
                                    Text("4").tag(4)
                                    Text("5").tag(5)
                                }
                                .labelsHidden()
                                .pickerStyle(.segmented)
                                .frame(maxWidth: 260)
                                .controlSize(.small)
                            }

                            SettingsCheckboxRow(title: "Fallback to regular tags", isOn: Binding(
                                get: { config.listTagFallbackToOther },
                                set: { try? config.setListTagFallbackToOther($0) }
                            ))

                            SettingsPillTextField(
                                placeholder: "Preferred namespaces, e.g. proj, task, topic",
                                text: $listTagNamespaceText,
                                onSubmit: onApplyListTagNamespaces,
                                isFocused: listTagNamespacesFocused
                            )

                            let namespaces = TagNamespaceSupport.parseText(listTagNamespaceText)
                            if !namespaces.isEmpty {
                                FlowLayout(spacing: 8) {
                                    ForEach(namespaces, id: \.self) { namespace in
                                        Text("\(namespace):")
                                            .appBadgePill(AppColors.namespaceColor(namespace), horizontal: 9, vertical: 4)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            SettingsSection("Display") {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsPanelCard("Visible Elements", caption: "Control which metadata blocks appear directly in each paper row.") {
                        VStack(alignment: .leading, spacing: 10) {
                            SettingsCheckboxRow(title: "Show flag", isOn: Binding(
                                get: { config.showFlagInList },
                                set: { try? config.setShowFlagInList($0) }
                            ))
                            SettingsCheckboxRow(title: "Show venue and year", isOn: Binding(
                                get: { config.showVenueInList },
                                set: { try? config.setShowVenueInList($0) }
                            ))
                            SettingsCheckboxRow(title: "Show rank badges", isOn: Binding(
                                get: { config.showRankInList },
                                set: { try? config.setShowRankInList($0) }
                            ))
                            SettingsCheckboxRow(title: "Show rating", isOn: Binding(
                                get: { config.showRatingInList },
                                set: { try? config.setShowRatingInList($0) }
                            ))
                            SettingsCheckboxRow(title: "Show reading status", isOn: Binding(
                                get: { config.showStatusInList },
                                set: { try? config.setShowStatusInList($0) }
                            ))
                        }
                    }

                    SettingsPanelCard("Filter Sections", caption: "Choose which filters appear in the sidebar and set their order.") {
                        SettingsInsetGroup {
                            ForEach(Array(config.filterPanelOrder.enumerated()), id: \.element) { index, raw in
                                if let section = FilterPanelSection(rawValue: raw) {
                                    HStack(spacing: 10) {
                                        Toggle(
                                            isOn: Binding(
                                                get: { config.visibleFilterSections.contains(section.rawValue) },
                                                set: { enabled in toggleFilterSection(section, enabled: enabled) }
                                            )
                                        ) {
                                            Text(section.title)
                                                .font(AppTypography.bodySmall)
                                                .foregroundStyle(.primary)
                                        }
                                        .toggleStyle(.checkbox)

                                        Spacer(minLength: 0)

                                        HStack(spacing: 6) {
                                            Button {
                                                moveFilterSection(at: index, delta: -1)
                                            } label: {
                                                Image(systemName: "arrow.up")
                                                    .frame(width: 24, height: 24)
                                            }
                                            .settingsIconButtonStyle()
                                            .disabled(index == 0)

                                            Button {
                                                moveFilterSection(at: index, delta: 1)
                                            } label: {
                                                Image(systemName: "arrow.down")
                                                    .frame(width: 24, height: 24)
                                            }
                                            .settingsIconButtonStyle()
                                            .disabled(index == config.filterPanelOrder.count - 1)
                                        }
                                        .foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    if index < config.filterPanelOrder.count - 1 {
                                        Divider().padding(.leading, 10)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func toggleFilterSection(_ section: FilterPanelSection, enabled: Bool) {
        var next = config.visibleFilterSections
        if enabled {
            if !next.contains(section.rawValue) {
                next.append(section.rawValue)
            }
        } else {
            next.removeAll { $0 == section.rawValue }
        }
        try? config.setVisibleFilterSections(next)
    }

    private func moveFilterSection(at index: Int, delta: Int) {
        let destination = index + delta
        guard destination >= 0, destination < config.filterPanelOrder.count else { return }
        var next = config.filterPanelOrder
        let item = next.remove(at: index)
        next.insert(item, at: destination)
        try? config.setFilterPanelOrder(next)
    }
}


// MARK: - Feed Settings Panel

struct FeedSettingsPanel: View {
    @ObservedObject private var feedViewModel = FeedViewModel.shared
    @State private var autoRefresh = FeedViewModel.autoRefreshOnLaunch
    @State private var editingID: UUID? = nil
    @State private var editURL = ""
    @State private var editLabel = ""
    @State private var newURL = ""
    @State private var newLabel = ""
    @FocusState private var urlFieldFocused: Bool

    private var newURLIsValid: Bool {
        URL(string: newURL.trimmingCharacters(in: .whitespacesAndNewlines))?.scheme?.hasPrefix("http") == true
    }
    private var editURLIsValid: Bool {
        URL(string: editURL.trimmingCharacters(in: .whitespacesAndNewlines))?.scheme?.hasPrefix("http") == true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppMetrics.sectionSpacing) {
            SettingsSection("Subscriptions") {
                SettingsPanelCard(
                    "Active Feeds",
                    caption: "Papyrus fetches these RSS / Atom URLs and surfaces new papers in your Feed."
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        if feedViewModel.subscriptions.isEmpty {
                            Text("No feeds yet. Add one below.")
                                .font(AppTypography.bodySmall)
                                .foregroundStyle(.tertiary)
                        } else {
                            ForEach(feedViewModel.subscriptions) { sub in
                                if editingID == sub.id {
                                    editRow(sub)
                                } else {
                                    subscriptionRow(sub)
                                }
                            }
                        }
                    }
                }
            }

            SettingsSection("Add Feed") {
                SettingsPanelCard(
                    "RSS / Atom URL",
                    caption: "Paste any RSS or Atom feed URL. Works with arXiv, PubMed, journal feeds, and more."
                ) {
                    addForm
                }
            }

            SettingsSection("Behavior") {
                SettingsPanelCard(
                    "Auto-Refresh on Launch",
                    caption: "Automatically check for new papers when the app starts (at most once per hour per subscription)."
                ) {
                    Toggle("", isOn: $autoRefresh)
                        .labelsHidden()
                        .onChange(of: autoRefresh) { _, v in FeedViewModel.autoRefreshOnLaunch = v }
                }
            }
        }
        .onAppear { autoRefresh = FeedViewModel.autoRefreshOnLaunch }
    }

    // MARK: - Subscription Row

    @ViewBuilder
    private func subscriptionRow(_ sub: FeedSubscription) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "dot.radiowaves.up.forward")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(sub.isEnabled ? Color.accentColor : Color.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(sub.displayLabel)
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(sub.isEnabled ? .primary : .secondary)
                HStack(spacing: 4) {
                    Text(sub.value)
                        .font(AppTypography.labelMedium)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                    if let last = sub.lastFetchedAt {
                        Text("· checked \(last, style: .relative) ago")
                            .font(AppTypography.labelMedium)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { sub.isEnabled },
                set: { _ in Task { await feedViewModel.toggleSubscription(id: sub.id) } }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.small)

            Button {
                editURL = sub.value
                editLabel = sub.displayLabel
                editingID = sub.id
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Edit")

            Button {
                Task { await feedViewModel.removeSubscription(id: sub.id) }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .appCardSurface()
    }

    // MARK: - Edit Row

    @ViewBuilder
    private func editRow(_ sub: FeedSubscription) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("URL", text: $editURL)
                .textFieldStyle(.plain)
                .padding(.horizontal, AppMetrics.pillHorizontal + 4)
                .padding(.vertical, AppMetrics.pillVertical + 3)
                .appInsetInputSurface(
                    fill: Color.primary.opacity(0.05),
                    stroke: editURLIsValid ? Color.primary.opacity(0.08) : Color.orange.opacity(0.5),
                    cornerRadius: AppMetrics.controlCornerRadius
                )
                .onSubmit { saveEdit(sub) }

            TextField("Label", text: $editLabel)
                .textFieldStyle(.plain)
                .padding(.horizontal, AppMetrics.pillHorizontal + 4)
                .padding(.vertical, AppMetrics.pillVertical + 3)
                .appInsetInputSurface(
                    fill: Color.primary.opacity(0.04),
                    stroke: Color.primary.opacity(0.06),
                    cornerRadius: AppMetrics.controlCornerRadius
                )
                .onSubmit { saveEdit(sub) }

            HStack(spacing: 8) {
                Button("Save") { saveEdit(sub) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!editURLIsValid)

                Button("Cancel") { editingID = nil }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .appCardSurface()
    }

    private func saveEdit(_ sub: FeedSubscription) {
        let value = editURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard editURLIsValid else { return }
        let label = editLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedLabel = label.isEmpty ? (URL(string: value)?.host ?? value) : label
        var updated = sub
        updated.value = value
        updated.displayLabel = resolvedLabel
        updated.lastFetchedAt = nil  // reset so next refresh fetches fresh
        Task {
            await feedViewModel.updateSubscription(updated)
            editingID = nil
        }
    }

    // MARK: - Add Form

    private var addForm: some View {
        HStack(spacing: 8) {
            TextField("https://...", text: $newURL)
                .textFieldStyle(.plain)
                .padding(.horizontal, AppMetrics.pillHorizontal + 4)
                .padding(.vertical, AppMetrics.pillVertical + 4)
                .appInsetInputSurface(
                    fill: Color.primary.opacity(0.05),
                    stroke: Color.primary.opacity(0.08),
                    cornerRadius: AppMetrics.controlCornerRadius
                )
                .focused($urlFieldFocused)
                .onSubmit { addSub() }

            TextField("Label (optional)", text: $newLabel)
                .textFieldStyle(.plain)
                .padding(.horizontal, AppMetrics.pillHorizontal + 4)
                .padding(.vertical, AppMetrics.pillVertical + 4)
                .appInsetInputSurface(
                    fill: Color.primary.opacity(0.04),
                    stroke: Color.primary.opacity(0.06),
                    cornerRadius: AppMetrics.controlCornerRadius
                )
                .onSubmit { addSub() }
                .frame(maxWidth: 160)

            Button { addSub() } label: {
                Label("Add", systemImage: "plus")
                    .font(AppTypography.bodySmall)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(!newURLIsValid)
        }
    }

    private func addSub() {
        let value = newURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard newURLIsValid else { return }
        let label = newLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedLabel = label.isEmpty ? URL(string: value)?.host : label
        let sub = FeedSubscription(type: .rssURL, value: value, displayLabel: resolvedLabel)
        Task {
            await feedViewModel.addSubscription(sub)
            newURL = ""
            newLabel = ""
            urlFieldFocused = true
        }
    }
}

struct MetadataSettingsPanel: View {
    @ObservedObject var config: AppConfig
    @Binding var semanticScholarKey: String
    @Binding var easyScholarKey: String
    @Binding var rankSourceText: String
    @Binding var venuesText: String
    let venuesError: String?
    let apiFieldFocused: FocusState<SettingsAPIField?>.Binding
    let rankSourcesFocused: FocusState<Bool>.Binding
    let venuesFocused: FocusState<Bool>.Binding
    let isRefreshingVenues: Bool
    let onApplySemanticScholarKey: () -> Void
    let onApplyEasyScholarKey: () -> Void
    let onApplyRankSources: () -> Void
    let onRefreshVenueRankings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppMetrics.sectionSpacing) {
            SettingsSection("API Keys") {
                SettingsPanelCard("Metadata Sources", caption: "Configure external services used to enrich papers and fetch rankings.") {
                    VStack(alignment: .leading, spacing: 16) {
                        apiField(
                            label: "Semantic Scholar",
                            description: "Used for citation counts and reference data. Optional, but more reliable with a key.",
                            placeholder: "API key (optional)",
                            text: $semanticScholarKey,
                            isSet: !config.semanticScholarKey.isEmpty,
                            focus: .semantic,
                            onSubmit: onApplySemanticScholarKey
                        )

                        Divider().opacity(0.45)

                        apiField(
                            label: "EasyScholar",
                            description: "Used for venue ranking sources fetched from EasyScholar.",
                            placeholder: "API key (optional)",
                            text: $easyScholarKey,
                            isSet: !config.easyscholarKey.isEmpty,
                            focus: .easy,
                            onSubmit: onApplyEasyScholarKey
                        )
                    }
                }
            }

            SettingsSection("Rank Sources") {
                SettingsPanelCard("Visible Rank Sources", caption: "Choose which ranking sources are shown in the list and detail views. Leave empty to show everything available.") {
                    SettingsPillTextField(
                        placeholder: "e.g. sci, ei, cssci",
                        text: $rankSourceText,
                        onSubmit: onApplyRankSources,
                        isFocused: rankSourcesFocused
                    )

                    if !config.rankBadgeSources.isEmpty {
                        Text("Current: \(RankSourceConfig.formatText(config.rankBadgeSources))")
                            .font(AppTypography.label)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            SettingsSection("Venue Rankings") {
                SettingsPanelCard("Refresh Rankings", caption: "Re-fetch rankings for all venues in your library.") {
                    Button(action: onRefreshVenueRankings) {
                        HStack(spacing: 6) {
                            if isRefreshingVenues {
                                ProgressView().controlSize(.small)
                            }
                            Text(isRefreshingVenues ? "Refreshing…" : "Refresh All Venue Rankings")
                        }
                    }
                    .settingsSecondaryButtonStyle()
                    .disabled(isRefreshingVenues || config.easyscholarKey.isEmpty)
                    .help(config.easyscholarKey.isEmpty ? "Set an EasyScholar API key first" : "Re-fetch rankings for all known venues")

                    Text("Use this after changing the EasyScholar key or when venue classifications look outdated.")
                        .font(AppTypography.label)
                        .foregroundStyle(.tertiary)
                }
            }

            SettingsSection("Venue Abbreviations") {
                SettingsPanelCard("Custom Abbreviations", caption: "One mapping per line: Full Venue Name = Abbreviation. Changes apply when leaving the editor.") {
                    TextEditor(text: $venuesText)
                        .font(AppTypography.monoSmall)
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .frame(minHeight: 320)
                        .appInsetInputSurface(
                            fill: Color.primary.opacity(0.03),
                            stroke: Color.primary.opacity(0.06),
                            cornerRadius: AppMetrics.controlCornerRadius
                        )
                        .focused(venuesFocused)

                    if let venuesError {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(AppTypography.label)
                            Text(venuesError)
                                .font(AppTypography.label)
                        }
                        .foregroundStyle(.red)
                    }
                }
            }
        }
    }

    private func apiField(
        label: String,
        description: String,
        placeholder: String,
        text: Binding<String>,
        isSet: Bool,
        focus: SettingsAPIField,
        onSubmit: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(label)
                    .font(AppTypography.bodySmallMedium)
                    .foregroundStyle(.primary)
                Circle()
                    .fill(isSet ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: 7, height: 7)
                Text(isSet ? "Key set" : "No key")
                    .font(AppTypography.labelMedium)
                    .foregroundStyle(isSet ? Color.green : Color.secondary)
            }
            Text(description)
                .font(AppTypography.label)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            SettingsMonoTextField(
                placeholder: placeholder,
                text: text,
                onSubmit: onSubmit,
                focus: focus,
                isFocused: apiFieldFocused
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(Color.primary.opacity(0.018), in: RoundedRectangle(cornerRadius: AppMetrics.controlCornerRadius))
    }

    private func settingsField(
        label: String,
        description: String,
        placeholder: String,
        text: Binding<String>,
        focus: SettingsAPIField,
        onSubmit: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(AppTypography.bodySmallMedium)
                .foregroundStyle(.primary)
            Text(description)
                .font(AppTypography.label)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            SettingsMonoTextField(
                placeholder: placeholder,
                text: text,
                onSubmit: onSubmit,
                focus: focus,
                isFocused: apiFieldFocused
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(Color.primary.opacity(0.018), in: RoundedRectangle(cornerRadius: AppMetrics.controlCornerRadius))
    }
}

struct KeyboardSettingsPanel: View {
    let actions: [InputAction]
    let bindingForAction: (InputAction) -> String
    let shortcutLabel: (InputAction) -> String
    let validationMessage: (InputAction, String) -> String?
    let recordingStatusMessage: (InputAction) -> String?
    let isRecording: (InputAction) -> Bool
    let recordingPreview: (InputAction) -> String?
    let onToggleRecording: (InputAction) -> Void
    let onClear: (InputAction) -> Void
    let onRestoreDefaults: () -> Void
    let onRowFrameChange: (InputAction, CGRect) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppMetrics.sectionSpacing) {
            SettingsSection("Keyboard") {
                SettingsPanelCard(
                    "Keyboard Shortcuts",
                    caption: "Click a shortcut to change it.\nSingle-key shortcuts are limited to Space, Return, Delete, Escape, and F1-F6.",
                    trailingAccessory: AnyView(
                        Button("Restore Defaults", action: onRestoreDefaults)
                            .settingsSecondaryButtonStyle()
                    )
                ) {
                    SettingsInsetGroup {
                        ForEach(actions) { action in
                            KeyboardShortcutRow(
                                action: action,
                                title: shortcutLabel(action),
                                value: bindingForAction(action),
                                helper: AppShortcutConfig.helperText(for: action),
                                validationMessage: validationMessage(action, bindingForAction(action)),
                                recordingStatusMessage: recordingStatusMessage(action),
                                recording: isRecording(action),
                                recordingPreview: recordingPreview(action),
                                onToggleRecording: { onToggleRecording(action) },
                                onClear: { onClear(action) },
                                onFrameChange: { onRowFrameChange(action, $0) }
                            )
                            if action != actions.last {
                                Divider().opacity(0.14).padding(.leading, 12)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct KeyboardShortcutRow: View {
    let action: InputAction
    let title: String
    let value: String
    let helper: String
    let validationMessage: String?
    let recordingStatusMessage: String?
    let recording: Bool
    let recordingPreview: String?
    let onToggleRecording: () -> Void
    let onClear: () -> Void
    let onFrameChange: (CGRect) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(AppTypography.bodyStrong)
                    .foregroundStyle(.primary)
                Text(statusLine)
                    .font(AppTypography.label)
                    .foregroundStyle(statusLineColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, minHeight: 16, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                shortcutBadge(label: shortcutBadgeLabel)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onToggleRecording)
                    .help(recording ? "Press a shortcut. Esc cancels." : "Click to change shortcut")

                Button(action: onClear) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary.opacity(value.isEmpty ? 0 : 0.62))
                .background(Color.primary.opacity(value.isEmpty ? 0 : 0.04), in: Circle())
                .opacity(value.isEmpty ? 0 : 1)
                .allowsHitTesting(!value.isEmpty)
                .help("Clear shortcut")
            }
            .frame(width: 214, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            GeometryReader { proxy in
                RoundedRectangle(cornerRadius: AppMetrics.controlCornerRadius)
                    .fill(recording ? Color.primary.opacity(0.03) : Color.clear)
                    .onAppear {
                        let frame = proxy.frame(in: .global)
                        DispatchQueue.main.async {
                            onFrameChange(frame)
                        }
                    }
                    .onChange(of: proxy.frame(in: .global)) { _, newValue in
                        DispatchQueue.main.async {
                            onFrameChange(newValue)
                        }
                    }
            }
        )
    }

    private var shortcutBadgeLabel: String {
        if let recordingPreview, !recordingPreview.isEmpty {
            return AppShortcutConfig.displayString(for: recordingPreview)
        }
        return recording ? "Press shortcut…" : AppShortcutConfig.displayString(for: value)
    }

    private var statusLine: String {
        if let validationMessage {
            return validationMessage
        }
        if let recordingStatusMessage {
            return recordingStatusMessage
        }
        return recording ? "Press shortcut. Esc cancels." : helper
    }

    private var statusLineColor: Color {
        if validationMessage != nil || recordingStatusMessage != nil {
            return Color.orange.opacity(0.82)
        }
        return recording ? .primary : .secondary
    }


    private func shortcutBadge(label: String) -> some View {
        HStack(spacing: 0) {
            Text(label)
                .font(AppTypography.monoLabel)
                .foregroundStyle(recording ? Color.primary : (value.isEmpty ? Color.secondary : Color.primary))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .frame(minWidth: 158, alignment: .leading)
        .background(
            Capsule(style: .continuous)
                .fill(recording ? Color.primary.opacity(0.05) : (value.isEmpty ? Color.primary.opacity(0.022) : Color.primary.opacity(0.038)))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(recording ? Color.primary.opacity(0.11) : Color.primary.opacity(value.isEmpty ? 0.045 : 0.06), lineWidth: 1)
        )
    }

}

// MARK: - Extensions Settings Panel

struct ExtensionsSettingsPanel: View {
    @State private var safariExtensionEnabled: Bool? = nil
    @State private var showingSafariSetupAlert = false

    private let safariExtensionID = "com.papyrus.app.web-clipper.Extension"
    // TODO: Replace with the published Chrome Web Store URL
    private let chromeWebStoreURL = URL(string: "https://chromewebstore.google.com")!

    var body: some View {
        VStack(alignment: .leading, spacing: AppMetrics.sectionSpacing) {
            SettingsSection("Browser Extensions") {
                VStack(alignment: .leading, spacing: 10) {
                    safariCard
                    chromeCard
                }
            }
        }
        .onAppear { refreshSafariState() }
        .alert("Safari Extension Not Visible", isPresented: $showingSafariSetupAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("""
Enable unsigned extensions in Safari first:

1. Safari > Settings > Advanced
   Show features for web developers
2. Safari > Settings > Developer > Extensions
   Allow unsigned extensions

Then click "Set Up in Safari" again.
Note: this must be re-enabled after each Mac restart.
""")
        }
    }

    // MARK: Safari

    private var safariCard: some View {
        SettingsPanelCard(
            "Safari Extension",
            caption: "Clip papers to Papyrus directly from Safari.",
            trailingAccessory: AnyView(safariStatusBadge)
        ) {
            Button("Set Up in Safari") { openSafariExtensionPreferences() }
                .settingsSecondaryButtonStyle()
        }
    }

    @ViewBuilder
    private var safariStatusBadge: some View {
        if let enabled = safariExtensionEnabled {
            HStack(spacing: 5) {
                Circle()
                    .fill(enabled ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: 7, height: 7)
                Text(enabled ? "Enabled" : "Not enabled")
                    .font(AppTypography.label)
                    .foregroundStyle(enabled ? .primary : .secondary)
            }
        }
    }

    private func refreshSafariState() {
        SFSafariExtensionManager.getStateOfSafariExtension(withIdentifier: safariExtensionID) { state, _ in
            DispatchQueue.main.async {
                safariExtensionEnabled = state?.isEnabled
            }
        }
    }

    private func openSafariExtensionPreferences() {
        var didFinish = false

        SFSafariApplication.showPreferencesForExtension(withIdentifier: safariExtensionID) { error in
            didFinish = true
            DispatchQueue.main.async {
                if let error = error as NSError?, error.domain == "SFErrorDomain" {
                    showingSafariSetupAlert = true
                } else {
                    refreshSafariState()
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            guard !didFinish else { return }
            showingSafariSetupAlert = true
        }
    }

    // MARK: Chrome

    private var chromeCard: some View {
        SettingsPanelCard(
            "Chrome Extension",
            caption: "Works with Chrome, Edge, Arc, and other Chromium-based browsers."
        ) {
            Button("Get from Chrome Web Store") {
                NSWorkspace.shared.open(chromeWebStoreURL)
            }
            .settingsSecondaryButtonStyle()
        }
    }
}
