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
    @State private var didSave = false

    var body: some View {
        NavigationStack {
            ZStack {
                PastelMeshBackground()

                if didSave {
                    successState
                } else {
                    editorContent
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .fileImporter(
                isPresented: $showPDFImporter,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    importedPDFURL = urls.first
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

    private var editorContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
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
                    .disabled(isSaving)
                    .accessibilityLabel("Cancel")

                    Spacer()

                    SectionLabel(text: "Add note")

                    Spacer()

                    Button {
                        Task { await save() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.down")
                                .font(.caption.weight(.bold))
                            Text(isSaving ? "…" : "Save")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    .buttonStyle(RecallSecondaryButtonStyle())
                    .disabled(!canSave || isSaving)
                }
                .padding(.top, 8)

                VStack(alignment: .leading, spacing: 10) {
                    TextField("Title your thought…", text: $note, axis: .vertical)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(RecallTheme.ink)
                        .lineLimit(3...12)

                    Text("Paste a thought, recipe, reminder, or anything you’d want to find later.")
                        .font(.subheadline)
                        .foregroundStyle(RecallTheme.inkMuted)
                }
                .glassCard()

                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(text: "Link")
                    TextField("https://…", text: $linkText)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: RecallTheme.controlRadius, style: .continuous)
                                .fill(Color.white.opacity(0.7))
                        )
                }
                .glassCard()

                VStack(alignment: .leading, spacing: 14) {
                    SectionLabel(text: "Attachment")

                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        HStack {
                            Image(systemName: "photo")
                            Text(selectedImageData == nil ? "Add photo" : "Change photo")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(RecallTheme.inkSoft)
                        }
                        .foregroundStyle(RecallTheme.ink)
                        .font(.subheadline.weight(.medium))
                    }
                    .onChange(of: selectedPhoto) { _, item in
                        Task { await loadPhoto(item) }
                    }

                    if let imageData = selectedImageData, let preview = UIImage(data: imageData) {
                        Image(uiImage: preview)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 160)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .accessibilityLabel("Selected photo preview")

                        Button("Remove photo", role: .destructive) {
                            selectedPhoto = nil
                            selectedImageData = nil
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(RecallTheme.danger)
                    }

                    Button {
                        showPDFImporter = true
                    } label: {
                        HStack {
                            Image(systemName: importedPDFURL == nil ? "doc.richtext" : "checkmark.circle.fill")
                            Text(importedPDFURL == nil ? "Add PDF" : "PDF selected")
                            Spacer()
                        }
                        .foregroundStyle(RecallTheme.ink)
                        .font(.subheadline.weight(.medium))
                    }

                    if importedPDFURL != nil {
                        Button("Remove PDF", role: .destructive) {
                            importedPDFURL = nil
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(RecallTheme.danger)
                    }
                }
                .glassCard()

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(RecallTheme.danger)
                        .font(.footnote)
                }

                Button {
                    Task { await save() }
                } label: {
                    Text(isSaving ? "Saving…" : "Save note")
                }
                .buttonStyle(RecallPrimaryButtonStyle(isEnabled: canSave && !isSaving))
                .disabled(!canSave || isSaving)
                .padding(.top, 4)

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 20)
        }
    }

    private var successState: some View {
        VStack(spacing: 28) {
            Spacer()

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                RecallTheme.accentWarm.opacity(0.9),
                                RecallTheme.accent.opacity(0.55),
                                RecallTheme.accentCool.opacity(0.35),
                                .clear
                            ],
                            center: .center,
                            startRadius: 10,
                            endRadius: 120
                        )
                    )
                    .frame(width: 220, height: 220)
                    .blur(radius: 8)

                Circle()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: 96, height: 96)
                    .shadow(color: Color.black.opacity(0.08), radius: 16, y: 8)

                Image(systemName: "checkmark")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(RecallTheme.ink)
            }

            VStack(spacing: 8) {
                Text("Successfully Saved!")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(RecallTheme.ink)
                Text("Your note is ready whenever you need it.")
                    .font(.subheadline)
                    .foregroundStyle(RecallTheme.inkMuted)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Label("Back to Home", systemImage: "house.fill")
            }
            .buttonStyle(RecallPrimaryButtonStyle())
            .padding(.horizontal, 28)
            .padding(.bottom, 36)
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
            withAnimation(.easeOut(duration: 0.35)) {
                didSave = true
            }
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
