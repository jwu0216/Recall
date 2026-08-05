import SwiftUI
import SwiftData
import RecallCore

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<ProcessingJob> { $0.statusRaw == "pending" }) private var pendingJobs: [ProcessingJob]
    @Query(filter: #Predicate<ProcessingJob> { $0.statusRaw == "failed" }) private var failedJobs: [ProcessingJob]
    @Query private var memories: [MemoryItem]

    @State private var apiKey = APIKeyStore.load() ?? ""
    @State private var statusMessage: String?
    @State private var isProcessing = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("sk-…", text: $apiKey)
                    Button("Save API Key") {
                        do {
                            try APIKeyStore.save(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
                            statusMessage = "API key saved to Keychain."
                        } catch {
                            statusMessage = error.localizedDescription
                        }
                    }
                } header: {
                    Text("OpenAI (dev mode)")
                } footer: {
                    Text("Your key stays on this device. Subscriptions come later for public launch.")
                }

                Section("Library") {
                    LabeledContent("Memories", value: "\(memories.count)")
                    LabeledContent("Pending tags", value: "\(pendingJobs.count)")
                    LabeledContent("Failed", value: "\(failedJobs.count)")
                    Button(isProcessing ? "Processing…" : "Process pending now") {
                        Task { await processPending() }
                    }
                    .disabled(isProcessing || pendingJobs.isEmpty || apiKey.isEmpty)
                }

                Section {
                    LabeledContent("Photo library", value: "V2 — Coming soon")
                } header: {
                    Text("Future")
                } footer: {
                    Text("When Photos arrives: opt-in only, low-detail vision, OCR first, cost estimate before indexing, pause anytime. See PRODUCT.md.")
                }

                Section("About") {
                    Text("Recall V1: Share from any app, then ask in plain English. Designed so you’ll be proud to show people — not a dump of half-finished features.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let statusMessage {
                    Section {
                        Text(statusMessage)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func processPending() async {
        guard let key = APIKeyStore.load(), !key.isEmpty else {
            statusMessage = RecallStoreError.missingAPIKey.localizedDescription
            return
        }
        isProcessing = true
        defer { isProcessing = false }
        let service = OpenAIService(configuration: OpenAIConfiguration(apiKey: key))
        await MemoryProcessor(aiService: service).processPendingJobs(modelContext: modelContext)
        statusMessage = "Finished processing queue."
    }
}
