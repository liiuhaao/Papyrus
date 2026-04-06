import Foundation
import Testing
@testable import PapyrusCore

struct MetadataParsersTests {
    @Test
    func parseArxivXMLExtractsCoreFields() throws {
        let xml = """
        <feed>
          <entry>
            <title>
              Attention Is All You Need
            </title>
            <summary>Sequence transduction with attention.</summary>
            <name>Ashish Vaswani</name>
            <name>Noam Shazeer</name>
            <published>2017-06-12T17:57:33Z</published>
          </entry>
        </feed>
        """

        let metadata = try MetadataParsers.parseArxivXML(xml)

        #expect(metadata.title == "Attention Is All You Need")
        #expect(metadata.abstract == "Sequence transduction with attention.")
        #expect(metadata.authors == "Ashish Vaswani, Noam Shazeer")
        #expect(metadata.year == 2017)
        #expect(metadata.publicationType == "preprint")
    }

    @Test
    func parseCrossRefJSONUsesShortContainerTitleAndInfersConferenceType() {
        let json: [String: Any] = [
            "title": ["Scaling Laws for Agents"],
            "author": [
                ["given": "Ada", "family": "Lovelace"],
                ["given": "Alan", "family": "Turing"]
            ],
            "short-container-title": ["NeurIPS"],
            "published-online": ["date-parts": [[2024, 12, 1]]]
        ]

        let metadata = MetadataParsers.parseCrossRefJSON(json)

        #expect(metadata.title == "Scaling Laws for Agents")
        #expect(metadata.authors == "Ada Lovelace, Alan Turing")
        #expect(metadata.venue == "NeurIPS")
        #expect(metadata.year == 2024)
        #expect(metadata.publicationType == "conference")
    }

    @Test
    func parseOpenReviewSearchResultBuildsICLRVenueAndYear() throws {
        let note: [String: Any] = [
            "domain": "openreview.net/group?id=ICLR.cc/2025/Conference",
            "content": [
                "title": ["value": "A Better Retrieval Model"],
                "abstract": ["value": "Abstract text"],
                "authors": ["value": ["Author One", "Author Two"]]
            ]
        ]

        let metadata = try MetadataParsers.parseOpenReviewSearchResult(note)

        #expect(metadata.title == "A Better Retrieval Model")
        #expect(metadata.abstract == "Abstract text")
        #expect(metadata.authors == "Author One, Author Two")
        #expect(metadata.venue == "ICLR 2025")
        #expect(metadata.year == 2025)
    }

}
