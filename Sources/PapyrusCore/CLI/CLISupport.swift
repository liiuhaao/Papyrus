import Foundation

package enum CLISupport {
    private struct CLIStatus: Encodable {
        let ok: Bool
        let action: String
        let paperID: UUID?
    }

    package enum CLIError: LocalizedError {
        case missingValue(String)
        case invalidUUID(String)
        case invalidStatus(String)
        case invalidSortField(String)
        case invalidBoolean(String)
        case invalidInteger(option: String, raw: String)
        case invalidURL(option: String, raw: String)
        case unexpectedArgument(String)

        package var errorDescription: String? {
            switch self {
            case .missingValue(let option):
                return "Missing value for \(option)"
            case .invalidUUID(let raw):
                return "Invalid UUID: \(raw)"
            case .invalidStatus(let raw):
                return "Invalid status: \(raw). Expected unread, reading, or read."
            case .invalidSortField(let raw):
                return "Invalid sort field: \(raw). Expected date-added, year, title, or citations."
            case .invalidBoolean(let raw):
                return "Invalid boolean: \(raw). Expected true or false."
            case .invalidInteger(let option, let raw):
                return "Invalid integer for \(option): \(raw)"
            case .invalidURL(let option, let raw):
                return "Invalid URL for \(option): \(raw)"
            case .unexpectedArgument(let raw):
                return "Unexpected argument: \(raw)"
            }
        }
    }

    @MainActor
    package static func run(arguments: [String]) async throws -> Int32 {
        let args = Array(arguments.dropFirst())
        let command = args.first ?? "help"
        let runtime = AppContainer.shared.makeLibraryRuntime()
        let queries = runtime.queries
        let commands = runtime.commands
        switch command {
        case "help", "--help", "-h":
            printHelp()
            return 0
        case "config":
            try printJSON(queries.runtimeSnapshot())
            return 0
        case "list":
            try printJSON(queries.listPapers(try parseListQuery(args)))
            return 0
        case "get":
            let id = try parsePositionalUUID(args, command: "get")
            try printJSON(commands.getPaper(id: id))
            return 0
        case "update":
            let update = try parseUpdateCommand(args)
            try printJSON(commands.updatePaper(update))
            return 0
        case "import":
            let importCommand = try parseImportCommand(args)
            try printJSON(await commands.importPaper(importCommand))
            return 0
        case "queue-import":
            let importCommand = try parseImportCommand(args, command: "queue-import")
            try printJSON(await commands.queueImportPaper(importCommand))
            return 0
        case "delete":
            let id = try parsePositionalUUID(args, command: "delete")
            try commands.deletePaper(id: id)
            try printJSON(CLIStatus(ok: true, action: "delete", paperID: id))
            return 0
        case "delete-all":
            try commands.deleteAllPapers()
            try printJSON(CLIStatus(ok: true, action: "delete-all", paperID: nil))
            return 0
        case "fetch-metadata":
            let id = try parsePositionalUUID(args, command: "fetch-metadata")
            try printJSON(await commands.fetchMetadata(id: id))
            return 0
        case "refresh-metadata":
            let id = try parsePositionalUUID(args, command: "refresh-metadata")
            try printJSON(await commands.refreshMetadata(id: id))
            return 0
        case "reextract-metadata-seed":
            let id = try parsePositionalUUID(args, command: "reextract-metadata-seed")
            try printJSON(await commands.reextractMetadataSeed(id: id))
            return 0
        default:
            fputs("Unknown command: \(command)\n", stderr)
            printHelp()
            return 1
        }
    }

    private static func printJSON<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        if let text = String(data: data, encoding: .utf8) {
            print(text)
        }
    }

    package static func parsePositionalUUID(_ args: [String], command: String) throws -> UUID {
        guard args.count >= 2 else { throw CLIError.missingValue("\(command) <paper-id>") }
        guard let id = UUID(uuidString: args[1]) else { throw CLIError.invalidUUID(args[1]) }
        return id
    }

    package static func parseUpdateCommand(_ args: [String]) throws -> UpdatePaperCommand {
        let id = try parsePositionalUUID(args, command: "update")
        var index = 2
        var readingStatus: Paper.ReadingStatus?
        var rating: Int?
        var flagged: Bool?
        var pinned: Bool?
        var tagsToAdd = Set<String>()
        var tagsToRemove = Set<String>()
        var publicationType: String?

        while index < args.count {
            let option = args[index]
            guard index + 1 < args.count else { throw CLIError.missingValue(option) }
            let value = args[index + 1]

            switch option {
            case "--status":
                guard let status = Paper.ReadingStatus(rawValue: value.lowercased()) else {
                    throw CLIError.invalidStatus(value)
                }
                readingStatus = status
            case "--rating":
                guard let parsed = Int(value) else {
                    throw CLIError.invalidInteger(option: option, raw: value)
                }
                rating = parsed
            case "--flagged":
                flagged = try parseBool(value)
            case "--pinned":
                pinned = try parseBool(value)
            case "--tags-add":
                tagsToAdd.formUnion(parseTags(value))
            case "--tags-remove":
                tagsToRemove.formUnion(parseTags(value))
            case "--publication-type":
                publicationType = value.trimmingCharacters(in: .whitespacesAndNewlines)
            default:
                throw CLIError.unexpectedArgument(option)
            }

            index += 2
        }

        return UpdatePaperCommand(
            id: id,
            readingStatus: readingStatus,
            rating: rating,
            flagged: flagged,
            pinned: pinned,
            tagsToAdd: tagsToAdd,
            tagsToRemove: tagsToRemove,
            publicationType: publicationType
        )
    }

    package static func parseListQuery(_ args: [String]) throws -> LibraryListQuery {
        var index = 1
        var searchText = ""
        var readingStatuses = Set<String>()
        var minRating = 0
        var years = Set<Int>()
        var publicationTypes = Set<String>()
        var tags = Set<String>()
        var flaggedOnly = false
        var pinnedOnly = false
        var sortField: PaperSortField = .dateAdded
        var sortAscending = false
        var limit: Int?

        while index < args.count {
            let option = args[index]
            guard index + 1 < args.count else { throw CLIError.missingValue(option) }
            let value = args[index + 1]

            switch option {
            case "--query":
                searchText = value.trimmingCharacters(in: .whitespacesAndNewlines)
            case "--status":
                readingStatuses.formUnion(try parseStatuses(value))
            case "--tag":
                tags.formUnion(parseTags(value))
            case "--year":
                years.formUnion(try parseIntegerSet(value, option: option))
            case "--publication-type":
                publicationTypes.formUnion(parseTags(value))
            case "--min-rating":
                guard let parsed = Int(value) else {
                    throw CLIError.invalidInteger(option: option, raw: value)
                }
                minRating = parsed
            case "--flagged":
                flaggedOnly = try parseBool(value)
            case "--pinned":
                pinnedOnly = try parseBool(value)
            case "--sort":
                sortField = try parseSortField(value)
            case "--ascending":
                sortAscending = try parseBool(value)
            case "--limit":
                guard let parsed = Int(value) else {
                    throw CLIError.invalidInteger(option: option, raw: value)
                }
                limit = parsed
            default:
                throw CLIError.unexpectedArgument(option)
            }

            index += 2
        }

        return LibraryListQuery(
            searchText: searchText,
            readingStatuses: readingStatuses,
            minRating: minRating,
            years: years,
            publicationTypes: publicationTypes,
            tags: tags,
            flaggedOnly: flaggedOnly,
            pinnedOnly: pinnedOnly,
            sortField: sortField,
            sortAscending: sortAscending,
            limit: limit
        )
    }

    package static func parseImportCommand(
        _ args: [String],
        command: String = "import"
    ) throws -> ImportPaperCommand {
        guard args.count >= 2 else { throw CLIError.missingValue("\(command) <pdf-path>") }
        let rawPath = args[1]
        guard !rawPath.isEmpty else { throw CLIError.missingValue("\(command) <pdf-path>") }
        var index = 2
        var webpageMetadata = WebpageMetadata()

        while index < args.count {
            let option = args[index]
            guard index + 1 < args.count else { throw CLIError.missingValue(option) }
            let value = args[index + 1]

            switch option {
            case "--title":
                webpageMetadata.title = normalizedOptionalValue(value)
            case "--authors":
                webpageMetadata.authors = normalizedOptionalValue(value)
            case "--doi":
                webpageMetadata.doi = normalizedOptionalValue(value)
            case "--arxiv-id":
                webpageMetadata.arxivId = normalizedOptionalValue(value)
            case "--abstract":
                webpageMetadata.abstract = normalizedOptionalValue(value)
            case "--venue":
                webpageMetadata.venue = normalizedOptionalValue(value)
            case "--year":
                guard let parsed = Int16(value) else {
                    throw CLIError.invalidInteger(option: option, raw: value)
                }
                webpageMetadata.year = parsed
            case "--source-url":
                webpageMetadata.sourceURL = try parseWebURL(value, option: option)
            case "--pdf-url":
                webpageMetadata.pdfURL = try parseWebURL(value, option: option)
            default:
                throw CLIError.unexpectedArgument(option)
            }

            index += 2
        }

        let hasMetadata =
            webpageMetadata.title != nil
            || webpageMetadata.authors != nil
            || webpageMetadata.doi != nil
            || webpageMetadata.arxivId != nil
            || webpageMetadata.abstract != nil
            || webpageMetadata.venue != nil
            || webpageMetadata.year > 0
            || webpageMetadata.pdfURL != nil
            || webpageMetadata.sourceURL != nil

        return ImportPaperCommand(
            pdfURL: URL(fileURLWithPath: rawPath),
            webpageMetadata: hasMetadata ? webpageMetadata : nil
        )
    }

    private static func parseBool(_ raw: String) throws -> Bool {
        switch raw.lowercased() {
        case "true", "1", "yes":
            return true
        case "false", "0", "no":
            return false
        default:
            throw CLIError.invalidBoolean(raw)
        }
    }

    private static func parseTags(_ raw: String) -> Set<String> {
        Set(
            raw.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }

    private static func parseStatuses(_ raw: String) throws -> Set<String> {
        var statuses = Set<String>()
        for item in parseTags(raw) {
            guard let status = Paper.ReadingStatus(rawValue: item.lowercased()) else {
                throw CLIError.invalidStatus(item)
            }
            statuses.insert(status.rawValue)
        }
        return statuses
    }

    private static func parseIntegerSet(_ raw: String, option: String) throws -> Set<Int> {
        var values = Set<Int>()
        for item in raw.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }).filter({ !$0.isEmpty }) {
            guard let parsed = Int(item) else {
                throw CLIError.invalidInteger(option: option, raw: item)
            }
            values.insert(parsed)
        }
        return values
    }

    private static func parseSortField(_ raw: String) throws -> PaperSortField {
        switch raw.lowercased() {
        case "date-added":
            return .dateAdded
        case "year":
            return .year
        case "title":
            return .title
        case "citations":
            return .citations
        default:
            throw CLIError.invalidSortField(raw)
        }
    }

    private static func normalizedOptionalValue(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func parseWebURL(_ raw: String, option: String) throws -> URL {
        guard let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else {
            throw CLIError.invalidURL(option: option, raw: raw)
        }
        return url
    }

    private static func printHelp() {
        print(
            """
            Papyrus CLI

            Usage:
              papyrus help
              papyrus config
              papyrus list [--query text] [--status unread,reading] [--tag a,b] [--year 2024,2025] [--publication-type journal] [--min-rating 3] [--flagged true|false] [--pinned true|false] [--sort date-added|year|title|citations] [--ascending true|false] [--limit N]
              papyrus get <paper-id>
              papyrus update <paper-id> [--status unread|reading|read] [--rating 0-5] [--flagged true|false] [--pinned true|false] [--tags-add a,b] [--tags-remove c,d] [--publication-type journal]
              papyrus import <pdf-path> [--title t] [--authors a] [--doi d] [--arxiv-id x] [--venue v] [--year yyyy] [--abstract text] [--source-url https://...] [--pdf-url https://...]
              papyrus queue-import <pdf-path> [--title t] [--authors a] [--doi d] [--arxiv-id x] [--venue v] [--year yyyy] [--abstract text] [--source-url https://...] [--pdf-url https://...]
              papyrus delete <paper-id>
              papyrus delete-all
              papyrus fetch-metadata <paper-id>
              papyrus refresh-metadata <paper-id>
              papyrus reextract-metadata-seed <paper-id>
            """
        )
    }
}
