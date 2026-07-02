import Foundation

public final class AppGroupPaths {
    public static let shared = AppGroupPaths()

    private init() {}

    public var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: RecallConstants.appGroupID)
    }

    public var mediaDirectory: URL? {
        guard let containerURL else { return nil }
        let mediaURL = containerURL.appendingPathComponent(RecallConstants.sharedMediaFolder, isDirectory: true)
        if !FileManager.default.fileExists(atPath: mediaURL.path) {
            try? FileManager.default.createDirectory(at: mediaURL, withIntermediateDirectories: true)
        }
        return mediaURL
    }

    public func uniqueMediaURL(fileExtension: String) -> URL? {
        mediaDirectory?.appendingPathComponent("\(UUID().uuidString).\(fileExtension)")
    }
}
