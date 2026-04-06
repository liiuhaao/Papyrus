import Foundation
import Testing
@testable import PapyrusCore

struct CLISupportTests {
    @Test
    func parseImportCommandBuildsWebpageMetadata() throws {
        let command = try CLISupport.parseImportCommand([
            "import",
            "/tmp/sample.pdf",
            "--title", "Graph Agents",
            "--authors", "Alice, Bob",
            "--doi", "10.1000/test",
            "--arxiv-id", "2501.12345",
            "--venue", "ICML",
            "--year", "2025",
            "--abstract", "A paper about agents.",
            "--source-url", "https://example.com/paper",
            "--pdf-url", "https://example.com/paper.pdf"
        ])

        #expect(command.pdfURL.path == "/tmp/sample.pdf")
        #expect(command.webpageMetadata?.title == "Graph Agents")
        #expect(command.webpageMetadata?.authors == "Alice, Bob")
        #expect(command.webpageMetadata?.doi == "10.1000/test")
        #expect(command.webpageMetadata?.arxivId == "2501.12345")
        #expect(command.webpageMetadata?.venue == "ICML")
        #expect(command.webpageMetadata?.year == 2025)
        #expect(command.webpageMetadata?.abstract == "A paper about agents.")
        #expect(command.webpageMetadata?.sourceURL?.absoluteString == "https://example.com/paper")
        #expect(command.webpageMetadata?.pdfURL?.absoluteString == "https://example.com/paper.pdf")
    }

    @Test
    func parseImportCommandRejectsInvalidSourceURL() {
        #expect(throws: CLISupport.CLIError.self) {
            _ = try CLISupport.parseImportCommand([
                "import",
                "/tmp/sample.pdf",
                "--source-url", "notaurl"
            ])
        }
    }

    @Test
    func parseUpdateCommandCapturesPublicationType() throws {
        let id = UUID()

        let command = try CLISupport.parseUpdateCommand([
            "update",
            id.uuidString,
            "--status", "reading",
            "--rating", "4",
            "--publication-type", "journal"
        ])

        #expect(command.id == id)
        #expect(command.readingStatus == .reading)
        #expect(command.rating == 4)
        #expect(command.publicationType == "journal")
    }
}
