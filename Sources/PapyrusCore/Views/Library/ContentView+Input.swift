import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension ContentView {
    var activeViewInputAdapter: any LibraryViewInputAdapter {
        switch appConfig.libraryViewMode {
        case .list:
            return ListViewInputAdapter()
        case .gallery:
            return GalleryViewInputAdapter()
        }
    }

    var commandRouter: CommandRouter {
        CommandRouter.shared
    }

    func setupSingleKeyMonitor() {
        singleKeyMonitor.handleBinding = { binding in
            let normalized = AppShortcutConfig.normalizeBinding(binding)
            for action in AppConfig.allShortcutActions {
                let configured = appConfig.shortcuts[action.rawValue]?.first
                    ?? AppConfig.defaultShortcuts[action.rawValue]?.first
                    ?? ""
                if AppShortcutConfig.normalizeBinding(configured) == normalized {
                    guard let command = AppCommand(inputAction: action) else { return false }
                    let source: CommandSource = normalized.contains("+") ? .eventMonitor : .singleKeyMonitor
                    return executeAppCommand(command, source: source)
                }
            }
            return false
        }
        singleKeyMonitor.start()
    }

        // MARK: - Keyboard Shortcuts

    var globalShortcutLayer: some View {
        GlobalShortcutLayer(configuration: globalShortcutConfiguration)
    }

    var hasBlockingModal: Bool {
        presentationState.hasBlockingModal(errorMessagePresent: taskState.errorMessage != nil)
            || detailModel.showBibTeX
    }

    var libraryInputContext: LibraryInputContext {
        LibraryInputContext(
            activeViewMode: appConfig.libraryViewMode,
            supportsMultiSelection: activeViewInputAdapter.supportsMultiSelection,
            hasBlockingModal: hasBlockingModal,
            isTextInputFocused: currentResponderIsTextInput(),
            isLibraryWindowActive: currentLibraryWindowIsActive(),
            isCommandFocusEligible: shouldHandleGlobalShortcut(),
            primaryPaperID: currentPrimaryPaper?.objectID,
            selectedPaperIDs: Set(currentSelectedPapers.map(\.objectID))
        )
    }

    func handleTextSelectionCopy() -> Bool {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return false }
        guard let textView = window.firstResponder as? NSTextView else { return false }
        if textView.selectedRange.length <= 0 { return false }
        NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
        return true
    }

    func currentLibraryWindowIsActive() -> Bool {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return false }
        return window === NSApp.keyWindow || window === NSApp.mainWindow
    }

    func currentResponderIsTextInput() -> Bool {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow,
              let responder = window.firstResponder else { return false }
        return isTextInputResponder(responder)
    }

    func shouldHandleGlobalShortcut() -> Bool {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return false }
        guard let responder = window.firstResponder else { return false }
        if isTextInputResponder(responder) {
            return false
        }
        if showingFeed {
            return window === NSApp.keyWindow || window === NSApp.mainWindow
        }
        return activeViewInputAdapter.canAcceptLibraryCommands(
            window: window,
            responder: responder,
            listTableView: listTableView
        )
    }

    private func isTextInputResponder(_ responder: NSResponder) -> Bool {
        if let textView = responder as? NSTextView {
            return textView.isEditable || textView.isFieldEditor
        }
        if responder is NSTextField || responder is NSSearchField {
            return true
        }
        guard let view = responder as? NSView else { return false }
        if let textView = view as? NSTextView {
            return textView.isEditable || textView.isFieldEditor
        }
        if view is NSTextField || view is NSSearchField {
            return true
        }
        if let ancestorTextView = view.superview(ofType: NSTextView.self),
           ancestorTextView.isEditable || ancestorTextView.isFieldEditor {
            return true
        }
        return view.superview(ofType: NSTextField.self) != nil
            || view.superview(ofType: NSSearchField.self) != nil
    }

    @MainActor
    func executeAppCommand(_ command: AppCommand, source: CommandSource) -> Bool {
        let context = CommandContext(
            source: source,
            library: libraryInputContext,
            onTextCopyFallback: { _ = handleTextSelectionCopy() }
        )
        return commandRouter.execute(command, context: context) { command, _ in
            performCommand(command)
        }
    }

    @MainActor
    func performKeyboardAction(_ action: InputAction, source: CommandSource = .inputAction) -> Bool {
        guard let command = AppCommand(inputAction: action) else { return false }
        return executeAppCommand(command, source: source)
    }

    @MainActor
    func performCommand(_ command: AppCommand) {
        // Commands that work in both Library and Feed
        switch command {
        case .moveUp:
            if showingFeed {
                navigateFeedSelection(.up)
            } else {
                navigateSelection(.up)
            }
            return
        case .moveDown:
            if showingFeed {
                navigateFeedSelection(.down)
            } else {
                navigateSelection(.down)
            }
            return
        case .moveLeft:
            if showingFeed {
                navigateFeedSelection(.left)
            } else {
                navigateSelection(.left)
            }
            return
        case .moveRight:
            if showingFeed {
                navigateFeedSelection(.right)
            } else {
                navigateSelection(.right)
            }
            return
        case .moveTop:
            if showingFeed {
                navigateFeedSelection(.top)
            } else {
                navigateSelection(.top)
            }
            return
        case .moveBottom:
            if showingFeed {
                navigateFeedSelection(.bottom)
            } else {
                navigateSelection(.bottom)
            }
            return
        case .pageUp:
            if showingFeed {
                navigateFeedSelection(.pageUp)
            } else {
                navigateSelection(.pageUp)
            }
            return
        case .pageDown:
            if showingFeed {
                navigateFeedSelection(.pageDown)
            } else {
                navigateSelection(.pageDown)
            }
            return
        case .focusSearch:
            isSearchFocused = true
            return
        case .toggleLeftPanel:
            presentationState.toggleSidebarVisibility()
            return
        case .toggleRightPanel:
            if showingFeed || currentPrimaryPaper != nil {
                presentationState.toggleInspectorVisibility()
            }
            return
        default:
            break
        }

        // Feed-specific handling
        if showingFeed {
            switch command {
            case .openPDF:
                openPrimaryFeedItemOnline()
            case .toggleRead:
                toggleReadForSelectedFeedItems()
            case .refreshMetadata:
                refreshFeed()
            case .copyTitle:
                let titles = selectedFeedItems.map(\.title).joined(separator: "\n")
                guard !titles.isEmpty else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(titles, forType: .string)
                presentationState.showToast("Title copied")
            default:
                break
            }
            return
        }

        // Library-only commands
        switch command {
        case .openPDF:
            openPaperForPrimaryAction()
        case .quickLook:
            quickLookForPrimaryAction()
        case .deletePaper:
            beginDeleteSelection()
        case .importPDF:
            presentationState.showingImportDialog = true
        case .refreshMetadata:
            viewModel.refreshMetadata(currentSelectedPapers)
        case .pinPaper:
            togglePinForCurrentSelection()
        case .flagPaper:
            toggleFlagForCurrentSelection()
        case .copyTitle:
            copySelectedTitle()
        case .copyBibTeX:
            copySelectedBibTeX()
        case .rate1:
            applyRating(1)
        case .rate2:
            applyRating(2)
        case .rate3:
            applyRating(3)
        case .rate4:
            applyRating(4)
        case .rate5:
            applyRating(5)
        case .rateClear:
            applyRating(0)
        default:
            break
        }
    }

    var globalShortcutConfiguration: GlobalShortcutConfiguration {
        GlobalShortcutConfiguration(
            openPDFShortcut: appConfig.keyboardShortcut(for: .openPDF),
            quickLookShortcut: appConfig.keyboardShortcut(for: .quickLook),
            deletePaperShortcut: appConfig.keyboardShortcut(for: .deletePaper),
            focusSearchShortcut: appConfig.keyboardShortcut(for: .focusSearch),
            toggleLeftPanelShortcut: appConfig.keyboardShortcut(for: .toggleLeftPanel),
            toggleRightPanelShortcut: appConfig.keyboardShortcut(for: .toggleRightPanel),
            importPDFShortcut: appConfig.keyboardShortcut(for: .importPDF),
            refreshMetadataShortcut: appConfig.keyboardShortcut(for: .refreshMetadata),
            pinPaperShortcut: appConfig.keyboardShortcut(for: .pinPaper),
            flagPaperShortcut: appConfig.keyboardShortcut(for: .flagPaper),
            copyTitleShortcut: appConfig.keyboardShortcut(for: .copyTitle),
            copyBibTeXShortcut: appConfig.keyboardShortcut(for: .copyBibTeX),
            openPDF: { _ = executeAppCommand(.openPDF, source: .globalShortcutLayer) },
            quickLook: { _ = executeAppCommand(.quickLook, source: .globalShortcutLayer) },
            deletePaper: { _ = executeAppCommand(.deletePaper, source: .globalShortcutLayer) },
            focusSearch: { _ = executeAppCommand(.focusSearch, source: .globalShortcutLayer) },
            toggleLeftPanel: { _ = executeAppCommand(.toggleLeftPanel, source: .globalShortcutLayer) },
            toggleRightPanel: { _ = executeAppCommand(.toggleRightPanel, source: .globalShortcutLayer) },
            importPDF: { _ = executeAppCommand(.importPDF, source: .globalShortcutLayer) },
            refreshMetadata: { _ = executeAppCommand(.refreshMetadata, source: .globalShortcutLayer) },
            pinPaper: { _ = executeAppCommand(.pinPaper, source: .globalShortcutLayer) },
            flagPaper: { _ = executeAppCommand(.flagPaper, source: .globalShortcutLayer) },
            copyTitle: { _ = executeAppCommand(.copyTitle, source: .globalShortcutLayer) },
            copyBibTeX: { _ = executeAppCommand(.copyBibTeX, source: .globalShortcutLayer) }
        )
    }

    // MARK: - Drag & Drop

    @ViewBuilder
    var dragOverlay: some View {
        if presentationState.isDragTargeted {
            RoundedRectangle(cornerRadius: 16)
                .glassEffect(in: RoundedRectangle(cornerRadius: 16))
                .overlay(
                    VStack(spacing: 12) {
                        Image(systemName: "arrow.down.doc.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.tint)
                        Text("Drop to import PDF")
                            .font(AppTypography.titleSmall)
                            .foregroundStyle(.tint)
                    }
                )
                .padding(8)
                .allowsHitTesting(false)
        }
    }

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        if LibraryDragSessionState.shared.isInternalDragActive {
            return false
        }

        // Ignore internal drags from Papyrus library rows/cards.
        // NSItemProvider can drop custom types during AppKit -> SwiftUI bridging,
        // so also check the raw drag pasteboard directly.
        let hasInternalProviderType = providers.contains {
            $0.hasItemConformingToTypeIdentifier(PaperDragDrop.internalPaperType)
        }
        let hasInternalPasteboardType = NSPasteboard(name: .drag)
            .types?
            .contains(NSPasteboard.PasteboardType(PaperDragDrop.internalPaperType)) == true
        if hasInternalProviderType || hasInternalPasteboardType {
            return false
        }

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
                provider.loadFileRepresentation(forTypeIdentifier: UTType.pdf.identifier) { tempURL, error in
                    guard let tempURL else { return }
                    let dest = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString + ".pdf")
                    do {
                        try FileManager.default.copyItem(at: tempURL, to: dest)
                        DispatchQueue.main.async { viewModel.importPDF(from: dest) }
                    } catch { print("Copy error: \(error)") }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    var url: URL?
                    if let nsurl = item as? NSURL { url = nsurl as URL }
                    else if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
                    if let url, url.pathExtension.lowercased() == "pdf" {
                        DispatchQueue.main.async { viewModel.importPDF(from: url) }
                    }
                }
            }
        }
        return true
    }

    func handleFileImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls): urls.forEach { viewModel.importPDF(from: $0) }
        case .failure(let error): taskState.errorMessage = error.localizedDescription
        }
    }

    func openPrimaryFeedItemOnline() {
        guard let item = feedSelection.selectedItem(in: visibleFeedItems),
              let rawURL = item.landingURL,
              let url = URL(string: rawURL) else { return }
        NSWorkspace.shared.open(url)
    }

    func toggleReadForSelectedFeedItems() {
        guard !feedSelection.selectedIDs.isEmpty else { return }
        let items = feedSelection.selectedItems(in: visibleFeedItems)
        guard !items.isEmpty else { return }

        let shouldMarkUnread = items.allSatisfy { $0.status == .read }
        Task {
            if shouldMarkUnread {
                await feedViewModel.batchMarkUnread(ids: feedSelection.selectedIDs)
            } else {
                await feedViewModel.batchMarkRead(ids: feedSelection.selectedIDs)
            }
            feedSelection.clearSelection()
        }
    }

    func refreshFeed() {
        Task { await feedViewModel.refresh(papers: viewModel.papers) }
    }
}
