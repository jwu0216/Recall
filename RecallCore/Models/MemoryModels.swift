import Foundation
import SwiftData

@Model
public final class MemoryItem {
    @Attribute(.unique) public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var sourceRaw: String
    public var contentTypeRaw: String
    public var title: String?
    public var summary: String?
    public var extractedText: String?
    public var tags: [String]
    public var embedding: [Float]?
    public var sourceURLString: String?
    public var photoLocalIdentifier: String?
    public var mediaRelativePath: String?
    public var processingStatusRaw: String
    public var lastIndexedAt: Date?

    public var source: MemorySource {
        get { MemorySource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    public var contentType: ContentType {
        get { ContentType(rawValue: contentTypeRaw) ?? .text }
        set { contentTypeRaw = newValue.rawValue }
    }

    public var processingStatus: ProcessingStatus {
        get { ProcessingStatus(rawValue: processingStatusRaw) ?? .pending }
        set { processingStatusRaw = newValue.rawValue }
    }

    public var sourceURL: URL? {
        get {
            guard let sourceURLString else { return nil }
            return URL(string: sourceURLString)
        }
        set {
            sourceURLString = newValue?.absoluteString
        }
    }

    public init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        updatedAt: Date = .now,
        source: MemorySource,
        contentType: ContentType,
        title: String? = nil,
        summary: String? = nil,
        extractedText: String? = nil,
        tags: [String] = [],
        embedding: [Float]? = nil,
        sourceURL: URL? = nil,
        photoLocalIdentifier: String? = nil,
        mediaRelativePath: String? = nil,
        processingStatus: ProcessingStatus = .pending,
        lastIndexedAt: Date? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sourceRaw = source.rawValue
        self.contentTypeRaw = contentType.rawValue
        self.title = title
        self.summary = summary
        self.extractedText = extractedText
        self.tags = tags
        self.embedding = embedding
        self.sourceURLString = sourceURL?.absoluteString
        self.photoLocalIdentifier = photoLocalIdentifier
        self.mediaRelativePath = mediaRelativePath
        self.processingStatusRaw = processingStatus.rawValue
        self.lastIndexedAt = lastIndexedAt
    }

    public func snapshot() -> MemoryItemSnapshot {
        MemoryItemSnapshot(
            id: id,
            createdAt: createdAt,
            source: source,
            contentType: contentType,
            title: title,
            summary: summary,
            extractedText: extractedText,
            tags: tags,
            sourceURL: sourceURL,
            processingStatus: processingStatus
        )
    }
}

@Model
public final class ProcessingJob {
    @Attribute(.unique) public var id: UUID
    public var createdAt: Date
    public var sourceRaw: String
    public var contentTypeRaw: String
    public var statusRaw: String
    public var payloadPath: String?
    public var sourceURLString: String?
    public var note: String?

    public var source: MemorySource {
        get { MemorySource(rawValue: sourceRaw) ?? .share }
        set { sourceRaw = newValue.rawValue }
    }

    public var contentType: ContentType {
        get { ContentType(rawValue: contentTypeRaw) ?? .text }
        set { contentTypeRaw = newValue.rawValue }
    }

    public var status: ProcessingStatus {
        get { ProcessingStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    public init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        source: MemorySource = .share,
        contentType: ContentType,
        status: ProcessingStatus = .pending,
        payloadPath: String? = nil,
        sourceURL: URL? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.sourceRaw = source.rawValue
        self.contentTypeRaw = contentType.rawValue
        self.statusRaw = status.rawValue
        self.payloadPath = payloadPath
        self.sourceURLString = sourceURL?.absoluteString
        self.note = note
    }
}

@Model
public final class ChatMessage {
    @Attribute(.unique) public var id: UUID
    public var createdAt: Date
    public var role: String
    public var content: String

    public init(id: UUID = UUID(), createdAt: Date = .now, role: String, content: String) {
        self.id = id
        self.createdAt = createdAt
        self.role = role
        self.content = content
    }
}
