import SwiftUI

struct InspectorHostView: View {
    @ObservedObject var viewModel: PaperListViewModel
    @ObservedObject var taskState: LibraryTaskStateModel
    @ObservedObject var detailModel: LibraryDetailModel
    let primaryPaper: Paper?
    let selectedPapers: [Paper]
    @Binding var showBatchEdit: Bool
    let onBatchEdit: () -> Void
    let onRefreshSelection: () -> Void
    let onDeleteSelection: () -> Void

    var body: some View {
        Group {
            if selectedPapers.count >= 2 {
                multiSelectionContent
            } else if let paper = resolvedPrimaryPaper {
                singleSelectionContent(for: paper)
            } else {
                EmptyStateView()
            }
        }
        .inspectorColumnWidth(min: 340, ideal: 340, max: 500)
    }

    private var resolvedPrimaryPaper: Paper? {
        primaryPaper ?? selectedPapers.first
    }

    @ViewBuilder
    private func singleSelectionContent(for paper: Paper) -> some View {
        if detailModel.showEditMetadata {
            PaperEditorView(
                paper: paper,
                suggestions: allKnownTags,
                onSaved: { paper in
                    viewModel.findOrCreateVenue(for: paper)
                    viewModel.fetchPapers()
                },
                onClose: {
                    detailModel.showEditMetadata = false
                }
            )
        } else {
            PaperDetailView(
                paper: paper,
                viewModel: viewModel,
                taskState: taskState,
                detailModel: detailModel
            )
        }
    }

    @ViewBuilder
    private var multiSelectionContent: some View {
        if showBatchEdit, selectedPapers.count >= 2 {
            BatchEditView(
                papers: selectedPapers,
                allTags: viewModel.tagCounts.map(\.tag),
                onApply: { state in
                    showBatchEdit = false
                    viewModel.applyBatchEdit(
                        to: selectedPapers,
                        status: state.status,
                        rating: state.rating,
                        tagsToAdd: state.tagsToAdd,
                        tagsToRemove: state.tagsToRemove,
                        publicationType: nil
                    )
                },
                onCancel: { showBatchEdit = false }
            )
        } else {
            MultiSelectionDetailView(
                papers: selectedPapers,
                onBatchEdit: onBatchEdit,
                onRefreshSelection: onRefreshSelection,
                onDeleteSelection: onDeleteSelection
            )
        }
    }

    private var allKnownTags: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for paper in viewModel.papers {
            for tag in paper.tagsList {
                let key = tag.lowercased()
                if !seen.contains(key) {
                    seen.insert(key)
                    ordered.append(tag)
                }
            }
        }
        return TagNamespaceSupport.sortTags(ordered)
    }
}
