import Testing
@testable import PapyrusCore

struct MetadataNormalizationTests {
    @Test
    func normalizeTitleStripsLeadingDatePrefix() {
        let normalized = MetadataNormalization.normalizeTitle("11 Feb 2025 ToolOrchestra: Elevating Intelligence via Efficient Model and Tool Orchestration")
        #expect(normalized == "ToolOrchestra: Elevating Intelligence via Efficient Model and Tool Orchestration")
    }

    @Test
    func normalizeTitleKeepsYearStyledTitle() {
        let normalized = MetadataNormalization.normalizeTitle("2025: Scaling Agentic Workflows")
        #expect(normalized == "2025: Scaling Agentic Workflows")
    }
}
