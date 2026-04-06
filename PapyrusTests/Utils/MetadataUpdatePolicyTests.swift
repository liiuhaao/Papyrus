import CoreData
import Testing
@testable import PapyrusCore

struct MetadataUpdatePolicyTests {
    @MainActor
    @Test
    func applyRespectsManualFieldsButUpdatesDerivedFields() async throws {
        let context = TestSupport.makeInMemoryContext()
        let paper = TestSupport.makePaper(in: context, title: "Initial")
        paper.title = "Manual Title"
        paper.titleManual = true
        paper.authors = "Manual Author"
        paper.authorsManual = true
        paper.venue = "Initial Venue"
        paper.venueManual = false
        paper.year = 2022
        paper.yearManual = true
        paper.doiManual = false
        paper.arxivManual = false
        paper.publicationTypeManual = false

        let metadata = PaperMetadata(
            title: "Fetched Title",
            authors: "Fetched Author",
            venue: "ICML",
            venueAcronym: nil,
            year: 2024,
            doi: "10.1000/example",
            arxivId: "2401.12345",
            abstract: "Fetched abstract",
            publicationType: nil,
            citationCount: 42
        )

        MetadataUpdatePolicy.apply(metadata, to: paper)

        #expect(paper.title == "Manual Title")
        #expect(paper.authors == "Manual Author")
        #expect(paper.venue == "ICML")
        #expect(paper.year == 2022)
        #expect(paper.doi == "10.1000/example")
        #expect(paper.arxivId == "2401.12345")
        #expect(paper.abstract == "Fetched abstract")
        #expect(paper.publicationType == "conference")
        #expect(paper.citationCount == 42)
        #expect(context.hasChanges == false)
    }

    @MainActor
    @Test
    func applyPreservesManualIdentifiersWhileUpdatingResolvedValues() async {
        let context = TestSupport.makeInMemoryContext()
        let paper = TestSupport.makePaper(in: context, title: "Initial")
        paper.doi = "10.1000/existing"
        paper.arxivId = "2301.00001"
        paper.doiManual = true
        paper.arxivManual = true

        let metadata = PaperMetadata(
            doi: "10.1000/new",
            arxivId: "2501.99999",
            citationCount: 7
        )

        MetadataUpdatePolicy.apply(metadata, to: paper)

        #expect(paper.doi == "10.1000/existing")
        #expect(paper.arxivId == "2301.00001")
        #expect(paper.resolvedDOI == "10.1000/new")
        #expect(paper.resolvedArxivId == "2501.99999")
        #expect(paper.citationCount == 7)
    }
}
