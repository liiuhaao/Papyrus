// Persistence.swift
// Core Data Stack - Code-defined model (reliable version)

import CoreData
import Foundation

package struct PersistenceController {
    package static let shared = PersistenceController()

    package let container: NSPersistentContainer

    private static func rawDbPath() -> String {
        UserDefaults.standard.string(forKey: "settings.general.db_path")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func storeDbPath(_ path: String) {
        UserDefaults.standard.set(path, forKey: "settings.general.db_path")
    }

    private static func defaultDocumentsStoreURL() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("Papyrus Library").appendingPathComponent("Papyrus.sqlite")
    }

    // Current store URL — reads the dedicated db_path key if set; otherwise use the default library location.
    package static var desiredStoreURL: URL {
        let raw = rawDbPath()
        if !raw.isEmpty {
            return URL(fileURLWithPath: (raw as NSString).expandingTildeInPath)
        }
        return defaultDocumentsStoreURL()
    }

    init(inMemory: Bool = false) {
        // Build model programmatically
        let model = NSManagedObjectModel()

        let paperEntity = NSEntityDescription()
        paperEntity.name = "Paper"
        paperEntity.managedObjectClassName = "PapyrusCore.Paper"

        func attr(
            _ name: String,
            _ type: NSAttributeType,
            optional: Bool = true,
            default def: Any? = nil,
            transient: Bool = false
        ) -> NSAttributeDescription {
            let a = NSAttributeDescription()
            a.name = name; a.attributeType = type; a.isOptional = optional
            a.isTransient = transient
            if let def { a.defaultValue = def }
            return a
        }

        paperEntity.properties = [
            attr("id",                    .UUIDAttributeType,      optional: false, default: UUID()),
            attr("title",                 .stringAttributeType),
            attr("authors",               .stringAttributeType),
            attr("venue",                 .stringAttributeType),
            attr("year",                  .integer16AttributeType, optional: false, default: 0),
            attr("doi",                   .stringAttributeType),
            attr("arxivId",               .stringAttributeType),
            attr("seedTitle",             .stringAttributeType),
            attr("seedAuthors",           .stringAttributeType),
            attr("seedVenue",             .stringAttributeType),
            attr("seedYear",              .integer16AttributeType, optional: false, default: 0),
            attr("seedDOI",               .stringAttributeType),
            attr("seedArxivId",           .stringAttributeType),
            attr("seedAbstract",          .stringAttributeType),
            attr("seedPublicationType",   .stringAttributeType),
            attr("resolvedTitle",         .stringAttributeType),
            attr("resolvedAuthors",       .stringAttributeType),
            attr("resolvedVenue",         .stringAttributeType),
            attr("resolvedYear",          .integer16AttributeType, optional: false, default: 0),
            attr("resolvedDOI",           .stringAttributeType),
            attr("resolvedArxivId",       .stringAttributeType),
            attr("resolvedAbstract",      .stringAttributeType),
            attr("resolvedPublicationType", .stringAttributeType),
            attr("resolvedCitationCount", .integer32AttributeType, optional: false, default: -1),
            attr("filePath",              .stringAttributeType),
            attr("originalFilename",      .stringAttributeType),
            attr("dateAdded",             .dateAttributeType,      optional: false, default: Date()),
            attr("dateModified",          .dateAttributeType,      optional: false, default: Date()),
            attr("abstract",              .stringAttributeType),
            attr("tags",                  .stringAttributeType),
            attr("isFlagged",             .booleanAttributeType,   optional: false, default: false),
            attr("isPinned",              .booleanAttributeType,   optional: false, default: false),
            attr("readingStatus",         .stringAttributeType,    optional: false, default: "unread"),
            attr("rating",                .integer16AttributeType, optional: false, default: 0),
            attr("citationCount",         .integer32AttributeType, optional: false, default: -1),
            attr("pinOrder",              .integer32AttributeType, optional: false, default: 0),
            attr("titleManual",           .booleanAttributeType,   optional: false, default: false),
            attr("authorsManual",         .booleanAttributeType,   optional: false, default: false),
            attr("venueManual",           .booleanAttributeType,   optional: false, default: false),
            attr("yearManual",            .booleanAttributeType,   optional: false, default: false),
            attr("doiManual",             .booleanAttributeType,   optional: false, default: false),
            attr("arxivManual",           .booleanAttributeType,   optional: false, default: false),
            attr("publicationType",       .stringAttributeType),
            attr("publicationTypeManual", .booleanAttributeType,   optional: false, default: false),
            attr("notes",                 .stringAttributeType),
            attr("enrichStatus",          .stringAttributeType, transient: true),

            // MARK: Audit fields
            attr("seedMetadataJSON",        .stringAttributeType),
            attr("manualTitle",             .stringAttributeType),
            attr("manualAuthors",           .stringAttributeType),
            attr("manualVenue",             .stringAttributeType),
            attr("manualYear",              .integer16AttributeType, optional: false, default: 0),
            attr("manualDOI",               .stringAttributeType),
            attr("manualArxivId",           .stringAttributeType),
            attr("manualPublicationType",   .stringAttributeType),
            attr("fetchCandidatesJSON",     .stringAttributeType),
            attr("fetchSelectedSource",     .stringAttributeType),
            attr("fetchSelectedScore",      .doubleAttributeType,    optional: false, default: 0),
            attr("fetchSelectedTrace",      .stringAttributeType),
            attr("fetchTimestamp",          .dateAttributeType),
        ]

        // MARK: Venue entity
        let venueEntity = NSEntityDescription()
        venueEntity.name = "Venue"
        venueEntity.managedObjectClassName = "PapyrusCore.Venue"
        venueEntity.properties = [
            attr("name",         .stringAttributeType, optional: false),
            attr("abbreviation", .stringAttributeType),
            attr("rankSourceJSON", .stringAttributeType),
        ]

        // Paper.venueObject ←→ Venue.papers
        let paperToVenue = NSRelationshipDescription()
        paperToVenue.name = "venueObject"
        paperToVenue.isOptional = true
        paperToVenue.minCount = 0
        paperToVenue.maxCount = 1
        paperToVenue.deleteRule = .nullifyDeleteRule

        let venueToPapers = NSRelationshipDescription()
        venueToPapers.name = "papers"
        venueToPapers.isOptional = true
        venueToPapers.minCount = 0
        venueToPapers.maxCount = 0  // 0 = unlimited (to-many)
        venueToPapers.deleteRule = .nullifyDeleteRule

        paperToVenue.destinationEntity  = venueEntity
        paperToVenue.inverseRelationship = venueToPapers
        venueToPapers.destinationEntity  = paperEntity
        venueToPapers.inverseRelationship = paperToVenue

        paperEntity.properties += [paperToVenue]
        venueEntity.properties += [venueToPapers]

        model.entities = [paperEntity, venueEntity]

        container = NSPersistentContainer(name: "PapyrusData", managedObjectModel: model)
        container.persistentStoreDescriptions.first?.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
        container.persistentStoreDescriptions.first?.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)

        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        } else {
            let storeURL = Self.desiredStoreURL
            try? FileManager.default.createDirectory(
                at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            container.persistentStoreDescriptions.first!.url = storeURL
            Self.storeDbPath(storeURL.path)
        }

        container.loadPersistentStores { _, error in
            if let error { print("Core Data load error: \(error)") }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    /// Migrate the persistent store (with all data) to a new URL at runtime.
    func migrateStore(to newURL: URL) throws {
        guard let store = container.persistentStoreCoordinator.persistentStores.first else { return }
        try FileManager.default.createDirectory(
            at: newURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let options: [AnyHashable: Any] = [
            NSMigratePersistentStoresAutomaticallyOption: true,
            NSInferMappingModelAutomaticallyOption: true,
        ]
        try container.persistentStoreCoordinator.migratePersistentStore(
            store, to: newURL, options: options, withType: NSSQLiteStoreType)
    }

    /// Switch to a fresh empty store at a new URL (old store stays in place).
    func switchStore(to newURL: URL) throws {
        let coordinator = container.persistentStoreCoordinator
        let postWillSwitch = {
            NotificationCenter.default.post(name: .libraryWillSwitch, object: nil)
        }
        if Thread.isMainThread {
            postWillSwitch()
        } else {
            DispatchQueue.main.sync(execute: postWillSwitch)
        }
        container.viewContext.performAndWait {
            container.viewContext.reset()
        }
        if let old = coordinator.persistentStores.first {
            try coordinator.remove(old)
        }
        try FileManager.default.createDirectory(
            at: newURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let options: [AnyHashable: Any] = [
            NSMigratePersistentStoresAutomaticallyOption: true,
            NSInferMappingModelAutomaticallyOption: true,
        ]
        try coordinator.addPersistentStore(
            ofType: NSSQLiteStoreType, configurationName: nil, at: newURL, options: options)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .libraryDidSwitch, object: nil)
        }
    }
}

extension Notification.Name {
    /// Posted immediately before the current store is detached.
    static let libraryWillSwitch = Notification.Name("Papyrus.libraryWillSwitch")
    /// Posted after the new store is open and ready.
    static let libraryDidSwitch  = Notification.Name("Papyrus.libraryDidSwitch")
    /// Posted when the user requests a bulk refresh of venue rankings.
    static let refreshVenueRankings = Notification.Name("Papyrus.refreshVenueRankings")
}
