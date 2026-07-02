import Foundation
import SwiftData

public enum ProcessingQueueService {
    public static func enqueue(
        contentType: ContentType,
        sourceURL: URL? = nil,
        note: String? = nil,
        payloadFilename: String? = nil,
        modelContext: ModelContext
    ) throws {
        let job = ProcessingJob(
            contentType: contentType,
            payloadPath: payloadFilename,
            sourceURL: sourceURL,
            note: note
        )
        modelContext.insert(job)
        try modelContext.save()
    }
}
