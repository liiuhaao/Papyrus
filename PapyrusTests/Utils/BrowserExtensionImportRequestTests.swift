import Foundation
import Testing
@testable import PapyrusCore

struct BrowserExtensionImportRequestTests {
    @Test
    func parseRequiresLocalPDFPathAndPreservesWebMetadata() {
        let url = URL(string: "papyrus://import?title=Test%20Paper&authors=Alice%2C%20Bob&doi=10.1145%2F1234567.1234568&pdfPath=%2Ftmp%2Fpaper.pdf&pdfURL=https%3A%2F%2Fexample.com%2Fpaper.pdf&year=2024&venue=NeurIPS&sourceURL=https%3A%2F%2Fexample.com%2Fabs")!
        let request = BrowserExtensionImportRequest.parse(from: url)

        #expect(request?.pdfFileURL?.path == "/tmp/paper.pdf")
        #expect(request?.webpageMetadata?.title == "Test Paper")
        #expect(request?.webpageMetadata?.authors == "Alice, Bob")
        #expect(request?.webpageMetadata?.venue == "NeurIPS")
        #expect(request?.webpageMetadata?.year == 2024)
        #expect(request?.webpageMetadata?.sourceURL?.absoluteString == "https://example.com/abs")
    }

    @Test
    func parsePrefersLocalPDFPathWhenBrowserTransfersPDFFile() {
        let url = URL(string: "papyrus://import?title=Local%20PDF&doi=10.1145%2F1234567.1234568&pdfPath=%2Ftmp%2Fpaper.pdf&pdfURL=https%3A%2F%2Fexample.com%2Fpaper.pdf")!
        let request = BrowserExtensionImportRequest.parse(from: url)

        #expect(request?.pdfFileURL?.path == "/tmp/paper.pdf")
        #expect(request?.webpageMetadata?.title == "Local PDF")
        #expect(request?.webpageMetadata?.doi == "10.1145/1234567.1234568")
    }

    @Test
    func parseKeepsSourceContextWhenPDFPathExists() {
        let url = URL(string: "papyrus://import?title=Scholar%20Result&pdfPath=%2Ftmp%2Fscholar.pdf&pdfURL=https%3A%2F%2Fexample.com%2Fpaper.pdf&sourceURL=https%3A%2F%2Fscholar.google.com%2Fscholar%3Fq%3Dtest")!
        let request = BrowserExtensionImportRequest.parse(from: url)

        #expect(request?.pdfFileURL?.path == "/tmp/scholar.pdf")
        #expect(request?.webpageMetadata?.title == "Scholar Result")
        #expect(request?.webpageMetadata?.sourceURL?.absoluteString == "https://scholar.google.com/scholar?q=test")
        #expect(request?.webpageMetadata?.pdfURL?.absoluteString == "https://example.com/paper.pdf")
    }

    @Test
    func parseRejectsPapernestImportURLWithoutPDFPath() {
        let url = URL(string: "papyrus://import?title=No%20PDF&sourceURL=https%3A%2F%2Fexample.com")!
        let request = BrowserExtensionImportRequest.parse(from: url)
        #expect(request == nil)
    }
}
