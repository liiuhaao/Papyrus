import Foundation
import Testing
@testable import PapyrusCore

struct MetadataPipelineDebugTest {

    @Test
    func runTheAvengersPipeline() async throws {
        let service = MetadataService.shared
        let seed = MetadataSeed(
            title: "The Avengers: A Simple Recipe for Uniting Smaller Language Models to Challenge Proprietary Giants",
            titleCandidates: [],
            authors: "Yiqun Zhang, Hao Li, Chenxu Wang, Linyao Chen, Qiaosheng Zhang, Peng Ye, Shi Feng, Daling Wang, Zhen Wang, Xinrun Wang, Jia Xu, Lei Bai, Wanli Ouyang, Shuyue Hu",
            doi: nil,
            arxivId: "2505.19797",
            abstract: nil,
            venue: nil,
            year: 2025,
            originalFilename: "avengers.pdf"
        )

        let pipeline = service.makePipeline(for: .cs, seed: seed)
        let resolution = await pipeline.resolve(seed: seed)

        print("=== The Avengers Pipeline Result ===")
        print("Trace: \(resolution.trace)")
        print("Metadata present: \(resolution.metadata != nil)")
        if let metadata = resolution.metadata {
            print("Title: \(metadata.title ?? "nil")")
            print("Venue: \(metadata.venue ?? "nil")")
            print("DOI: \(metadata.doi ?? "nil")")
            print("ArxivId: \(metadata.arxivId ?? "nil")")
            print("Year: \(metadata.year)")
            print("PublicationType: \(metadata.publicationType ?? "nil")")
        }
        print("Candidates (\(resolution.candidates.count)):")
        for (index, c) in resolution.candidates.enumerated() {
            print("  [\(index)] source=\(c.source) matchKind=\(c.matchKind) venue=\(c.metadata.venue ?? "nil") doi=\(c.metadata.doi ?? "nil")")
        }
    }

    @Test
    func runRouterR1Pipeline() async throws {
        let service = MetadataService.shared
        let seed = MetadataSeed(
            title: "Router-R1: Teaching LLMs Multi-Round Routing and Aggregation via Reinforcement Learning",
            titleCandidates: [],
            authors: "Haozhen Zhang, Tao Feng, Jiaxuan You",
            doi: nil,
            arxivId: "2506.09033",
            abstract: nil,
            venue: nil,
            year: 2025,
            originalFilename: "router-r1.pdf"
        )

        let pipeline = service.makePipeline(for: .cs, seed: seed)
        let resolution = await pipeline.resolve(seed: seed)

        print("=== Router-R1 Pipeline Result ===")
        print("Trace: \(resolution.trace)")
        print("Metadata present: \(resolution.metadata != nil)")
        if let metadata = resolution.metadata {
            print("Title: \(metadata.title ?? "nil")")
            print("Venue: \(metadata.venue ?? "nil")")
            print("DOI: \(metadata.doi ?? "nil")")
            print("ArxivId: \(metadata.arxivId ?? "nil")")
            print("Year: \(metadata.year)")
            print("PublicationType: \(metadata.publicationType ?? "nil")")
        }
        print("Candidates (\(resolution.candidates.count)):")
        for (index, c) in resolution.candidates.enumerated() {
            print("  [\(index)] source=\(c.source) matchKind=\(c.matchKind) venue=\(c.metadata.venue ?? "nil") doi=\(c.metadata.doi ?? "nil")")
        }
    }
}
