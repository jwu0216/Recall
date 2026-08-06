import Foundation
import SwiftData

public final class MemoryProcessor {
    private let aiService: CloudAIService

    /// Ensures only one queue drain runs at a time (App + Home were both processing the same Share job).
    private static let processLock = NSLock()
    private static var isProcessingQueue = false

    public init(aiService: CloudAIService) {
        self.aiService = aiService
    }

    public func process(job: ProcessingJob, modelContext: ModelContext) async throws {
        // Another worker may have already claimed this job.
        guard job.status == .pending else { return }

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

        // Enrich + embed first, then insert as ready. Inserting earlier left memories
        // stuck on "processing" when AI calls failed.
        let enrichment = try await enrich(
            job: job,
            extractedText: extractedText,
            mediaData: mediaData
        )

        let mergedText = mergedExtractedText(
            existing: extractedText,
            originalNote: job.note
        )

        let item = MemoryItem(
            source: job.source,
            contentType: job.contentType,
            title: enrichment.title ?? suggestedTitle(for: job, extractedText: extractedText),
            summary: enrichment.summary,
            extractedText: mergedText,
            tags: enrichment.tags,
            sourceURL: job.sourceURLString.flatMap(URL.init(string:)),
            mediaRelativePath: job.payloadPath,
            processingStatus: .ready
        )

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

        item.lastIndexedAt = .now
        modelContext.insert(item)
        job.status = .ready
        try modelContext.save()
    }

    public func processPendingJobs(modelContext: ModelContext) async {
        Self.processLock.lock()
        if Self.isProcessingQueue {
            Self.processLock.unlock()
            return
        }
        Self.isProcessingQueue = true
        Self.processLock.unlock()

        defer {
            Self.processLock.lock()
            Self.isProcessingQueue = false
            Self.processLock.unlock()
        }

        reclaimStaleProcessingJobs(modelContext: modelContext)
        reconcileStuckMemories(modelContext: modelContext)

        let pendingRaw = ProcessingStatus.pending.rawValue
        let descriptor = FetchDescriptor<ProcessingJob>(
            predicate: #Predicate { $0.statusRaw == pendingRaw },
            sortBy: [SortDescriptor(\.createdAt)]
        )

        guard let jobs = try? modelContext.fetch(descriptor) else { return }

        for job in jobs {
            // Re-check after awaits from earlier jobs in this drain.
            guard job.status == .pending else { continue }
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
            if item.processingStatus == .processing || item.processingStatus == .failed {
                item.processingStatus = .ready
            }
            updated += 1
        }

        try modelContext.save()
        return updated
    }

    /// Jobs interrupted mid-run were stuck in `.processing` and never retried.
    private func reclaimStaleProcessingJobs(modelContext: ModelContext) {
        let processingRaw = ProcessingStatus.processing.rawValue
        let descriptor = FetchDescriptor<ProcessingJob>(
            predicate: #Predicate { $0.statusRaw == processingRaw }
        )
        guard let jobs = try? modelContext.fetch(descriptor), !jobs.isEmpty else { return }
        for job in jobs {
            job.status = .pending
        }
        try? modelContext.save()
    }

    /// Repair memories left on `.processing` by older builds.
    private func reconcileStuckMemories(modelContext: ModelContext) {
        let processingRaw = ProcessingStatus.processing.rawValue
        let descriptor = FetchDescriptor<MemoryItem>(
            predicate: #Predicate { $0.processingStatusRaw == processingRaw }
        )
        guard let items = try? modelContext.fetch(descriptor), !items.isEmpty else { return }
        for item in items {
            item.processingStatus = item.embedding == nil ? .failed : .ready
            item.updatedAt = .now
        }
        try? modelContext.save()
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
