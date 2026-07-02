import Foundation
import SwiftData

public final class MemoryProcessor {
    private let aiService: CloudAIService

    public init(aiService: CloudAIService) {
        self.aiService = aiService
    }

    public func process(job: ProcessingJob, modelContext: ModelContext) async throws {
        job.status = .processing

        let item = MemoryItem(
            source: job.source,
            contentType: job.contentType,
            title: job.note,
            extractedText: job.note,
            sourceURL: job.sourceURLString.flatMap(URL.init(string:)),
            mediaRelativePath: job.payloadPath,
            processingStatus: .processing
        )

        modelContext.insert(item)

        let enrichment = try await enrich(job: job)
        item.title = enrichment.title ?? item.title
        item.summary = enrichment.summary
        item.tags = enrichment.tags
        item.updatedAt = .now
        item.lastIndexedAt = .now

        let embedText = [item.title, item.summary, item.extractedText, item.tags.joined(separator: " ")]
            .compactMap { $0 }
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

    private func enrich(job: ProcessingJob) async throws -> AIEnrichment {
        switch job.contentType {
        case .link, .text:
            let text = [job.note, job.sourceURLString].compactMap { $0 }.joined(separator: "\n")
            return try await aiService.summarizeText(text)
        case .image, .photo, .pdf:
            if
                let payloadPath = job.payloadPath,
                let mediaDirectory = AppGroupPaths.shared.mediaDirectory
            {
                let fileURL = mediaDirectory.appendingPathComponent(payloadPath)
                let data = try Data(contentsOf: fileURL)
                return try await aiService.describeImage(data, ocrText: job.note)
            }
            return try await aiService.summarizeText(job.note ?? "")
        }
    }
}
