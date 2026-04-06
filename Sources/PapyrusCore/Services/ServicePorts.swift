import Foundation

protocol MetadataProviding: AnyObject {
    @MainActor
    func enrichMetadata(paper: Paper) async -> Bool
    func fetchPDFURL(arxivId: String?, doi: String?) async throws -> URL
    func fetchReferences(for paper: Paper) async throws -> [PaperReference]
    func fetchCitations(for paper: Paper) async throws -> [PaperReference]
}

protocol RankProviding: AnyObject {
    func cached(venue: String) -> JournalRankInfo?
    func fetchIfNeeded(venue: String) async
    func fetchForce(venue: String) async
}

protocol VenueAbbreviationProviding: AnyObject {
    func cached(venue: String) -> String?
    func fetchFromDBLPIfNeeded(venue: String) async
}

protocol FileStorageProviding: AnyObject {
    var libraryURL: URL { get }
    var pdfDirectoryURL: URL { get }
    var attachmentsDirectoryURL: URL { get }
    func importPDF(from sourceURL: URL, paper: Paper) throws -> URL
    func renameFile(for paper: Paper) throws -> URL?
    func notesURL(for paper: Paper) -> URL
    func loadNotes(for paper: Paper) -> String?
    @discardableResult
    func saveNotes(_ content: String?, for paper: Paper) throws -> URL?
    func removeAttachments(for paper: Paper)
}
