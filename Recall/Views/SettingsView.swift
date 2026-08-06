import SwiftUI
import SwiftData
import RecallCore

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<ProcessingJob> { $0.statusRaw == "pending" }) private var pendingJobs: [ProcessingJob]
    @Query(filter: #Predicate<ProcessingJob> { $0.statusRaw == "failed" }) private var failedJobs: [ProcessingJob]
    @Query private var memories: [MemoryItem]

    @State private var apiKey = APIKeyStore.load() ?? ""
    @State private var apiKeyStatus: String?
    @State private var libraryStatus: String?
    @State private var isProcessing = false
    @State private var isValidatingKey = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("sk-…", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .disabled(isValidatingKey)

                    Button(isValidatingKey ? "Checking…" : "Save API Key") {
                        Task { await saveAPIKey() }
                    }
                    .disabled(isValidatingKey || apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } header: {
                    Text("OpenAI (dev mode)")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your key stays on this device. Subscriptions come later for public launch.")
                        if let apiKeyStatus {
                            Text(apiKeyStatus)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    LabeledContent("Memories", value: "\(memories.count)")
                    LabeledContent("Pending tags", value: "\(pendingJobs.count)")
                    LabeledContent("Failed", value: "\(failedJobs.count)")
                    Button(isProcessing ? "Processing…" : "Process pending now") {
                        Task { await processPending() }
                    }
                    .disabled(isProcessing || pendingJobs.isEmpty || apiKey.isEmpty)

                    Button(isProcessing ? "Refreshing…" : "Refresh search index") {
                        Task { await rebuildSearchIndex() }
                    }
                    .disabled(isProcessing || memories.isEmpty || apiKey.isEmpty)
                } header: {
                    Text("Library")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Refresh rebuilds embeddings for Ask. Memories you’ve edited keep their title, summary, and tags.")
                        if let libraryStatus {
                            Text(libraryStatus)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    LabeledContent("Photo library", value: "V2 — Coming soon")
                } header: {
                    Text("Future")
                } footer: {
                    Text("When Photos arrives: opt-in only, low-detail vision, OCR first, cost estimate before indexing, pause anytime. See PRODUCT.md.")
                }

                Section("About") {
                    Text("Recall V1: Add memories manually or via Share, then ask in plain English.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func saveAPIKey() async {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            apiKeyStatus = "Enter an API key first."
            return
        }

        isValidatingKey = true
        apiKeyStatus = "Checking key…"
        defer { isValidatingKey = false }

        do {
            let service = OpenAIService(configuration: OpenAIConfiguration(apiKey: key))
            try await service.validateAPIKey()
            try APIKeyStore.save(key)
            apiKey = key
            apiKeyStatus = "API key saved."
        } catch {
            // Keep any previously saved key; only reject this new value.
            apiKeyStatus = error.localizedDescription
        }
    }

    private func processPending() async {
        guard let key = APIKeyStore.load(), !key.isEmpty else {
            libraryStatus = RecallStoreError.missingAPIKey.localizedDescription
            return
        }
        isProcessing = true
        defer { isProcessing = false }
        let service = OpenAIService(configuration: OpenAIConfiguration(apiKey: key))
        await MemoryProcessor(aiService: service).processPendingJobs(modelContext: modelContext)
        libraryStatus = "Finished processing queue."
    }

    private func rebuildSearchIndex() async {
        guard let key = APIKeyStore.load(), !key.isEmpty else {
            libraryStatus = RecallStoreError.missingAPIKey.localizedDescription
            return
        }
        isProcessing = true
        defer { isProcessing = false }
        do {
            let service = OpenAIService(configuration: OpenAIConfiguration(apiKey: key))
            let count = try await MemoryProcessor(aiService: service).reindexEmbeddings(modelContext: modelContext)
            libraryStatus = "Refreshed search index for \(count) memories."
        } catch {
            libraryStatus = error.localizedDescription
        }
    }
}
