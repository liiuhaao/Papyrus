import SwiftUI

struct PaperEditorView: View {
    private enum MetadataUpdateMode: String, CaseIterable, Identifiable {
        case auto = "auto"
        case manual = "manual"

        var id: String { rawValue }
        var title: String { self == .auto ? "Auto" : "Manual" }
    }

    private enum FocusField: Hashable {
        case tags
        case title
    }

    @ObservedObject var paper: Paper
    let viewModel: PaperListViewModel
    let suggestions: [String]
    let onSaved: (Paper) -> Void
    var onClose: (() -> Void)? = nil

    @State private var tags: [String] = []
    @State private var tagSearch: String = ""
    @State private var titleText: String = ""
    @State private var authorsText: String = ""
    @State private var venueText: String = ""
    @State private var yearText: String = ""
    @State private var doiText: String = ""
    @State private var arxivText: String = ""
    @State private var publicationType: String = ""
    @State private var updateMode: MetadataUpdateMode = .auto
    @State private var showSourcePicker = false
    @State private var selectedSourceLabel: String = "Manual"
    @State private var selectedCandidateKey: String? = nil
    @FocusState private var focusedField: FocusField?

    private var namespaceChips: [String] {
        TagNamespaceSupport.namespaceChips(from: suggestions + tags)
    }

    private var availableTags: [String] {
        let query = tagSearch.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = suggestions.filter { suggestion in
            !tags.contains(where: { $0.caseInsensitiveCompare(suggestion) == .orderedSame }) &&
            (query.isEmpty || suggestion.lowercased().contains(query))
        }
        return TagNamespaceSupport.sortTags(filtered)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AppEditorHeader(
                title: "Edit",
                subtitle: nil,
                confirmTitle: "Save",
                onCancel: { onClose?() },
                onConfirm: save
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    AppEditorSection("Tags") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Add, remove, and reuse tags.")
                                .font(AppTypography.label)
                                .foregroundStyle(.tertiary)

                            HStack(spacing: AppEditorMetrics.compactSpacing) {
                                Image(systemName: "magnifyingglass")
                                    .foregroundStyle(.tertiary)
                                    .font(.system(size: AppEditorMetrics.compactIconSize))
                                TextField("Search or add tag…", text: $tagSearch)
                                    .textFieldStyle(.plain)
                                    .font(AppTypography.body)
                                    .focused($focusedField, equals: .tags)
                                    .onSubmit { commitTagSearch() }
                                if !tagSearch.trimmingCharacters(in: .whitespaces).isEmpty {
                                    Button("Add") { commitTagSearch() }
                                        .buttonStyle(.plain)
                                        .font(.system(size: AppEditorMetrics.compactIconSize, weight: .medium))
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .padding(.horizontal, AppEditorMetrics.tagInputHorizontalPadding)
                            .padding(.vertical, AppEditorMetrics.tagInputVerticalPadding)
                            .appInsetInputSurface(
                                fill: Color.primary.opacity(0.035),
                                stroke: Color.primary.opacity(0.06),
                                cornerRadius: AppEditorMetrics.inputCornerRadius
                            )

                            namespaceChipRow(namespaceChips) { chip in
                                tagSearch = TagNamespaceSupport.applyingNamespaceChip(chip, to: tagSearch)
                                focusedField = .tags
                            }

                            if tags.isEmpty {
                                Text("No tags added")
                                    .font(AppTypography.label)
                                    .foregroundStyle(.tertiary)
                            } else {
                                Text("Current")
                                    .font(AppTypography.labelStrong)
                                    .foregroundStyle(.secondary)
                                FlowTagCloud(tags: tags) { removeTag($0) }
                            }

                            if !availableTags.isEmpty {
                                Text("Suggestions")
                                    .font(AppTypography.labelStrong)
                                    .foregroundStyle(.secondary)
                                TagFlowLayout(spacing: AppEditorMetrics.compactSpacing) {
                                    ForEach(availableTags, id: \.self) { tag in
                                        Button { addTag(tag) } label: {
                                            let tint = AppColors.tagColor(tag)
                                            HStack(spacing: AppEditorMetrics.microSpacing) {
                                                Image(systemName: "plus")
                                                    .font(.system(size: AppEditorMetrics.miniIconSize, weight: .semibold))
                                                Text(tag)
                                            }
                                            .appPill(
                                                background: tint.opacity(0.10),
                                                foreground: tint
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            } else if !tagSearch.trimmingCharacters(in: .whitespaces).isEmpty {
                                Text("No matches - press Add to create")
                                    .font(AppTypography.label)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }

                    AppEditorSection("Metadata") {
                        VStack(alignment: .leading, spacing: 0) {
                            // Source control row
                            HStack(alignment: .center, spacing: 10) {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.down.circle")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.tertiary)

                                    Text(selectedSourceLabel)
                                        .font(AppTypography.bodySmall)
                                        .foregroundStyle(.primary)
                                }

                                Spacer(minLength: 0)

                                if paper.fetchCandidatesJSON != nil {
                                    Button("Change Source…") { showSourcePicker = true }
                                        .buttonStyle(.plain)
                                        .font(AppTypography.label)
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .padding(.bottom, AppEditorMetrics.bodyBottomSpacing)

                            AppEditorFieldRow(label: "Title", labelWidth: AppEditorMetrics.fieldLabelWidth) {
                                TextField("", text: $titleText)
                                    .textFieldStyle(.roundedBorder)
                                    .focused($focusedField, equals: .title)
                            }
                            rowDivider()
                            AppEditorFieldRow(label: "Authors", labelWidth: AppEditorMetrics.fieldLabelWidth) {
                                TextField("", text: $authorsText)
                                    .textFieldStyle(.roundedBorder)
                            }
                            rowDivider()
                            AppEditorFieldRow(label: "Venue", labelWidth: AppEditorMetrics.fieldLabelWidth) {
                                TextField("", text: $venueText)
                                    .textFieldStyle(.roundedBorder)
                            }
                            rowDivider()
                            AppEditorFieldRow(label: "DOI", labelWidth: AppEditorMetrics.fieldLabelWidth) {
                                TextField("", text: $doiText)
                                    .textFieldStyle(.roundedBorder)
                            }
                            rowDivider()
                            AppEditorFieldRow(label: "arXiv", labelWidth: AppEditorMetrics.fieldLabelWidth) {
                                TextField("", text: $arxivText)
                                    .textFieldStyle(.roundedBorder)
                            }
                            rowDivider()
                            AppEditorDoubleFieldRow(
                                leftLabel: "Year",
                                leftLabelWidth: AppEditorMetrics.fieldLabelWidth,
                                rightLabel: "Type",
                                rightLabelWidth: AppEditorMetrics.smallFieldLabelWidth,
                                leftField: {
                                    TextField("", text: $yearText)
                                        .textFieldStyle(.roundedBorder)
                                },
                                rightField: {
                                    Picker("", selection: $publicationType) {
                                        Text("—").tag("")
                                        Text("Conference").tag("conference")
                                        Text("Journal").tag("journal")
                                        Text("Workshop").tag("workshop")
                                        Text("Preprint").tag("preprint")
                                        Text("Book/Chapter").tag("book")
                                        Text("Other").tag("other")
                                    }
                                    .labelsHidden()
                                    .pickerStyle(.menu)
                                }
                            )

                            // Lock toggle
                            HStack(spacing: 8) {
                                Spacer()
                                    .frame(width: AppEditorMetrics.fieldLabelWidth)
                                Toggle(isOn: Binding(
                                    get: { updateMode == .manual },
                                    set: { isOn in updateMode = isOn ? .manual : .auto }
                                )) {
                                    Text("Lock fields from automatic updates")
                                        .font(AppTypography.label)
                                        .foregroundStyle(.secondary)
                                }
                                .toggleStyle(.checkbox)
                                Spacer(minLength: 0)
                            }
                            .padding(.top, AppEditorMetrics.bodyBottomSpacing)
                        }
                    }
                }
                .padding(.horizontal, AppEditorMetrics.sectionHorizontalPadding)
                .padding(.vertical, AppEditorMetrics.sectionVerticalPadding)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheet(isPresented: $showSourcePicker) {
            MetadataSourcePickerView(
                paper: paper,
                selectedCandidateKey: selectedCandidateKey,
                onSelect: { candidate in
                    showSourcePicker = false
                    applyCandidateToEditor(candidate)
                },
                onCancel: { showSourcePicker = false }
            )
        }
        .onAppear {
            tags = paper.tagsList
            reloadFieldsFromPaper()
            let anyManual = paper.titleManual || paper.authorsManual || paper.venueManual
                || paper.yearManual || paper.doiManual || paper.arxivManual || paper.publicationTypeManual
            updateMode = anyManual ? .manual : .auto
            focusedField = .tags
        }
    }

    private func rowDivider() -> some View {
        Divider()
            .padding(.leading, AppEditorMetrics.fieldLabelWidth + 12)
    }

    private func reloadFieldsFromPaper() {
        titleText = paper.title ?? ""
        authorsText = paper.authors ?? ""
        venueText = paper.venue ?? ""
        yearText = paper.year > 0 ? "\(paper.year)" : ""
        doiText = paper.doi ?? ""
        arxivText = paper.arxivId ?? ""
        publicationType = paper.publicationType ?? ""
        selectedSourceLabel = paper.fetchSelectedSource ?? "Manual"
        selectedCandidateKey = resolveCurrentCandidateKey()
    }

    private func resolveCurrentCandidateKey() -> String? {
        guard let json = paper.fetchCandidatesJSON,
              let data = json.data(using: .utf8),
              let candidates = try? JSONDecoder().decode([MetadataCandidate].self, from: data) else {
            return nil
        }
        let currentTitle = MetadataNormalization.normalizeTitle(paper.title)
        for candidate in candidates {
            if candidate.source == paper.fetchSelectedSource,
               MetadataNormalization.normalizeTitle(candidate.metadata.title) == currentTitle {
                return candidate.uniqueKey
            }
        }
        return nil
    }

    private func commitTagSearch() {
        let tag = tagSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty else { return }
        addTag(tag)
    }

    private func addTag(_ raw: String) {
        let tag = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty else { return }
        if !tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
            tags.append(tag)
        }
        tagSearch = ""
        focusedField = .tags
    }

    private func removeTag(_ tag: String) {
        tags.removeAll { $0.caseInsensitiveCompare(tag) == .orderedSame }
    }

    @ViewBuilder
    private func namespaceChipRow(
        _ chips: [String],
        onSelect: @escaping (String) -> Void
    ) -> some View {
        if !chips.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Namespaces")
                    .font(AppTypography.labelStrong)
                    .foregroundStyle(.secondary)
                TagFlowLayout(spacing: AppEditorMetrics.compactSpacing) {
                    ForEach(chips, id: \.self) { chip in
                        Button {
                            onSelect(chip)
                        } label: {
                            let namespace = String(chip.dropLast())
                            Text(chip)
                                .appBadgePill(AppColors.namespaceColor(namespace), horizontal: 9, vertical: 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func applyCandidateToEditor(_ candidate: MetadataCandidate) {
        let normalized = MetadataNormalization.normalizeMetadata(candidate.metadata)
        let canonicalVenue = normalized.venue.map {
            VenueFormatter.expandedFullName(forAbbreviation: $0)
                ?? VenueFormatter.standardFullName($0)
                ?? $0
        }
        titleText = normalized.title ?? ""
        authorsText = normalized.authors ?? ""
        venueText = canonicalVenue ?? ""
        yearText = normalized.year > 0 ? "\(normalized.year)" : ""
        doiText = normalized.doi ?? ""
        arxivText = normalized.arxivId ?? ""
        publicationType = normalized.publicationType ?? ""
        selectedSourceLabel = candidate.source
        selectedCandidateKey = candidate.uniqueKey
    }

    private func save() {
        paper.tags = tags.isEmpty ? nil : tags.joined(separator: ", ")
        let normalizedYear = Int16(yearText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        paper.applyMetadataEdit(
            title: titleText.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            authors: authorsText.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            venue: venueText.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            year: max(0, normalizedYear),
            doi: doiText.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            arxivId: arxivText.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            publicationType: publicationType.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            isManual: updateMode == .manual
        )
        // Update audit fields if user changed source via picker
        if selectedSourceLabel != "Manual",
           selectedSourceLabel != paper.fetchSelectedSource {
            paper.fetchSelectedSource = selectedSourceLabel
            paper.fetchTimestamp = Date()
        }
        onSaved(paper)
        onClose?()
    }
}

private struct FlowTagCloud: View {
    let tags: [String]
    let onTap: (String) -> Void

    var body: some View {
        TagFlowLayout(spacing: AppEditorMetrics.compactSpacing) {
            ForEach(tags, id: \.self) { tag in
                Button {
                    onTap(tag)
                } label: {
                    let tint = AppColors.tagColor(tag)
                    HStack(spacing: AppEditorMetrics.microSpacing) {
                        Text(tag)
                        Image(systemName: "xmark")
                            .font(.system(size: AppEditorMetrics.miniIconSize, weight: .semibold))
                            .foregroundStyle(tint.opacity(0.6))
                    }
                    .appPill(background: tint.opacity(0.16), foreground: tint)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct TagFlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                usedWidth = max(usedWidth, x - spacing)
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        usedWidth = max(usedWidth, max(0, x - spacing))
        let totalHeight = y + rowHeight
        let finalWidth = proposal.width ?? usedWidth
        return CGSize(width: finalWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
