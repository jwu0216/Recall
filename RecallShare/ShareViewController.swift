import UIKit
import UniformTypeIdentifiers
import SwiftData
import RecallCore

final class ShareViewController: UIViewController {
    private let statusLabel = UILabel()
    private let saveButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground

        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        statusLabel.text = "Preparing shared content..."

        saveButton.setTitle("Save to Recall", for: .normal)
        saveButton.titleLabel?.font = .boldSystemFont(ofSize: 17)
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [statusLabel, saveButton])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    @objc private func saveTapped() {
        Task {
            await handleShare()
        }
    }

    @MainActor
    private func handleShare() async {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            finishWithError("No shared items found.")
            return
        }

        do {
            let container = try RecallModelContainerFactory.makeContainer()
            let context = ModelContext(container)

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
                        statusLabel.text = "Saved link to Recall."
                    } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                              let text = try await loadText(from: provider) {
                        try ProcessingQueueService.enqueue(
                            contentType: .text,
                            note: text,
                            modelContext: context
                        )
                        statusLabel.text = "Saved text to Recall."
                    } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
                              let filename = try await saveImage(from: provider) {
                        try ProcessingQueueService.enqueue(
                            contentType: .image,
                            note: item.attributedContentText?.string,
                            payloadFilename: filename,
                            modelContext: context
                        )
                        statusLabel.text = "Saved image to Recall."
                    } else if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier),
                              let filename = try await savePDF(from: provider) {
                        try ProcessingQueueService.enqueue(
                            contentType: .pdf,
                            note: item.attributedContentText?.string,
                            payloadFilename: filename,
                            modelContext: context
                        )
                        statusLabel.text = "Saved PDF to Recall."
                    }
                }
            }

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
                        try FileManager.default.copyItem(at: url, to: destination)
                    } else if let image = item as? UIImage, let data = image.jpegData(compressionQuality: 0.85) {
                        try data.write(to: destination)
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
        statusLabel.text = message
        extensionContext?.cancelRequest(withError: NSError(domain: "RecallShare", code: 1, userInfo: [NSLocalizedDescriptionKey: message]))
    }
}
