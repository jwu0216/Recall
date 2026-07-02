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

        if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            let storeURL = groupURL.appendingPathComponent("Recall.store")
            let configuration = ModelConfiguration(schema: schema, url: storeURL)
            return try ModelContainer(for: schema, configurations: [configuration])
        }

        let fallback = ModelConfiguration(schema: schema)
        return try ModelContainer(for: schema, configurations: [fallback])
    }
}
