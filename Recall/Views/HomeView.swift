import SwiftUI
import SwiftData
import RecallCore

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MemoryItem.createdAt, order: .reverse) private var memories: [MemoryItem]

    @State private var question = ""
    @State private var answer = ""
    @State private var citedResults: [MemorySearchResult] = []
    @State private var isSearching = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What are you trying to recall?")
                            .font(.title2.bold())

                        TextField("chicken wings recipe, blue jacket, tax thing...", text: $question, axis: .vertical)
                            .textFieldStyle(.roundedBorder)

                        Button(isSearching ? "Searching..." : "Ask Recall") {
                            Task { await askRecall() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
                    }

                    if !answer.isEmpty {
                        GroupBox("Answer") {
                            Text(answer)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    if !citedResults.isEmpty {
                        GroupBox("Matching memories") {
                            VStack(spacing: 12) {
                                ForEach(citedResults) { result in
                                    NavigationLink {
                                        MemoryDetailView(memoryID: result.item.id)
                                    } label: {
                                        MemoryRowView(snapshot: result.item, score: result.score)
                                    }
                                }
                            }
                        }
                    }

                    GroupBox("Recent") {
                        if memories.isEmpty {
                            Text("Save links, photos, and notes to Recall from the Share sheet.")
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 12) {
                                ForEach(memories.prefix(5), id: \.id) { memory in
                                    NavigationLink {
                                        MemoryDetailView(memoryID: memory.id)
                                    } label: {
                                        MemoryRowView(snapshot: memory.snapshot(), score: nil)
                                    }
                                }
                            }
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
                .padding()
            }
            .navigationTitle("Recall")
            .task {
                await processPendingJobsIfNeeded()
            }
        }
    }

    private func askRecall() async {
        isSearching = true
        errorMessage = nil
        defer { isSearching = false }

        guard let apiKey = APIKeyStore.load(), !apiKey.isEmpty else {
            errorMessage = RecallStoreError.missingAPIKey.localizedDescription
            return
        }

        let service = OpenAIService(configuration: OpenAIConfiguration(apiKey: apiKey))

        do {
            let queryEmbedding = try await service.embed(question)
            var results = VectorSearchService.search(queryEmbedding: queryEmbedding, in: memories)

            if results.isEmpty {
                results = VectorSearchService.keywordFallback(query: question, in: memories)
            }

            citedResults = results

            let response = try await service.chat(
                system: "You are Recall, a personal memory assistant. Answer using only the provided memories. Cite memory titles when helpful. If nothing matches, say you could not find it.",
                messages: [ChatTurn(role: "user", content: question)],
                context: results.map(\.item)
            )

            answer = response
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func processPendingJobsIfNeeded() async {
        guard let apiKey = APIKeyStore.load(), !apiKey.isEmpty else { return }
        let service = OpenAIService(configuration: OpenAIConfiguration(apiKey: apiKey))
        let processor = MemoryProcessor(aiService: service)
        await processor.processPendingJobs(modelContext: modelContext)
    }
}
