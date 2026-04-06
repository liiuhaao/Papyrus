// FileManager.swift
// Handle paper file organization and naming

import Foundation

class PaperFileManager: FileStorageProviding {
    
    nonisolated static let shared = PaperFileManager()
    
    /// Library directory URL
    var libraryURL: URL {
        let configured = FileStorageConfig.libraryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let libraryURL: URL
        if configured.isEmpty {
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            libraryURL = documentsURL.appendingPathComponent("Papyrus Library")
        } else {
            let expanded = (configured as NSString).expandingTildeInPath
            libraryURL = URL(fileURLWithPath: expanded, isDirectory: true)
        }
        
        ensureLibraryLayout(at: libraryURL)
        
        return libraryURL
    }

    var pdfDirectoryURL: URL {
        libraryURL.appendingPathComponent("PDF", isDirectory: true)
    }

    var attachmentsDirectoryURL: URL {
        libraryURL.appendingPathComponent("Attachments", isDirectory: true)
    }
    
    /// Generate filename from paper metadata
    func generateFilename(for paper: Paper) -> String {
        var components: [String] = []
        
        // Add first author last name
        if let authors = paper.authors, !authors.isEmpty {
            let firstAuthor = authors.components(separatedBy: ",").first ?? authors
            let lastName = firstAuthor.components(separatedBy: " ").last ?? firstAuthor
            components.append(sanitizeFilename(lastName))
        } else {
            components.append("Unknown")
        }
        
        // Add year
        if paper.year > 0 {
            components.append("\(paper.year)")
        }
        
        // Add title (first few words)
        if let title = paper.title, !title.isEmpty {
            let shortTitle = shortenTitle(title)
            components.append(shortTitle)
        }
        
        // Add venue abbreviation if available
        if let venue = paper.venue, !venue.isEmpty {
            let abbrev = venueAbbreviation(venue)
            if !abbrev.isEmpty {
                components.append(abbrev)
            }
        }
        
        let filename = components.joined(separator: " - ")
        return filename + ".pdf"
    }
    
    /// Import a PDF file into the library
    func importPDF(from sourceURL: URL, paper: Paper) throws -> URL {
        let filename = generatePDFFilename(for: paper)
        let destinationURL = pdfDirectoryURL.appendingPathComponent(filename)
        
        // Handle duplicates
        let finalURL = uniqueURL(for: destinationURL)
        
        try FileManager.default.copyItem(at: sourceURL, to: finalURL)
        
        return finalURL
    }
    
    /// Move/rename file when paper metadata changes
    func renameFile(for paper: Paper) throws -> URL? {
        guard let currentPath = paper.filePath else { return nil }
        let currentURL = URL(fileURLWithPath: currentPath)
        
        let newFilename = generatePDFFilename(for: paper)
        let newURL = pdfDirectoryURL.appendingPathComponent(newFilename)
        
        // Only rename if name changed
        if currentURL.lastPathComponent != newFilename {
            let finalURL = uniqueURL(for: newURL)
            try FileManager.default.moveItem(at: currentURL, to: finalURL)
            return finalURL
        }
        
        return currentURL
    }

    func notesURL(for paper: Paper) -> URL {
        attachmentsDirectory(for: paper).appendingPathComponent("notes.md")
    }

    func loadNotes(for paper: Paper) -> String? {
        let fallbackURL = notesURL(for: paper)
        return try? String(contentsOf: fallbackURL, encoding: .utf8)
    }

    @discardableResult
    func saveNotes(_ content: String?, for paper: Paper) throws -> URL? {
        let raw = content ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetURL = notesURL(for: paper)
        if trimmed.isEmpty {
            if FileManager.default.fileExists(atPath: targetURL.path) {
                try? FileManager.default.removeItem(at: targetURL)
            }
            return nil
        }

        let directory = targetURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        // Atomic write prevents partial content when autosave is interrupted.
        try trimmed.write(to: targetURL, atomically: true, encoding: .utf8)
        return targetURL
    }

    func removeAttachments(for paper: Paper) {
        let directory = attachmentsDirectory(for: paper)
        if FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.removeItem(at: directory)
        }
    }
    
    // MARK: - Helpers
    
    private func sanitizeFilename(_ string: String) -> String {
        var sanitized = string
        let invalidCharacters = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        sanitized = sanitized.components(separatedBy: invalidCharacters).joined(separator: "")
        return sanitized.trimmingCharacters(in: .whitespaces)
    }
    
    private func shortenTitle(_ title: String) -> String {
        let words = title.components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
        
        // Take first 4-6 meaningful words
        let maxWords = min(6, words.count)
        let shortWords = Array(words.prefix(maxWords))
        
        return shortWords.joined(separator: " ")
    }
    
    private func venueAbbreviation(_ venue: String) -> String {
        let uppercased = venue.uppercased()
        
        // Common CS conferences
        let abbreviations: [String: String] = [
            "INTERNATIONAL CONFERENCE ON LEARNING REPRESENTATIONS": "ICLR",
            "IEEE INTERNATIONAL CONFERENCE ON DATA ENGINEERING": "ICDE",
            "IEEE TRANSACTIONS ON MOBILE COMPUTING": "TMC",
            "IEEE JOURNAL ON SELECTED AREAS IN COMMUNICATIONS": "JSAC",
            "ADVANCES IN NEURAL INFORMATION PROCESSING SYSTEMS": "NeurIPS",
            "INTERNATIONAL CONFERENCE ON MACHINE LEARNING": "ICML",
            "CONFERENCE ON COMPUTER VISION AND PATTERN RECOGNITION": "CVPR",
            "CONFERENCE ON EMPIRICAL METHODS IN NATURAL LANGUAGE PROCESSING": "EMNLP",
            "ANNUAL MEETING OF THE ASSOCIATION FOR COMPUTATIONAL LINGUISTICS": "ACL",
            "CONFERENCE ON ARTIFICIAL INTELLIGENCE": "AAAI",
            "INTERNATIONAL JOINT CONFERENCE ON ARTIFICIAL INTELLIGENCE": "IJCAI",
            "CONFERENCE ON OBJECT-ORIENTED PROGRAMMING": "OOPSLA",
            "PROGRAMMING LANGUAGE DESIGN AND IMPLEMENTATION": "PLDI",
            "OPERATING SYSTEMS DESIGN AND IMPLEMENTATION": "OSDI",
            "SYMPOSIUM ON OPERATING SYSTEMS PRINCIPLES": "SOSP"
        ]
        
        // Check for exact match
        for (full, abbrev) in abbreviations {
            if uppercased.contains(full) {
                return abbrev
            }
        }
        
        // Extract acronym from venue name
        let words = venue.components(separatedBy: .whitespacesAndNewlines)
        let acronym = words.compactMap { word -> String? in
            guard let first = word.first else { return nil }
            return String(first).uppercased()
        }.joined()
        
        return acronym
    }
    
    private func uniqueURL(for url: URL) -> URL {
        var uniqueURL = url
        var counter = 1
        let baseName = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        
        while FileManager.default.fileExists(atPath: uniqueURL.path) {
            let newName = "\(baseName) (\(counter)).\(ext)"
            uniqueURL = url.deletingLastPathComponent().appendingPathComponent(newName)
            counter += 1
        }
        
        return uniqueURL
    }

    private func generatePDFFilename(for paper: Paper) -> String {
        let titlePart = normalizedTitlePart(for: paper)
        let shortID = shortPaperID(for: paper)
        return "\(titlePart)__\(shortID).pdf"
    }

    private func attachmentsDirectory(for paper: Paper) -> URL {
        attachmentsDirectoryURL
            .appendingPathComponent("\(normalizedTitlePart(for: paper))__\(shortPaperID(for: paper))", isDirectory: true)
    }

    private func ensureLibraryLayout(at root: URL) {
        if !FileManager.default.fileExists(atPath: root.path) {
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }
        let folders = ["PDF", "Attachments"]
        for folder in folders {
            let path = root.appendingPathComponent(folder, isDirectory: true)
            if !FileManager.default.fileExists(atPath: path.path) {
                try? FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
            }
        }
    }

    private func normalizedTitlePart(for paper: Paper) -> String {
        let raw = paper.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutExtension = raw.replacingOccurrences(of: #"\.pdf$"#, with: "", options: [.regularExpression, .caseInsensitive])
        let base = sanitizeFilename(withoutExtension.isEmpty ? "untitled" : withoutExtension)
        return base.isEmpty ? "untitled" : base
    }

    private func shortPaperID(for paper: Paper) -> String {
        let compact = paper.id.uuidString
            .lowercased()
            .replacingOccurrences(of: "-", with: "")
        return String(compact.prefix(10))
    }
}

enum FileStorageConfig {
    nonisolated(unsafe) static var libraryPath: String = ""
}
