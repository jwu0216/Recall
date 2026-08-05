import Foundation
import SwiftData

public enum MemoryDeletion {
    public static func delete(_ memory: MemoryItem, modelContext: ModelContext) throws {
        if let relativePath = memory.mediaRelativePath,
           let mediaDirectory = AppGroupPaths.shared.mediaDirectory
        {
            let fileURL = mediaDirectory.appendingPathComponent(relativePath)
            try? FileManager.default.removeItem(at: fileURL)
        }

        modelContext.delete(memory)
        try modelContext.save()
    }
}
