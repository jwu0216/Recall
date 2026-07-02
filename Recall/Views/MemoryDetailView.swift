import SwiftUI
import SwiftData
import RecallCore

struct MemoryDetailView: View {
    let memoryID: UUID

    @Query private var memories: [MemoryItem]

    init(memoryID: UUID) {
        self.memoryID = memoryID
        _memories = Query(filter: #Predicate<MemoryItem> { $0.id == memoryID })
    }

    var body: some View {
        if let memory = memories.first {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(memory.title ?? "Untitled memory")
                        .font(.title.bold())

                    if let summary = memory.summary {
                        GroupBox("Summary") {
                            Text(summary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    if let extractedText = memory.extractedText, !extractedText.isEmpty {
                        GroupBox("Extracted text") {
                            Text(extractedText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    if !memory.tags.isEmpty {
                        GroupBox("Tags") {
                            Text(memory.tags.joined(separator: ", "))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    GroupBox("Details") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Type: \(memory.contentType.rawValue)")
                            Text("Source: \(memory.source.rawValue)")
                            Text("Status: \(memory.processingStatus.rawValue)")
                            if let sourceURL = memory.sourceURL {
                                Link(sourceURL.absoluteString, destination: sourceURL)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
            }
            .navigationTitle("Memory")
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("Memory not found", systemImage: "questionmark.folder")
        }
    }
}
