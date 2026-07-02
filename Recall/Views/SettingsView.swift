import SwiftUI
import RecallCore

struct SettingsView: View {
    @State private var apiKey = APIKeyStore.load() ?? ""
    @State private var statusMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("OpenAI") {
                    SecureField("API key", text: $apiKey)
                    Button("Save API Key") {
                        do {
                            try APIKeyStore.save(apiKey)
                            statusMessage = "API key saved to Keychain."
                        } catch {
                            statusMessage = error.localizedDescription
                        }
                    }
                }

                Section("Indexing") {
                    LabeledContent("Photo library", value: "Coming soon")
                    LabeledContent("Pending jobs", value: "Processed on app launch")
                }

                Section("About") {
                    Text("Recall saves links, images, PDFs, and text from Share, then lets you find them with natural language.")
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
}
