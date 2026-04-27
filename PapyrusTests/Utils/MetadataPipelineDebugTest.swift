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

    @Test
    func runConfidenceTokensPipeline() async throws {
        let service = MetadataService.shared
        let seed = MetadataSeed(
            title: "Learning to Route LLMs with Confidence Tokens",
            titleCandidates: [],
            authors: "Yu-Neng Chuang, Prathusha Kameswara Sarma, Parikshit Gopalan, John Boccio, Sara Bolouki, Xia Hu, Helen Zhou",
            doi: nil,
            arxivId: "2410.13284",
            abstract: nil,
            venue: nil,
            year: 2025,
            originalFilename: "confidence-tokens.pdf"
        )

        let pipeline = service.makePipeline(for: .general, seed: seed)
        let resolution = await pipeline.resolve(seed: seed)

        print("=== Confidence Tokens Pipeline Result ===")
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
    func runMockWorldsPipeline() async throws {
        let service = MetadataService.shared
        let seed = MetadataSeed(
            title: "Mock Worlds, Real Skills: Building Small Agentic Language Models with Synthetic Tasks, Simulated Environments, and Rubric-Based Rewards",
            titleCandidates: [],
            authors: "Yuan-Jay Lü, Chengyu Wang, Lei Shen, Jun Huang, Tong Xu",
            doi: nil,
            arxivId: "2601.22511",
            abstract: nil,
            venue: nil,
            year: 2026,
            originalFilename: "mock-worlds.pdf"
        )

        let pipelineCS = service.makePipeline(for: .cs, seed: seed)
        let resolutionCS = await pipelineCS.resolve(seed: seed)
        print("=== Mock Worlds CS Preset ===")
        print("Trace: \(resolutionCS.trace)")
        print("Metadata present: \(resolutionCS.metadata != nil)")
        if let metadata = resolutionCS.metadata {
            print("Title: \(metadata.title ?? "nil")")
            print("Venue: \(metadata.venue ?? "nil")")
        }
        print("Candidates (\(resolutionCS.candidates.count)):")
        for (index, c) in resolutionCS.candidates.enumerated() {
            print("  [\(index)] source=\(c.source) matchKind=\(c.matchKind) venue=\(c.metadata.venue ?? "nil")")
        }

        let pipelineGeneral = service.makePipeline(for: .general, seed: seed)
        let resolutionGeneral = await pipelineGeneral.resolve(seed: seed)
        print("=== Mock Worlds General Preset ===")
        print("Trace: \(resolutionGeneral.trace)")
        print("Metadata present: \(resolutionGeneral.metadata != nil)")
        if let metadata = resolutionGeneral.metadata {
            print("Title: \(metadata.title ?? "nil")")
            print("Venue: \(metadata.venue ?? "nil")")
        }
        print("Candidates (\(resolutionGeneral.candidates.count)):")
        for (index, c) in resolutionGeneral.candidates.enumerated() {
            print("  [\(index)] source=\(c.source) matchKind=\(c.matchKind) venue=\(c.metadata.venue ?? "nil")")
        }
    }


}
