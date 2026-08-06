import SwiftUI
import SwiftData
import UIKit
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
    @State private var mediaImage: UIImage?

    init(memoryID: UUID) {
        self.memoryID = memoryID
        _memories = Query(filter: #Predicate<MemoryItem> { $0.id == memoryID })
    }

    var body: some View {
        if let memory = memories.first {
            let metadataDirty = isMetadataDirty(for: memory)

            ZStack {
                PastelMeshBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            Button {
                                dismiss()
                            } label: {
                                Image(systemName: "chevron.left")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(RecallTheme.ink)
                                    .frame(width: 40, height: 40)
                                    .background(Color.white.opacity(0.75), in: Circle())
                            }
                            .accessibilityLabel("Back")

                            Spacer()

                            if metadataDirty {
                                Button {
                                    saveMetadata(for: memory)
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "square.and.arrow.down")
                                            .font(.caption.weight(.bold))
                                        Text("Save")
                                            .font(.subheadline.weight(.semibold))
                                    }
                                }
                                .buttonStyle(RecallSecondaryButtonStyle())
                            }

                            Button {
                                showingDeleteConfirmation = true
                            } label: {
                                Image(systemName: "trash")
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(RecallTheme.danger)
                                    .frame(width: 40, height: 40)
                                    .background(Color.white.opacity(0.75), in: Circle())
                            }
                            .accessibilityLabel("Delete")
                        }
                        .padding(.top, 8)

                        VStack(alignment: .leading, spacing: 12) {
                            TextField("Title", text: $editableTitle, axis: .vertical)
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                                .foregroundStyle(RecallTheme.ink)
                                .lineLimit(1...4)
                                .textInputAutocapitalization(.sentences)
                                .onSubmit {
                                    if metadataDirty {
                                        saveMetadata(for: memory)
                                    }
                                }

                            Text(memory.createdAt.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundStyle(RecallTheme.inkSoft)
                        }
                        .glassCard()

                        if let mediaImage {
                            Image(uiImage: mediaImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                                .shadow(color: Color.black.opacity(0.08), radius: 12, y: 6)
                                .accessibilityLabel("Memory photo")
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            SectionLabel(text: "Summary")
                            TextField("Add a short summary", text: $editableSummary, axis: .vertical)
                                .font(.body)
                                .foregroundStyle(RecallTheme.ink)
                                .lineLimit(3...12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .glassCard()

                        if metadataDirty {
                            Button("Save title & summary") {
                                saveMetadata(for: memory)
                            }
                            .buttonStyle(RecallPrimaryButtonStyle())
                        }

                        if let extractedText = memory.extractedText, !extractedText.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                SectionLabel(text: "Extracted text")
                                Text(extractedText)
                                    .font(.subheadline)
                                    .foregroundStyle(RecallTheme.ink)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .glassCard()
                        }

                        TagEditorSection(tags: $editableTags) { tags in
                            saveTags(tags, for: memory)
                        }

                        if let editStatus {
                            Text(editStatus)
                                .font(.footnote)
                                .foregroundStyle(RecallTheme.inkMuted)
                                .padding(.horizontal, 4)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            SectionLabel(text: "Details")
                            detailRow("Type", memory.contentType.rawValue.capitalized)
                            detailRow("Source", memory.source.rawValue.capitalized)
                            detailRow("Status", memory.processingStatus.rawValue.capitalized)
                            if let sourceURL = memory.sourceURL {
                                Link(sourceURL.absoluteString, destination: sourceURL)
                                    .font(.footnote)
                                    .foregroundStyle(RecallTheme.ink)
                                    .lineLimit(2)
                                    .truncationMode(.middle)
                            }
                        }
                        .glassCard()

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
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
                mediaImage = Self.loadMediaImage(for: memory)
            }
            .onChange(of: memory.mediaRelativePath) { _, _ in
                mediaImage = Self.loadMediaImage(for: memory)
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
            ZStack {
                PastelMeshBackground()
                ContentUnavailableView("Memory not found", systemImage: "questionmark.folder")
            }
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(RecallTheme.inkMuted)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(RecallTheme.ink)
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

    private static func loadMediaImage(for memory: MemoryItem) -> UIImage? {
        guard let relativePath = memory.mediaRelativePath,
              let mediaDirectory = AppGroupPaths.shared.mediaDirectory
        else {
            return nil
        }

        let fileURL = mediaDirectory.appendingPathComponent(relativePath)
        let ext = fileURL.pathExtension.lowercased()
        let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "webp", "gif"]
        guard imageExtensions.contains(ext) else { return nil }

        return UIImage(contentsOfFile: fileURL.path)
    }
}
