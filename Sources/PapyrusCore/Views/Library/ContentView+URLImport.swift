import Foundation

extension ContentView {
    func handleIncomingURLImport(_ url: URL) {
        guard url.scheme?.lowercased() == "papyrus" else { return }
        // Non-import URLs (e.g. papyrus://open) just wake the app — ignore silently.
        guard url.host?.lowercased() == "import" else { return }

        guard let request = BrowserExtensionImportRequest.parse(from: url) else {
            taskState.errorMessage = "Invalid browser import URL."
            return
        }

        if let pdfFileURL = request.pdfFileURL {
            viewModel.importPDF(
                from: pdfFileURL,
                webpageMetadata: request.webpageMetadata
            )
            return
        }

        taskState.errorMessage = "Browser import requires a PDF file."
    }
}
