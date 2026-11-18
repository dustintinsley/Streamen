//
//  CloudKitSchemaInitializer.swift
//  Streamen
//
//  Debug-only: writes the full CloudKit schema for the iCloud-mirrored store
//  to the container's Development environment, so it can be deployed to
//  Production from the CloudKit Console before a TestFlight or App Store
//  build. CloudKit otherwise only learns a record type once a record of it
//  syncs, and types nobody has used in a Debug build yet (a parental PIN, a
//  recording server) would be missing from Production and fail to sync there.
//
//  `initializeCloudKitSchema` uploads one sample record per entity and then
//  deletes it. It runs on a throwaway store in the temporary folder, so the
//  app's own stores are never touched, and only a Development-signed build
//  can reach the Development environment.
//

#if DEBUG

    import CoreData
    import Foundation
    import SwiftData

    nonisolated enum CloudKitSchemaInitializer {
        enum Failure: LocalizedError {
            case noModel

            var errorDescription: String? {
                "Couldn't build a Core Data model from the synced types."
            }
        }

        /// The record types the schema covers, in CloudKit's `CD_` naming.
        static var recordTypeNames: [String] {
            types.map { "CD_\(String(describing: $0))" }
        }

        private static var types: [any PersistentModel.Type] {
            StreamenApp.cloudMirrorModels + [SyncedBackendChoice.self]
        }

        /// Blocks while CloudKit uploads; call it off the main thread.
        static func run() throws {
            guard let model = NSManagedObjectModel.makeManagedObjectModel(for: types) else {
                throw Failure.noModel
            }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("cloudkit-schema-\(UUID().uuidString).sqlite")
            let description = NSPersistentStoreDescription(url: url)
            description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: StreamenApp.cloudKitContainerIdentifier
            )
            description.shouldAddStoreAsynchronously = false

            let container = NSPersistentCloudKitContainer(name: "CloudKitSchema", managedObjectModel: model)
            container.persistentStoreDescriptions = [description]
            var loadError: Error?
            container.loadPersistentStores { _, error in loadError = error }
            if let loadError { throw loadError }

            defer {
                let coordinator = container.persistentStoreCoordinator
                for store in coordinator.persistentStores {
                    try? coordinator.remove(store)
                }
                for suffix in ["", "-shm", "-wal"] {
                    try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
                }
            }
            try container.initializeCloudKitSchema()
        }
    }

#endif
