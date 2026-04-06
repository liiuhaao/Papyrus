// BatchEditView.swift
// Batch-edit panel for multi-selected papers

import SwiftUI

// MARK: - Batch Edit State

struct BatchEditState {
    // nil = "No Change"
    var status: Paper.ReadingStatus? = nil
    // -1 = "No Change", 0 = clear, 1-5 = set
    var rating: Int = -1
    // Tags to add (user typed/selected but not yet applied)
    var tagsToAdd: Set<String> = []
    // Tags to remove (user chose to remove shared tags)
    var tagsToRemove: Set<String> = []

    var hasChanges: Bool {
        status != nil || rating != -1 || !tagsToAdd.isEmpty || !tagsToRemove.isEmpty
    }
}

// MARK: - BatchEditView

struct BatchEditView: View {
    let papers: [Paper]
    let allTags: [String]
    let onApply: (_ state: BatchEditState) -> Void
    let onCancel: () -> Void

    @State private var editState = BatchEditState()
    @State private var tagInput: String = ""
    @FocusState private var isTagInputFocused: Bool

    private var namespaceChips: [String] {
        TagNamespaceSupport.namespaceChips(from: allTags + Array(sharedTags) + Array(mixedTags))
    }

    // Tags shared by ALL selected papers
    private var sharedTags: Set<String> {
        guard let first = papers.first else { return [] }
        var shared = Set(first.tagsList)
        for paper in papers.dropFirst() {
            shared.formIntersection(Set(paper.tagsList))
        }
        return shared
    }

    // Tags present in SOME (but not all) papers
    private var mixedTags: Set<String> {
        var all: Set<String> = []
        for paper in papers { all.formUnion(Set(paper.tagsList)) }
        return all.subtracting(sharedTags)
    }

    private func availableTags(matching query: String) -> [String] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = allTags.filter { tag in
            !editState.tagsToAdd.contains(tag)
            && !sharedTags.contains(tag)
            && !mixedTags.contains(tag)
            && (q.isEmpty || tag.lowercased().contains(q))
        }
        return TagNamespaceSupport.sortTags(filtered)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AppEditorHeader(
                title: "Batch Edit",
                subtitle: "\(papers.count) selected papers",
                confirmTitle: "Apply",
                confirmDisabled: !editState.hasChanges,
                onCancel: onCancel,
                onConfirm: { onApply(editState) }
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    AppEditorSection("Tags") { tagsSection }

                    AppEditorSection("Fields") {
                        VStack(spacing: 0) {
                            BatchEditFieldBlock(label: "Status") {
                                statusPicker
                            }
                            BatchEditFieldBlock(label: "Rating") {
                                ratingPicker
                            }
                        }
                    }
                }
                .padding(.horizontal, AppEditorMetrics.sectionHorizontalPadding)
                .padding(.vertical, AppEditorMetrics.sectionVerticalPadding)
            }

            if editState.hasChanges {
                changesPreview
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { isTagInputFocused = true }
    }

    // MARK: - Status Picker

    private var statusPicker: some View {
        FlowLayout(spacing: AppEditorMetrics.chipSpacing) {
            noChangeChip(selected: editState.status == nil) { editState.status = nil }
            ForEach(Paper.ReadingStatus.allCases, id: \.self) { s in
                statusChip(s, selected: editState.status == s) { editState.status = s }
            }
        }
    }

    private func noChangeChip(selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("No Change")
                .font(AppTypography.bodySmall)
                .lineLimit(1)
                .appBadgePill(.secondary, horizontal: 9, vertical: 4)
                .opacity(selected ? 1 : 0.65)
        }
        .buttonStyle(.plain)
    }

    private func statusChip(_ status: Paper.ReadingStatus, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(status.label)
                .font(AppTypography.bodySmall)
                .lineLimit(1)
                .appBadgePill(selected ? AppStatusStyle.tint(for: status) : .secondary, horizontal: 9, vertical: 4)
                .opacity(selected ? 1 : 0.8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Rating Picker

    private var ratingPicker: some View {
        HStack(spacing: AppEditorMetrics.chipSpacing) {
            noChangeChip(selected: editState.rating == -1) { editState.rating = -1 }
            BatchEditStarRating(rating: $editState.rating)
        }
    }

    private func ratingNoChangeChip(selected: Bool, action: @escaping () -> Void) -> some View {
        noChangeChip(selected: selected, action: action)
    }

    private struct BatchEditFieldBlock<Content: View>: View {
        let label: String
        @ViewBuilder let content: Content

        init(
            label: String,
            @ViewBuilder content: () -> Content
        ) {
            self.label = label
            self.content = content()
        }

        var body: some View {
            VStack(alignment: .leading, spacing: AppEditorMetrics.compactSpacing) {
                Text(label)
                    .font(AppTypography.label)
                    .foregroundStyle(.secondary)
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, AppEditorMetrics.compactSpacing)
        }
    }

    // MARK: - Tags Section

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: AppEditorMetrics.sectionSpacing) {
            // Shared tags (ALL papers) — click to mark for removal
            if !sharedTags.isEmpty {
                tagSubsection(label: "Shared by all") {
                    FlowLayout(spacing: AppEditorMetrics.chipSpacing) {
                        ForEach(TagNamespaceSupport.sortTags(Array(sharedTags)), id: \.self) { tag in
                            let removing = editState.tagsToRemove.contains(tag)
                            let tint = AppColors.tagColor(tag)
                            Button {
                                if removing { editState.tagsToRemove.remove(tag) }
                                else        { editState.tagsToRemove.insert(tag) }
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: removing ? "minus.circle.fill" : "xmark.circle.fill")
                                        .font(.system(size: AppEditorMetrics.miniIconSize))
                                        .foregroundStyle(removing ? Color.red : tint.opacity(0.65))
                                    Text(tag)
                                        .font(.system(size: AppEditorMetrics.compactTextSize))
                                        .foregroundStyle(removing ? Color.red : tint)
                                        .strikethrough(removing)
                                }
                                .padding(.horizontal, AppMetrics.pillHorizontal)
                                .padding(.vertical, AppMetrics.pillVertical + 1)
                                .background(removing ? Color.red.opacity(0.1) : tint.opacity(0.12),
                                            in: RoundedRectangle(cornerRadius: AppEditorMetrics.chipRadius))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            // Mixed tags (SOME papers) — info only
            if !mixedTags.isEmpty {
                tagSubsection(label: "In some papers") {
                    FlowLayout(spacing: AppEditorMetrics.chipSpacing) {
                        ForEach(TagNamespaceSupport.sortTags(Array(mixedTags)), id: \.self) { tag in
                            let tint = AppColors.tagColor(tag)
                            Text(tag)
                                .font(.system(size: AppEditorMetrics.compactTextSize))
                                .foregroundStyle(tint)
                                .padding(.horizontal, AppMetrics.pillHorizontal)
                                .padding(.vertical, AppMetrics.pillVertical + 1)
                                .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: AppEditorMetrics.chipRadius))
                                .overlay(RoundedRectangle(cornerRadius: AppEditorMetrics.chipRadius).stroke(tint.opacity(0.16), lineWidth: 1))
                        }
                    }
                }
            }

            // Tags to add — click to cancel
            if !editState.tagsToAdd.isEmpty {
                tagSubsection(label: "Will add") {
                    FlowLayout(spacing: AppEditorMetrics.chipSpacing) {
                        ForEach(TagNamespaceSupport.sortTags(Array(editState.tagsToAdd)), id: \.self) { tag in
                            let tint = AppColors.tagColor(tag)
                            Button { editState.tagsToAdd.remove(tag) } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: AppEditorMetrics.miniIconSize))
                                        .foregroundStyle(tint)
                                    Text(tag)
                                        .font(.system(size: AppEditorMetrics.compactTextSize))
                                        .foregroundStyle(tint)
                                }
                                .padding(.horizontal, AppMetrics.pillHorizontal)
                                .padding(.vertical, AppMetrics.pillVertical + 1)
                                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: AppEditorMetrics.chipRadius))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            // Search / add input
            HStack(spacing: AppEditorMetrics.compactSpacing) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: AppEditorMetrics.compactTextSize))
                TextField("Search or add tag…", text: $tagInput)
                    .textFieldStyle(.plain)
                    .font(AppTypography.bodySmall)
                    .focused($isTagInputFocused)
                    .onSubmit { commitTagInput() }
                if !tagInput.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button("Add") { commitTagInput() }
                        .buttonStyle(.plain)
                        .font(.system(size: AppEditorMetrics.compactTextSize, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, AppMetrics.pillHorizontal)
            .padding(.vertical, AppMetrics.pillVertical + 3)
            .appInsetInputSurface(
                fill: Color.primary.opacity(0.05),
                cornerRadius: AppEditorMetrics.inputCornerRadius
            )

            if !namespaceChips.isEmpty {
                tagSubsection(label: "Namespaces") {
                    FlowLayout(spacing: AppEditorMetrics.chipSpacing) {
                        ForEach(namespaceChips, id: \.self) { chip in
                            Button {
                                tagInput = TagNamespaceSupport.applyingNamespaceChip(chip, to: tagInput)
                                isTagInputFocused = true
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

            // Available tags (scrollable)
            let avail = availableTags(matching: tagInput)
            if !avail.isEmpty {
                tagSubsection(label: "Available") {
                    ScrollView(.vertical, showsIndicators: false) {
                        FlowLayout(spacing: AppEditorMetrics.chipSpacing) {
                            ForEach(avail, id: \.self) { tag in
                                Button {
                                    editState.tagsToAdd.insert(tag)
                                    tagInput = ""
                                    isTagInputFocused = true
                                } label: {
                                    let tint = AppColors.tagColor(tag)
                                    HStack(spacing: 3) {
                                        Image(systemName: "plus")
                                            .font(.system(size: AppEditorMetrics.miniIconSize))
                                        Text(tag)
                                            .font(.system(size: AppEditorMetrics.compactTextSize))
                                    }
                                    .foregroundStyle(tint)
                                    .padding(.horizontal, AppMetrics.pillHorizontal - 1)
                                    .padding(.vertical, AppMetrics.pillVertical)
                                    .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: AppEditorMetrics.chipRadius))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: AppEditorMetrics.availableHeight)
                }
            }
        }
    }

    private func tagSubsection<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AppMetrics.inlineRowVertical) {
            Text(label)
                .font(.system(size: AppEditorMetrics.compactLabelSize))
                .foregroundStyle(.tertiary)
            content()
        }
    }

    private func commitTagInput() {
        let trimmed = tagInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        editState.tagsToAdd.insert(trimmed)
        tagInput = ""
        isTagInputFocused = true
    }

    // MARK: - Changes Preview

    private var changesPreview: some View {
        VStack(alignment: .leading, spacing: AppEditorMetrics.footnoteSpacing) {
            Text("Pending changes")
                .font(AppTypography.labelStrong)
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: max(3, AppMetrics.badgeVertical + 2)) {
                if let s = editState.status {
                    changeRow(icon: AppStatusStyle.icon(for: s), label: "Status → \(s.label)",
                              color: AppStatusStyle.tint(for: s))
                }
                if editState.rating == 0 {
                    changeRow(icon: "star.slash", label: "Rating cleared", color: .orange)
                } else if editState.rating > 0 {
                    changeRow(icon: "star.fill",
                              label: "Rating → \(String(repeating: "★", count: editState.rating))",
                              color: .orange)
                }
                if !editState.tagsToAdd.isEmpty {
                    changeRow(icon: "plus.circle.fill",
                              label: "Add: \(editState.tagsToAdd.sorted().joined(separator: ", "))",
                              color: .green)
                }
                if !editState.tagsToRemove.isEmpty {
                    changeRow(icon: "minus.circle.fill",
                              label: "Remove: \(editState.tagsToRemove.sorted().joined(separator: ", "))",
                              color: .red)
                }
            }
        }
        .padding(.horizontal, AppEditorMetrics.sectionHorizontalPadding)
        .padding(.vertical, AppMetrics.cardPadding - 2)
        .background(Color.primary.opacity(0.02))
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private func changeRow(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: AppEditorMetrics.compactSpacing) {
            Image(systemName: icon)
                .font(.system(size: AppEditorMetrics.compactLabelSize))
                .foregroundStyle(color)
                .frame(width: AppEditorMetrics.rowIconWidth)
            Text(label)
                .font(.system(size: AppEditorMetrics.compactTextSize))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }

}

private struct BatchEditStarRating: View {
    @Binding var rating: Int
    private var starSize: CGFloat { 12 * AppStyleConfig.fontScale }
    private var starFrameWidth: CGFloat { max(14, 14 * AppStyleConfig.spacingScale) }

    var body: some View {
        HStack(spacing: max(4, AppMetrics.badgeVertical + 3)) {
            ForEach(1...5, id: \.self) { star in
                Button {
                    rating = (rating == star) ? 0 : star
                } label: {
                    Text("★")
                        .font(.system(size: starSize, weight: .semibold))
                        .foregroundStyle(AppColors.star)
                        .opacity(star <= max(rating, 0) ? 1 : 0.22)
                        .frame(width: starFrameWidth)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - FlowLayout (wrapping HStack)

struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowH: CGFloat = 0
        for sv in subviews {
            let size = sv.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                y += rowH + spacing
                x = 0
                rowH = 0
            }
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
        return CGSize(width: width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowH: CGFloat = 0
        for sv in subviews {
            let size = sv.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                y += rowH + spacing
                x = bounds.minX
                rowH = 0
            }
            sv.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
    }
}
