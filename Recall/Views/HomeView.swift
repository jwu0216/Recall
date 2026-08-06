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
    @State private var isGeneratingAnswer = false
    @State private var answerOpacity: Double = 0
    @State private var askGeneration = 0
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
                            if isProcessing {
                                ProgressView()
                            }
                            Text(pendingJobsMessage)
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

                    if memories.isEmpty && answer.isEmpty && !isSearching {
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

                    if isGeneratingAnswer {
                        GroupBox("Answer") {
                            ProgressView()
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .transition(.opacity)
                    } else if !answer.isEmpty {
                        GroupBox("Answer") {
                            Text(answerAttributed)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .opacity(answerOpacity)
                                .textSelection(.enabled)
                        }
                        .transition(.opacity.combined(with: .offset(y: 6)))
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
                        .transition(.opacity.combined(with: .offset(y: 8)))
                    } else if !answer.isEmpty && !isGeneratingAnswer {
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
                .animation(.easeOut(duration: 0.35), value: citedResults.map(\.id))
                .animation(.easeOut(duration: 0.35), value: isGeneratingAnswer)
                .animation(.easeOut(duration: 0.45), value: answerOpacity)
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
            .onReceive(NotificationCenter.default.publisher(for: RecallConstants.storeNeedsRefreshNotification)) { _ in
                // Processing already ran in RecallApp; just clear a stale banner if needed.
                if pendingJobs.isEmpty {
                    statusBanner = nil
                }
            }
        }
    }

    private func askRecall() async {
        askGeneration += 1
        let generation = askGeneration

        isSearching = true
        isGeneratingAnswer = false
        errorMessage = nil
        answer = ""
        answerOpacity = 0
        citedResults = []
        defer {
            if generation == askGeneration {
                isSearching = false
            }
        }

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
            guard generation == askGeneration else { return }

            let results = VectorSearchService.relevantMatches(
                query: question,
                queryEmbedding: queryEmbedding,
                in: readyMemories.isEmpty ? memories : readyMemories
            )

            // Show matches immediately while the answer is still loading.
            withAnimation(.easeOut(duration: 0.35)) {
                citedResults = results
            }

            if results.isEmpty {
                await presentAnswer("I couldn't find that in your saved memories yet.", generation: generation)
                return
            }

            withAnimation(.easeOut(duration: 0.25)) {
                isGeneratingAnswer = true
            }

            let matchedItems = results.map(\.item)
            let response = try await service.chat(
                system: """
                You are Recall, a personal memory assistant for the user's private notes.
                Answer briefly from the matched memories. Mention the memory title.
                Use plain text only — never Markdown links like [here](url).
                """,
                messages: [ChatTurn(role: "user", content: question)],
                context: matchedItems
            )
            guard generation == askGeneration else { return }

            // Search already found matches — never show a false "not found" from the model.
            let finalAnswer = looksLikeNotFound(response)
                ? groundedAnswer(for: question, from: matchedItems)
                : Self.sanitizeAnswer(response)
            await presentAnswer(finalAnswer, generation: generation)
        } catch {
            guard generation == askGeneration else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                isGeneratingAnswer = false
            }
            errorMessage = error.localizedDescription
        }
    }

    private var answerAttributed: AttributedString {
        if let markdown = try? AttributedString(
            markdown: answer,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return markdown
        }
        return AttributedString(answer)
    }

    /// Fades the answer in and reveals it in short word bursts, similar to AI overview UIs.
    private func presentAnswer(_ fullText: String, generation: Int) async {
        guard generation == askGeneration else { return }

        let text = Self.sanitizeAnswer(fullText)

        withAnimation(.easeOut(duration: 0.2)) {
            isGeneratingAnswer = false
            answer = ""
            answerOpacity = 0
        }

        let words = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        var assembled = ""

        withAnimation(.easeOut(duration: 0.45)) {
            answerOpacity = 1
        }

        for batchStart in stride(from: 0, to: words.count, by: 2) {
            guard generation == askGeneration else { return }
            let end = min(batchStart + 2, words.count)
            let batch = words[batchStart..<end].joined(separator: " ")
            if !assembled.isEmpty { assembled += " " }
            assembled += batch
            answer = assembled
            try? await Task.sleep(for: .milliseconds(28))
        }

        guard generation == askGeneration else { return }
        answer = text
        answerOpacity = 1
    }

    /// Turn `[label](url)` into readable plain text before display.
    private static func sanitizeAnswer(_ text: String) -> String {
        let pattern = #"\[([^\]]+)\]\(([^)]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }

        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        var result = text
        let matches = regex.matches(in: text, range: nsRange).reversed()
        for match in matches {
            guard
                let labelRange = Range(match.range(at: 1), in: result),
                let urlRange = Range(match.range(at: 2), in: result),
                let fullRange = Range(match.range, in: result)
            else { continue }

            let label = String(result[labelRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let url = String(result[urlRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let genericLabels: Set<String> = ["here", "this", "link", "page", "url", "site"]
            let replacement = genericLabels.contains(label.lowercased())
                ? url
                : "\(label) (\(url))"
            result.replaceSubrange(fullRange, with: replacement)
        }
        return result
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

    private var hasAPIKey: Bool {
        !(APIKeyStore.load() ?? "").isEmpty
    }

    private var pendingJobsMessage: String {
        if isProcessing {
            return "Tagging \(pendingJobs.count) saved item(s)…"
        }
        if !hasAPIKey {
            return "\(pendingJobs.count) item(s) waiting to be tagged. Add your API key in Settings, then pull to refresh."
        }
        return "\(pendingJobs.count) item(s) waiting to be tagged. Pull to refresh to finish."
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
