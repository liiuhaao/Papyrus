import SwiftUI

struct MetadataSourcePickerView: View {
    let paper: Paper
    let selectedCandidateKey: String?
    let onSelect: (MetadataCandidate) -> Void
    let onCancel: () -> Void

    private var candidates: [MetadataCandidate] {
        guard let json = paper.fetchCandidatesJSON,
              let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([MetadataCandidate].self, from: data)) ?? []
    }



    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AppEditorHeader(
                title: "Choose Source",
                subtitle: "Select a fetched source to fill metadata, or choose Manual to keep current values.",
                confirmTitle: "Done",
                onCancel: onCancel,
                onConfirm: onCancel
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(candidates.indices, id: \.self) { index in
                        let candidate = candidates[index]
                        candidateRow(candidate)
                        if index < candidates.count - 1 {
                            Divider().padding(.leading, 12)
                        }
                    }

                }
                .padding(.vertical, 4)
            }
        }
        .frame(minWidth: 420, idealWidth: 480, maxWidth: 520, minHeight: 240, idealHeight: 360, maxHeight: 520)
    }

    private func candidateRow(_ candidate: MetadataCandidate) -> some View {
        Button {
            onSelect(candidate)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(candidate.source)
                            .font(AppTypography.bodySmallMedium)
                            .foregroundStyle(.primary)

                        Text(matchLabel(candidate.matchKind))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))

                        Text(String(format: "%.2f", candidate.sourceConfidence))
                            .font(AppTypography.labelMedium)
                            .foregroundStyle(.tertiary)

                        Spacer(minLength: 0)

                        if selectedCandidateKey == candidate.uniqueKey {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                    }

                    if let title = candidate.metadata.title, !title.isEmpty {
                        Text(title)
                            .font(AppTypography.label)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    HStack(spacing: 8) {
                        if let authors = candidate.metadata.authors, !authors.isEmpty {
                            Text(authors)
                                .font(AppTypography.labelMedium)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                        if let venue = candidate.metadata.venue, !venue.isEmpty {
                            Text(venue)
                                .font(AppTypography.labelMedium)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                        if candidate.metadata.year > 0 {
                            Text(String(candidate.metadata.year))
                                .font(AppTypography.labelMedium)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .background(selectedCandidateKey == candidate.uniqueKey ? Color.accentColor.opacity(0.06) : Color.clear)
        }
        .buttonStyle(.plain)
    }

    private func matchLabel(_ kind: MetadataCandidate.MatchKind) -> String {
        switch kind {
        case .doi: return "DOI"
        case .arxiv: return "arXiv"
        case .exactTitle: return "Exact"
        case .fuzzyTitle: return "Fuzzy"
        }
    }
}
