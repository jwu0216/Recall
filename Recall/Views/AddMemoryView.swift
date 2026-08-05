import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers
import UIKit
import RecallCore

private struct ImportedImageData: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in
            ImportedImageData(data: data)
        }
    }
}

struct AddMemoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var note = ""
    @State private var linkText = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var importedPDFURL: URL?
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showPDFImporter = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What do you want to remember?", text: $note, axis: .vertical)
                        .lineLimit(4...12)
                } header: {
                    Text("Note")
                } footer: {
                    Text("Paste a thought, recipe, reminder, or anything you’d want to find later.")
                }

                Section {
                    TextField("https://…", text: $linkText)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                } header: {
                    Text("Link (optional)")
                }

                Section("Attachment (optional)") {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label(
                            selectedImageData == nil ? "Add photo" : "Photo selected",
                            systemImage: selectedImageData == nil ? "photo" : "checkmark.circle.fill"
                        )
                    }
                    .onChange(of: selectedPhoto) { _, item in
                        Task { await loadPhoto(item) }
                    }

                    if selectedImageData != nil {
                        Button("Remove photo", role: .destructive) {
                            selectedPhoto = nil
                            selectedImageData = nil
                        }
                    }

                    Button {
                        showPDFImporter = true
                    } label: {
                        Label(
                            importedPDFURL == nil ? "Add PDF" : "PDF selected",
                            systemImage: importedPDFURL == nil ? "doc.richtext" : "checkmark.circle.fill"
                        )
                    }

                    if importedPDFURL != nil {
                        Button("Remove PDF", role: .destructive) {
                            importedPDFURL = nil
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("Add Memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") {
                        Task { await save() }
                    }
                    .disabled(!canSave || isSaving)
                }
            }
            .fileImporter(
                isPresented: $showPDFImporter,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    importedPDFURL = urls.first
                    // Prefer one attachment at a time.
                    if importedPDFURL != nil {
                        selectedPhoto = nil
                        selectedImageData = nil
                    }
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private var trimmedNote: String {
        note.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var parsedURL: URL? {
        let raw = linkText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        if let url = URL(string: raw), url.scheme != nil {
            return url
        }
        return URL(string: "https://\(raw)")
    }

    private var canSave: Bool {
        !trimmedNote.isEmpty || parsedURL != nil || selectedImageData != nil || importedPDFURL != nil
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else {
            selectedImageData = nil
            return
        }
        do {
            let imported = try await item.loadTransferable(type: ImportedImageData.self)
            selectedImageData = imported?.data
            if selectedImageData != nil {
                importedPDFURL = nil
            }
        } catch {
            errorMessage = error.localizedDescription
            selectedImageData = nil
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            if let imageData = selectedImageData {
                let filename = try saveImageData(imageData)
                try ProcessingQueueService.enqueue(
                    contentType: .image,
                    source: .manual,
                    sourceURL: parsedURL,
                    note: trimmedNote.isEmpty ? nil : trimmedNote,
                    payloadFilename: filename,
                    modelContext: modelContext
                )
            } else if let pdfURL = importedPDFURL {
                let filename = try savePDF(from: pdfURL)
                try ProcessingQueueService.enqueue(
                    contentType: .pdf,
                    source: .manual,
                    sourceURL: parsedURL,
                    note: trimmedNote.isEmpty ? nil : trimmedNote,
                    payloadFilename: filename,
                    modelContext: modelContext
                )
            } else if let url = parsedURL {
                try ProcessingQueueService.enqueue(
                    contentType: .link,
                    source: .manual,
                    sourceURL: url,
                    note: trimmedNote.isEmpty ? nil : trimmedNote,
                    modelContext: modelContext
                )
            } else {
                try ProcessingQueueService.enqueue(
                    contentType: .text,
                    source: .manual,
                    note: trimmedNote,
                    modelContext: modelContext
                )
            }

            await processPendingIfPossible()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func processPendingIfPossible() async {
        guard let apiKey = APIKeyStore.load(), !apiKey.isEmpty else { return }
        let service = OpenAIService(configuration: OpenAIConfiguration(apiKey: apiKey))
        let processor = MemoryProcessor(aiService: service)
        await processor.processPendingJobs(modelContext: modelContext)
    }

    private func saveImageData(_ data: Data) throws -> String {
        guard let destination = AppGroupPaths.shared.uniqueMediaURL(fileExtension: "jpg") else {
            throw RecallStoreError.appGroupUnavailable
        }
        // Prefer JPEG compression when the picker returns a full image payload.
        if let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.8) {
            try jpeg.write(to: destination, options: .atomic)
        } else {
            try data.write(to: destination, options: .atomic)
        }
        return destination.lastPathComponent
    }

    private func savePDF(from url: URL) throws -> String {
        guard let destination = AppGroupPaths.shared.uniqueMediaURL(fileExtension: "pdf") else {
            throw RecallStoreError.appGroupUnavailable
        }
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        try FileManager.default.copyItem(at: url, to: destination)
        return destination.lastPathComponent
    }
}
