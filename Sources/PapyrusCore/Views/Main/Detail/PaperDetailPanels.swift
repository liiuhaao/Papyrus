import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct PaperNotesPanel: View {
    @ObservedObject var paper: Paper
    @AppStorage("detail.notesCollapsed") private var notesCollapsed = false

    private var notesMinHeight: CGFloat { max(124, 140 * AppStyleConfig.spacingScale) }
    private var notesDefaultHeight: CGFloat { max(220, 260 * AppStyleConfig.spacingScale) }
    private var notesCollapsedHeight: CGFloat { max(44, 50 * AppStyleConfig.spacingScale) }
    private var headerHorizontalPadding: CGFloat { 10 * AppStyleConfig.spacingScale }
    private var headerHeight: CGFloat { max(38, 40 * AppStyleConfig.spacingScale) }
    private var editorPadding: CGFloat { max(10, 10 * AppStyleConfig.spacingScale) }
    private var notesContentPadding: CGFloat { max(14, 14 * AppStyleConfig.spacingScale) }
    private var emptyStateIconSize: CGFloat { 24 * AppStyleConfig.fontScale }
    private var emptyStateSpacing: CGFloat { max(10, 10 * AppStyleConfig.spacingScale) }
    private var doneButtonHorizontalPadding: CGFloat { max(8, 8 * AppStyleConfig.spacingScale) }
    private var doneButtonVerticalPadding: CGFloat { max(4, 4 * AppStyleConfig.spacingScale) }
    private var doneButtonCornerRadius: CGFloat { max(5, 5 * AppStyleConfig.spacingScale) }
    private var openButtonSpacing: CGFloat { max(5, 5 * AppStyleConfig.spacingScale) }

    @State private var notesDraft = ""
    @State private var isEditingNotes = false
    @State private var saveTimer: Timer? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { notesCollapsed.toggle() }
                } label: {
                    Image(systemName: notesCollapsed ? "chevron.up" : "chevron.down")
                        .font(AppTypography.labelStrong)
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Text("Notes")
                    .font(AppTypography.labelStrong)
                    .foregroundStyle(.secondary)
                    .kerning(0.5)
                    .textCase(.uppercase)

                Spacer()

                if notesCollapsed {
                    EmptyView()
                } else if isEditingNotes {
                    Button("Done") { isEditingNotes = false }
                        .buttonStyle(.plain)
                        .font(AppTypography.labelMedium)
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, doneButtonHorizontalPadding)
                        .padding(.vertical, doneButtonVerticalPadding)
                        .background(Color.accentColor.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: doneButtonCornerRadius))
                } else {
                    HStack(spacing: 6) {
                        Button(action: openNotesInConfiguredApp) {
                            HStack(spacing: openButtonSpacing) {
                                Image(systemName: "arrow.up.right.square")
                                Text("Open in App")
                            }
                            .font(AppTypography.labelMedium)
                            .foregroundStyle(canOpenNotesInConfiguredApp ? .secondary : .tertiary)
                            .padding(.horizontal, doneButtonHorizontalPadding)
                            .padding(.vertical, doneButtonVerticalPadding)
                            .background(Color.primary.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: doneButtonCornerRadius))
                        }
                        .buttonStyle(.plain)
                        .disabled(!canOpenNotesInConfiguredApp)

                        Button(action: enterEdit) {
                            HStack(spacing: openButtonSpacing) {
                                Image(systemName: "square.and.pencil")
                                Text("Edit")
                            }
                            .font(AppTypography.labelMedium)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, doneButtonHorizontalPadding)
                            .padding(.vertical, doneButtonVerticalPadding)
                            .background(Color.primary.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: doneButtonCornerRadius))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, headerHorizontalPadding)
            .frame(height: headerHeight)

            if !notesCollapsed {
                Divider()

                if isEditingNotes {
                    TextEditor(text: $notesDraft)
                        .font(AppTypography.monoSmall)
                        .scrollContentBackground(.hidden)
                        .padding(editorPadding)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onKeyPress(.escape) {
                        isEditingNotes = false
                        return .handled
                    }
                } else if let notes = paper.notes, !notes.isEmpty {
                    ScrollView {
                        MarkdownRenderer(text: notes)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(notesContentPadding)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                } else {
                    VStack(spacing: emptyStateSpacing) {
                        Image(systemName: "note.text")
                            .font(.system(size: emptyStateIconSize))
                            .foregroundStyle(.quaternary)
                        Text("Your notes on this paper")
                            .font(AppTypography.bodySmall).italic()
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { enterEdit() }
                }
            }
        }
        .background(Color.primary.opacity(0.03))
        .animation(.easeInOut(duration: 0.18), value: notesCollapsed)
        .frame(
            minHeight: notesCollapsed ? notesCollapsedHeight : notesMinHeight,
            idealHeight: notesCollapsed ? notesCollapsedHeight : notesDefaultHeight,
            maxHeight: notesCollapsed ? notesCollapsedHeight : .infinity,
            alignment: .top
        )
        .onAppear {
            reloadNotesFromDiskIfNeeded()
        }
        .onDisappear {
            saveTimer?.invalidate()
            saveTimer = nil
        }
        .onChange(of: notesDraft) { _, newValue in
            saveTimer?.invalidate()
            saveTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { _ in
                persistNotes(newValue)
            }
        }
        .onChange(of: paper.objectID) { _, _ in
            saveTimer?.invalidate()
            isEditingNotes = false
            reloadNotesFromDiskIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            guard !isEditingNotes else { return }
            reloadNotesFromDiskIfNeeded()
        }
    }

    private func enterEdit() {
        reloadNotesFromDiskIfNeeded()
        isEditingNotes = true
    }

    private var canOpenNotesInConfiguredApp: Bool {
        switch AppConfig.shared.notesOpenMode {
        case .defaultApp:
            return true
        case .customApp:
            let path = AppConfig.shared.notesOpenAppPath.trimmingCharacters(in: .whitespacesAndNewlines)
            return !path.isEmpty && FileManager.default.fileExists(atPath: path)
        }
    }

    private func persistNotes(_ rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        paper.notes = trimmed.isEmpty ? nil : trimmed
        paper.dateModified = Date()

        do {
            _ = try PaperFileManager.shared.saveNotes(trimmed, for: paper)
        } catch {
            // Preserve current in-app notes even if filesystem sync fails.
        }

        try? paper.managedObjectContext?.save()
    }

    private func reloadNotesFromDiskIfNeeded() {
        let notesURL = PaperFileManager.shared.notesURL(for: paper)
        if FileManager.default.fileExists(atPath: notesURL.path),
           let fileNotes = PaperFileManager.shared.loadNotes(for: paper) {
            let trimmed = fileNotes.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = trimmed.isEmpty ? nil : trimmed
            if paper.notes != normalized {
                paper.notes = normalized
                try? paper.managedObjectContext?.save()
            }
            notesDraft = fileNotes
            return
        }

        notesDraft = paper.notes ?? ""
    }

    private func ensureNotesFileForExternalEditing() -> URL? {
        let notesURL = PaperFileManager.shared.notesURL(for: paper)
        let directory = notesURL.deletingLastPathComponent()

        do {
            if !FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }

            let content = isEditingNotes ? notesDraft : (paper.notes ?? "")
            if !FileManager.default.fileExists(atPath: notesURL.path) || PaperFileManager.shared.loadNotes(for: paper) != content {
                try content.write(to: notesURL, atomically: true, encoding: .utf8)
            }

            try? paper.managedObjectContext?.save()
            return notesURL
        } catch {
            return nil
        }
    }

    private func openNotesInConfiguredApp() {
        guard let notesURL = ensureNotesFileForExternalEditing() else { return }

        switch AppConfig.shared.notesOpenMode {
        case .defaultApp:
            NSWorkspace.shared.open(notesURL)
        case .customApp:
            let path = AppConfig.shared.notesOpenAppPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else { return }
            let appURL = URL(fileURLWithPath: path)
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.open([notesURL], withApplicationAt: appURL, configuration: configuration) { _, _ in }
        }
    }
}
