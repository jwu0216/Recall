import Foundation

public enum MemorySource: String, Codable, CaseIterable {
    case share
    case photoLibrary
    case manual
}

public enum ContentType: String, Codable, CaseIterable {
    case link
    case image
    case pdf
    case text
    case photo
}

public enum ProcessingStatus: String, Codable, CaseIterable {
    case pending
    case processing
    case ready
    case failed
}

public struct AIEnrichment: Codable, Equatable, Sendable {
    public var title: String?
    public var summary: String?
    public var tags: [String]

    public init(title: String? = nil, summary: String? = nil, tags: [String] = []) {
        self.title = title
        self.summary = summary
        self.tags = tags
    }
}

public struct ChatTurn: Codable, Equatable, Sendable {
    public var role: String
    public var content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

public struct MemorySearchResult: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let item: MemoryItemSnapshot
    public let score: Double

    public init(item: MemoryItemSnapshot, score: Double) {
        self.id = item.id
        self.item = item
        self.score = score
    }
}

public struct MemoryItemSnapshot: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let source: MemorySource
    public let contentType: ContentType
    public let title: String?
    public let summary: String?
    public let extractedText: String?
    public let tags: [String]
    public let sourceURL: URL?
    public let processingStatus: ProcessingStatus

    public init(
        id: UUID,
        createdAt: Date,
        source: MemorySource,
        contentType: ContentType,
        title: String?,
        summary: String?,
        extractedText: String?,
        tags: [String],
        sourceURL: URL?,
        processingStatus: ProcessingStatus
    ) {
        self.id = id
        self.createdAt = createdAt
        self.source = source
        self.contentType = contentType
        self.title = title
        self.summary = summary
        self.extractedText = extractedText
        self.tags = tags
        self.sourceURL = sourceURL
        self.processingStatus = processingStatus
    }

    public var searchableText: String {
        [title, summary, extractedText, tags.joined(separator: " ")]
            .compactMap { $0 }
            .joined(separator: "\n")
    }
}
