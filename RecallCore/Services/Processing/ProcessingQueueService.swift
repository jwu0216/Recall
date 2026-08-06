import Foundation
import SwiftData

public enum ProcessingQueueService {
    public static let lastEnqueueAtKey = "recall.lastShareEnqueueAt"

    public static func enqueue(
        contentType: ContentType,
        source: MemorySource = .share,
        sourceURL: URL? = nil,
        note: String? = nil,
        payloadFilename: String? = nil,
        modelContext: ModelContext
    ) throws {
        let job = ProcessingJob(
            source: source,
            contentType: contentType,
            payloadPath: payloadFilename,
            sourceURL: sourceURL,
            note: note
        )
        modelContext.insert(job)
        try modelContext.save()

        // Ping the shared defaults so the main app knows the store changed out-of-process.
        if let defaults = UserDefaults(suiteName: RecallConstants.appGroupID) {
            defaults.set(Date().timeIntervalSince1970, forKey: lastEnqueueAtKey)
            defaults.synchronize()
        }
    }

    public static func lastEnqueueAt() -> Date? {
        guard
            let defaults = UserDefaults(suiteName: RecallConstants.appGroupID),
            defaults.object(forKey: lastEnqueueAtKey) != nil
        else {
            return nil
        }
        return Date(timeIntervalSince1970: defaults.double(forKey: lastEnqueueAtKey))
    }
}
