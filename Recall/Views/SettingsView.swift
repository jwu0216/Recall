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
            ZStack {
                PastelMeshBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel(text: "Settings")
                            Text("Preferences")
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                .foregroundStyle(RecallTheme.ink)
                        }
                        .padding(.top, 8)

                        VStack(alignment: .leading, spacing: 12) {
                            SectionLabel(text: "OpenAI (dev mode)")
                            SecureField("sk-…", text: $apiKey)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .disabled(isValidatingKey)
                                .padding(14)
                                .background(
                                    RoundedRectangle(cornerRadius: RecallTheme.controlRadius, style: .continuous)
                                        .fill(Color.white.opacity(0.7))
                                )

                            Button(isValidatingKey ? "Checking…" : "Save API Key") {
                                Task { await saveAPIKey() }
                            }
                            .buttonStyle(RecallPrimaryButtonStyle(
                                isEnabled: !isValidatingKey && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ))
                            .disabled(isValidatingKey || apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                            Text("Your key stays on this device. Subscriptions come later for public launch.")
                                .font(.footnote)
                                .foregroundStyle(RecallTheme.inkMuted)

                            if let apiKeyStatus {
                                Text(apiKeyStatus)
                                    .font(.footnote)
                                    .foregroundStyle(RecallTheme.inkMuted)
                            }
                        }
                        .glassCard()

                        VStack(alignment: .leading, spacing: 12) {
                            SectionLabel(text: "Library")
                            statRow("Memories", "\(memories.count)")
                            statRow("Pending tags", "\(pendingJobs.count)")
                            statRow("Failed", "\(failedJobs.count)")

                            Button(isProcessing ? "Processing…" : "Process pending now") {
                                Task { await processPending() }
                            }
                            .buttonStyle(RecallSecondaryButtonStyle())
                            .disabled(isProcessing || pendingJobs.isEmpty || apiKey.isEmpty)

                            Button(isProcessing ? "Refreshing…" : "Refresh search index") {
                                Task { await rebuildSearchIndex() }
                            }
                            .buttonStyle(RecallSecondaryButtonStyle())
                            .disabled(isProcessing || memories.isEmpty || apiKey.isEmpty)

                            Text("Refresh rebuilds embeddings for search. Edited notes keep their title, summary, and tags.")
                                .font(.footnote)
                                .foregroundStyle(RecallTheme.inkMuted)

                            if let libraryStatus {
                                Text(libraryStatus)
                                    .font(.footnote)
                                    .foregroundStyle(RecallTheme.inkMuted)
                            }
                        }
                        .glassCard()

                        VStack(alignment: .leading, spacing: 10) {
                            SectionLabel(text: "Future")
                            Text("Photo library")
                                .font(.headline)
                                .foregroundStyle(RecallTheme.ink)
                            Text("V2 — Coming soon. Opt-in only, OCR first, pause anytime.")
                                .font(.subheadline)
                                .foregroundStyle(RecallTheme.inkMuted)
                        }
                        .glassCard()

                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel(text: "About")
                            Text("Recall V1: Add notes manually or via Share, then find them in plain English.")
                                .font(.footnote)
                                .foregroundStyle(RecallTheme.inkMuted)
                        }
                        .glassCard()

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(RecallTheme.inkMuted)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(RecallTheme.ink)
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
