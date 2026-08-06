import Foundation
import SwiftData

public enum RecallModelContainerFactory {
    public static let appGroupID = RecallConstants.appGroupID

    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([
            MemoryItem.self,
            ProcessingJob.self,
            ChatMessage.self
        ])

        if inMemory {
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try ModelContainer(for: schema, configurations: [configuration])
        }

        // Require the App Group. A silent local fallback made Share writes land in a
        // different store than the main app (so links appeared "saved" but never showed up).
        guard
            let groupURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: appGroupID
            )
        else {
            throw RecallStoreError.appGroupUnavailable
        }

        let storeURL = groupURL.appendingPathComponent("Recall.store")
        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
