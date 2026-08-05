import SwiftUI
import SwiftData
import RecallCore

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MemoryItem.createdAt, order: .reverse) private var memories: [MemoryItem]
    @Query(
        filter: #Predicate<ProcessingJob> { $0.statusRaw == "pending" },
        sort: \ProcessingJob.createdAt
    ) private var pendingJobs: [ProcessingJob]

    @State private var question = ""
    @State private var answer = ""
    @State private var citedResults: [MemorySearchResult] = []
    @State private var isSearching = false
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var statusBanner: String?
    @State private var showingAddMemory = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let statusBanner {
                        Text(statusBanner)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    }

                    if !pendingJobs.isEmpty {
                        HStack {
                            ProgressView()
                            Text(isProcessing
                                  ? "Tagging \(pendingJobs.count) saved item(s)…"
                                  : "\(pendingJobs.count) item(s) waiting to be tagged. Open Settings for your API key, then pull to refresh.")
                                .font(.footnote)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("What are you trying to recall?")
                            .font(.title2.bold())

                        TextField("chicken wings recipe, blue jacket, tax thing...", text: $question, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(1...4)

                        Button(isSearching ? "Searching..." : "Ask Recall") {
                            Task { await askRecall() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
                    }

                    if memories.isEmpty && answer.isEmpty {
                        GroupBox("How to get started") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("1. Add your OpenAI API key in Settings")
                                Text("2. Tap + to add a note, or Share → Recall from another app")
                                Text("3. Ask for what you saved")
                            }
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Button("Add a memory") {
                                showingAddMemory = true
                            }
                            .buttonStyle(.bordered)
                            .padding(.top, 4)
                        }
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
                    } else if !answer.isEmpty {
                        Text("No strong matches — try different words, or add another memory.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    GroupBox("Recent") {
                        if memories.isEmpty {
                            Text("Nothing saved yet. Tap + to add something, or Share from another app.")
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
                            .font(.footnote)
                    }
                }
                .padding()
            }
            .navigationTitle("Recall")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddMemory = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add memory")
                }
            }
            .sheet(isPresented: $showingAddMemory) {
                AddMemoryView()
            }
            .refreshable {
                await processPendingJobsIfNeeded()
            }
            .task {
                await processPendingJobsIfNeeded()
            }
        }
    }

    private func askRecall() async {
        isSearching = true
        errorMessage = nil
        answer = ""
        citedResults = []
        defer { isSearching = false }

        let readyMemories = memories.filter { $0.processingStatus == .ready || $0.embedding != nil }

        guard !memories.isEmpty else {
            errorMessage = "Add a memory first (tap +), then ask again."
            return
        }

        guard let apiKey = APIKeyStore.load(), !apiKey.isEmpty else {
            errorMessage = RecallStoreError.missingAPIKey.localizedDescription
            return
        }

        let service = OpenAIService(configuration: OpenAIConfiguration(apiKey: apiKey))

        do {
            let queryEmbedding = try await service.embed(question)
            let results = VectorSearchService.relevantMatches(
                query: question,
                queryEmbedding: queryEmbedding,
                in: readyMemories.isEmpty ? memories : readyMemories
            )

            citedResults = results

            if results.isEmpty {
                answer = "I couldn't find that in your saved memories yet."
                return
            }

            let matchedItems = results.map(\.item)
            let response = try await service.chat(
                system: """
                You are Recall, a personal memory assistant for the user's private notes.
                Answer briefly from the matched memories. Mention the memory title.
                """,
                messages: [ChatTurn(role: "user", content: question)],
                context: matchedItems
            )

            // Search already found matches — never show a false "not found" from the model.
            if looksLikeNotFound(response) {
                answer = groundedAnswer(for: question, from: matchedItems)
            } else {
                answer = response
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func looksLikeNotFound(_ text: String) -> Bool {
        let lower = text.lowercased()
        let phrases = [
            "could not find",
            "couldn't find",
            "couldn’t find",
            "no matching",
            "don't have anything",
            "do not have anything",
            "wasn't able to find",
            "was not able to find",
            "no memories",
            "nothing in your"
        ]
        return phrases.contains { lower.contains($0) }
    }

    private func groundedAnswer(for question: String, from items: [MemoryItemSnapshot]) -> String {
        guard let top = items.first else {
            return "I couldn't find that in your saved memories yet."
        }

        let title = top.title ?? "Untitled memory"
        if let summary = top.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
            return "From your memory “\(title)”: \(summary)"
        }
        if let text = top.extractedText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            let snippet = text.count > 180 ? String(text.prefix(180)) + "…" : text
            return "From your memory “\(title)”: \(snippet)"
        }
        return "I found a matching memory: “\(title)”."
    }

    private func processPendingJobsIfNeeded() async {
        guard let apiKey = APIKeyStore.load(), !apiKey.isEmpty else {
            if !pendingJobs.isEmpty {
                statusBanner = "Add an OpenAI API key in Settings to finish tagging shared items."
            }
            return
        }

        guard !pendingJobs.isEmpty else {
            statusBanner = nil
            return
        }

        isProcessing = true
        statusBanner = "Tagging saved items…"
        defer { isProcessing = false }

        let service = OpenAIService(configuration: OpenAIConfiguration(apiKey: apiKey))
        let processor = MemoryProcessor(aiService: service)
        await processor.processPendingJobs(modelContext: modelContext)
        statusBanner = pendingJobs.isEmpty ? "All caught up." : nil
    }
}
