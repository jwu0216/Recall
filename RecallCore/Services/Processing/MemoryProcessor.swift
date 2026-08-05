import Foundation
import SwiftData

public final class MemoryProcessor {
    private let aiService: CloudAIService

    public init(aiService: CloudAIService) {
        self.aiService = aiService
    }

    public func process(job: ProcessingJob, modelContext: ModelContext) async throws {
        job.status = .processing
        try modelContext.save()

        var extractedText = job.note
        var mediaData: Data?

        if
            let payloadPath = job.payloadPath,
            let mediaDirectory = AppGroupPaths.shared.mediaDirectory
        {
            let fileURL = mediaDirectory.appendingPathComponent(payloadPath)
            if let data = try? Data(contentsOf: fileURL) {
                mediaData = data
                if job.contentType == .image || job.contentType == .photo {
                    let ocr = await TextExtractor.ocrImage(data: data)
                    if !ocr.isEmpty {
                        extractedText = [job.note, ocr]
                            .compactMap { $0 }
                            .filter { !$0.isEmpty }
                            .joined(separator: "\n")
                    }
                }
            }
        }

        let item = MemoryItem(
            source: job.source,
            contentType: job.contentType,
            title: suggestedTitle(for: job, extractedText: extractedText),
            extractedText: extractedText,
            sourceURL: job.sourceURLString.flatMap(URL.init(string:)),
            mediaRelativePath: job.payloadPath,
            processingStatus: .processing
        )

        modelContext.insert(item)

        let enrichment = try await enrich(
            job: job,
            extractedText: extractedText,
            mediaData: mediaData
        )
        item.title = enrichment.title ?? item.title
        item.summary = enrichment.summary
        item.tags = enrichment.tags
        // Keep the user's original words searchable even if AI rewrites the title.
        item.extractedText = mergedExtractedText(
            existing: item.extractedText ?? extractedText,
            originalNote: job.note
        )
        item.updatedAt = .now
        item.lastIndexedAt = .now

        let embedText = [
            item.title,
            item.summary,
            item.extractedText,
            job.note,
            item.sourceURL?.host,
            item.sourceURL?.absoluteString,
            item.tags.joined(separator: " ")
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        if !embedText.isEmpty {
            item.embedding = try await aiService.embed(embedText)
        }

        item.processingStatus = .ready
        job.status = .ready
        try modelContext.save()
    }

    public func processPendingJobs(modelContext: ModelContext) async {
        let pendingRaw = ProcessingStatus.pending.rawValue
        let descriptor = FetchDescriptor<ProcessingJob>(
            predicate: #Predicate { $0.statusRaw == pendingRaw },
            sortBy: [SortDescriptor(\.createdAt)]
        )

        guard let jobs = try? modelContext.fetch(descriptor) else { return }

        for job in jobs {
            do {
                try await process(job: job, modelContext: modelContext)
            } catch {
                job.status = .failed
                try? modelContext.save()
            }
        }
    }

    public static func pendingJobCount(modelContext: ModelContext) -> Int {
        let pendingRaw = ProcessingStatus.pending.rawValue
        let descriptor = FetchDescriptor<ProcessingJob>(
            predicate: #Predicate { $0.statusRaw == pendingRaw }
        )
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    /// Refresh tags/summary from source text, then rebuild embeddings for Ask.
    public func reindexEmbeddings(modelContext: ModelContext) async throws -> Int {
        let descriptor = FetchDescriptor<MemoryItem>(sortBy: [SortDescriptor(\.createdAt)])
        let items = try modelContext.fetch(descriptor)
        var updated = 0

        for item in items {
            let sourceText = [
                item.extractedText,
                item.title,
                item.sourceURL?.absoluteString
            ]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")

            if !sourceText.isEmpty, !item.userEditedLabels {
                let enrichment = try await aiService.summarizeText(sourceText)
                // Keep the existing title; refresh summary/tags for search quality.
                if let summary = enrichment.summary, !summary.isEmpty {
                    item.summary = summary
                }
                if !enrichment.tags.isEmpty {
                    item.tags = enrichment.tags
                }
            }

            let embedText = [
                item.title,
                item.summary,
                item.extractedText,
                item.sourceURL?.host,
                item.sourceURL?.absoluteString,
                item.tags.joined(separator: " ")
            ]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")

            guard !embedText.isEmpty else { continue }
            item.embedding = try await aiService.embed(embedText)
            item.lastIndexedAt = .now
            item.updatedAt = .now
            updated += 1
        }

        try modelContext.save()
        return updated
    }

    private func enrich(
        job: ProcessingJob,
        extractedText: String?,
        mediaData: Data?
    ) async throws -> AIEnrichment {
        switch job.contentType {
        case .link, .text:
            let text = [extractedText, job.sourceURLString]
                .compactMap { $0 }
                .joined(separator: "\n")
            return try await aiService.summarizeText(text.isEmpty ? "Untitled memory" : text)
        case .image, .photo, .pdf:
            if let mediaData {
                return try await aiService.describeImage(mediaData, ocrText: extractedText)
            }
            return try await aiService.summarizeText(extractedText ?? job.note ?? "Saved file")
        }
    }

    private func suggestedTitle(for job: ProcessingJob, extractedText: String?) -> String? {
        if let note = job.note, !note.isEmpty {
            return String(note.prefix(80))
        }
        if let url = job.sourceURLString, let host = URL(string: url)?.host {
            return host
        }
        if let extractedText, !extractedText.isEmpty {
            return String(extractedText.prefix(80))
        }
        return nil
    }

    private func mergedExtractedText(existing: String?, originalNote: String?) -> String? {
        let existingText = existing?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let note = originalNote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        switch (existingText.isEmpty, note.isEmpty) {
        case (true, true):
            return nil
        case (true, false):
            return note
        case (false, true):
            return existingText
        case (false, false):
            if existingText.localizedCaseInsensitiveContains(note) {
                return existingText
            }
            return note + "\n" + existingText
        }
    }
}
