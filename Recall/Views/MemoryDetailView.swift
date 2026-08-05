import SwiftUI
import SwiftData
import RecallCore

struct MemoryDetailView: View {
    let memoryID: UUID

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var memories: [MemoryItem]
    @State private var showingDeleteConfirmation = false
    @State private var editableTitle = ""
    @State private var editableSummary = ""
    @State private var editableTags: [String] = []
    @State private var editStatus: String?

    init(memoryID: UUID) {
        self.memoryID = memoryID
        _memories = Query(filter: #Predicate<MemoryItem> { $0.id == memoryID })
    }

    var body: some View {
        if let memory = memories.first {
            let metadataDirty = isMetadataDirty(for: memory)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TextField("Title", text: $editableTitle, axis: .vertical)
                        .font(.title.bold())
                        .lineLimit(1...4)
                        .textInputAutocapitalization(.sentences)
                        .onSubmit {
                            if metadataDirty {
                                saveMetadata(for: memory)
                            }
                        }

                    GroupBox("Summary") {
                        TextField("Add a short summary", text: $editableSummary, axis: .vertical)
                            .lineLimit(3...12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if metadataDirty {
                        Button("Save title & summary") {
                            saveMetadata(for: memory)
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    if let extractedText = memory.extractedText, !extractedText.isEmpty {
                        GroupBox("Extracted text") {
                            Text(extractedText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    TagEditorSection(tags: $editableTags) { tags in
                        saveTags(tags, for: memory)
                    }

                    if let editStatus {
                        Text(editStatus)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    GroupBox("Details") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Type: \(memory.contentType.rawValue)")
                            Text("Source: \(memory.source.rawValue)")
                            Text("Status: \(memory.processingStatus.rawValue)")
                            if let sourceURL = memory.sourceURL {
                                Link(sourceURL.absoluteString, destination: sourceURL)
                                    .lineLimit(2)
                                    .truncationMode(.middle)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .navigationTitle("Memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    if metadataDirty {
                        Button("Save") {
                            saveMetadata(for: memory)
                        }
                    }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button("Delete", role: .destructive) {
                        showingDeleteConfirmation = true
                    }
                }
            }
            .confirmationDialog(
                "Delete this memory?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Memory", role: .destructive) {
                    delete(memory)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This can’t be undone.")
            }
            .onAppear {
                syncEditors(from: memory)
            }
            .onChange(of: memory.title) { oldTitle, newTitle in
                if normalized(editableTitle) == normalized(oldTitle ?? "") {
                    editableTitle = newTitle ?? ""
                }
            }
            .onChange(of: memory.summary) { oldSummary, newSummary in
                if normalized(editableSummary) == normalized(oldSummary ?? "") {
                    editableSummary = newSummary ?? ""
                }
            }
            .onChange(of: memory.tags) { _, newTags in
                if newTags != editableTags {
                    editableTags = newTags
                }
            }
        } else {
            ContentUnavailableView("Memory not found", systemImage: "questionmark.folder")
        }
    }

    private func syncEditors(from memory: MemoryItem) {
        editableTitle = memory.title ?? ""
        editableSummary = memory.summary ?? ""
        editableTags = memory.tags
    }

    private func isMetadataDirty(for memory: MemoryItem) -> Bool {
        normalized(editableTitle) != normalized(memory.title ?? "")
            || normalized(editableSummary) != normalized(memory.summary ?? "")
    }

    private func saveMetadata(for memory: MemoryItem) {
        let title = normalized(editableTitle)
        let summary = normalized(editableSummary)

        memory.title = title.isEmpty ? nil : title
        memory.summary = summary.isEmpty ? nil : summary
        memory.userEditedLabels = true
        memory.updatedAt = .now

        editableTitle = memory.title ?? ""
        editableSummary = memory.summary ?? ""

        do {
            try modelContext.save()
            editStatus = "Saved."
            Task { await reembed(memory, successMessage: "Saved and search index updated.") }
        } catch {
            editStatus = error.localizedDescription
        }
    }

    private func saveTags(_ tags: [String], for memory: MemoryItem) {
        memory.tags = tags
        memory.userEditedLabels = true
        memory.updatedAt = .now
        do {
            try modelContext.save()
            editStatus = "Tags saved."
            Task { await reembed(memory, successMessage: "Tags saved and search index updated.") }
        } catch {
            editStatus = error.localizedDescription
        }
    }

    private func reembed(_ memory: MemoryItem, successMessage: String) async {
        guard let apiKey = APIKeyStore.load(), !apiKey.isEmpty else {
            await MainActor.run {
                editStatus = "Saved. Add an API key to update search matching."
            }
            return
        }

        let embedText = [
            memory.title,
            memory.summary,
            memory.extractedText,
            memory.sourceURL?.host,
            memory.sourceURL?.absoluteString,
            memory.tags.joined(separator: " ")
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        guard !embedText.isEmpty else { return }

        do {
            let service = OpenAIService(configuration: OpenAIConfiguration(apiKey: apiKey))
            let embedding = try await service.embed(embedText)
            await MainActor.run {
                memory.embedding = embedding
                memory.lastIndexedAt = .now
                memory.updatedAt = .now
                try? modelContext.save()
                editStatus = successMessage
            }
        } catch {
            await MainActor.run {
                editStatus = "Saved, but search index update failed."
            }
        }
    }

    private func delete(_ memory: MemoryItem) {
        do {
            try MemoryDeletion.delete(memory, modelContext: modelContext)
            dismiss()
        } catch {
            // Keep the detail screen up if save fails; user can retry.
        }
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
