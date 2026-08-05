import UIKit
import UniformTypeIdentifiers
import SwiftData
import RecallCore

final class ShareViewController: UIViewController {
    private let titleLabel = UILabel()
    private let previewLabel = UILabel()
    private let statusLabel = UILabel()
    private let saveButton = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .medium)

    private var detectedSummary = "Looking at shared content…"
    private var isSaving = false

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground

        titleLabel.text = "Save to Recall"
        titleLabel.font = .preferredFont(forTextStyle: .title2)
        titleLabel.textAlignment = .center

        previewLabel.numberOfLines = 4
        previewLabel.textAlignment = .center
        previewLabel.textColor = .secondaryLabel
        previewLabel.font = .preferredFont(forTextStyle: .body)
        previewLabel.text = detectedSummary

        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.textColor = .secondaryLabel
        statusLabel.text = "Recall will tag this later when you open the app."

        saveButton.setTitle("Save", for: .normal)
        saveButton.titleLabel?.font = .boldSystemFont(ofSize: 17)
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)

        spinner.hidesWhenStopped = true

        let stack = UIStackView(arrangedSubviews: [
            titleLabel,
            previewLabel,
            statusLabel,
            spinner,
            saveButton
        ])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        Task { await inspectSharedContent() }
    }

    private func inspectSharedContent() async {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            previewLabel.text = "Nothing to save."
            saveButton.isEnabled = false
            return
        }

        var kinds: [String] = []

        for item in extensionItems {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let url = try? await loadURL(from: provider) {
                        kinds.append("Link: \(url.host ?? url.absoluteString)")
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    kinds.append("Image")
                } else if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
                    kinds.append("PDF")
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    if let text = try? await loadText(from: provider) {
                        let preview = String(text.prefix(100))
                        kinds.append("Text: \(preview)")
                    }
                }
            }
        }

        detectedSummary = kinds.isEmpty ? "Unsupported content." : kinds.joined(separator: "\n")
        previewLabel.text = detectedSummary
        saveButton.isEnabled = !kinds.isEmpty
    }

    @objc private func saveTapped() {
        guard !isSaving else { return }
        Task { await handleShare() }
    }

    @MainActor
    private func handleShare() async {
        isSaving = true
        saveButton.isEnabled = false
        spinner.startAnimating()
        statusLabel.text = "Saving…"

        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            finishWithError("No shared items found.")
            return
        }

        do {
            let container = try RecallModelContainerFactory.makeContainer()
            let context = ModelContext(container)
            var savedCount = 0

            for item in extensionItems {
                let attachments = item.attachments ?? []

                for provider in attachments {
                    if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                       let url = try await loadURL(from: provider) {
                        try ProcessingQueueService.enqueue(
                            contentType: .link,
                            sourceURL: url,
                            note: item.attributedContentText?.string,
                            modelContext: context
                        )
                        savedCount += 1
                    } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                              let text = try await loadText(from: provider) {
                        try ProcessingQueueService.enqueue(
                            contentType: .text,
                            note: text,
                            modelContext: context
                        )
                        savedCount += 1
                    } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
                              let filename = try await saveImage(from: provider) {
                        try ProcessingQueueService.enqueue(
                            contentType: .image,
                            note: item.attributedContentText?.string,
                            payloadFilename: filename,
                            modelContext: context
                        )
                        savedCount += 1
                    } else if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier),
                              let filename = try await savePDF(from: provider) {
                        try ProcessingQueueService.enqueue(
                            contentType: .pdf,
                            note: item.attributedContentText?.string,
                            payloadFilename: filename,
                            modelContext: context
                        )
                        savedCount += 1
                    }
                }
            }

            guard savedCount > 0 else {
                finishWithError("Could not save this content.")
                return
            }

            spinner.stopAnimating()
            statusLabel.text = savedCount == 1
                ? "Saved. Open Recall to finish tagging."
                : "Saved \(savedCount) items. Open Recall to finish tagging."
            saveButton.setTitle("Done", for: .normal)

            try await Task.sleep(nanoseconds: 700_000_000)
            extensionContext?.completeRequest(returningItems: nil)
        } catch {
            finishWithError(error.localizedDescription)
        }
    }

    private func loadURL(from provider: NSItemProvider) async throws -> URL? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                if let url = item as? URL {
                    continuation.resume(returning: url)
                } else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url)
                } else if let text = item as? String, let url = URL(string: text) {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func loadText(from provider: NSItemProvider) async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                if let text = item as? String {
                    continuation.resume(returning: text)
                } else if let data = item as? Data, let text = String(data: data, encoding: .utf8) {
                    continuation.resume(returning: text)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func saveImage(from provider: NSItemProvider) async throws -> String? {
        guard let mediaDirectory = AppGroupPaths.shared.mediaDirectory else {
            throw RecallStoreError.appGroupUnavailable
        }

        return try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                do {
                    let filename = "\(UUID().uuidString).jpg"
                    let destination = mediaDirectory.appendingPathComponent(filename)

                    if let url = item as? URL {
                        let data = try Data(contentsOf: url)
                        // Compress to keep Share extension memory under control
                        if let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.75) {
                            try jpeg.write(to: destination)
                        } else {
                            try data.write(to: destination)
                        }
                    } else if let image = item as? UIImage, let data = image.jpegData(compressionQuality: 0.75) {
                        try data.write(to: destination)
                    } else if let data = item as? Data {
                        if let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.75) {
                            try jpeg.write(to: destination)
                        } else {
                            try data.write(to: destination)
                        }
                    } else {
                        continuation.resume(returning: nil)
                        return
                    }

                    continuation.resume(returning: filename)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func savePDF(from provider: NSItemProvider) async throws -> String? {
        guard let mediaDirectory = AppGroupPaths.shared.mediaDirectory else {
            throw RecallStoreError.appGroupUnavailable
        }

        return try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.pdf.identifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                do {
                    let filename = "\(UUID().uuidString).pdf"
                    let destination = mediaDirectory.appendingPathComponent(filename)

                    if let url = item as? URL {
                        try FileManager.default.copyItem(at: url, to: destination)
                    } else if let data = item as? Data {
                        try data.write(to: destination)
                    } else {
                        continuation.resume(returning: nil)
                        return
                    }

                    continuation.resume(returning: filename)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func finishWithError(_ message: String) {
        spinner.stopAnimating()
        isSaving = false
        saveButton.isEnabled = true
        statusLabel.text = message
        statusLabel.textColor = .systemRed
    }
}
