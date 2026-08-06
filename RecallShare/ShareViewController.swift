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

        let ink = UIColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1)
        let muted = UIColor(red: 0.42, green: 0.42, blue: 0.46, alpha: 1)
        view.backgroundColor = UIColor(red: 0.97, green: 0.96, blue: 0.95, alpha: 1)

        titleLabel.text = "Save to Recall"
        titleLabel.font = .systemFont(ofSize: 28, weight: .bold)
        titleLabel.textColor = ink
        titleLabel.textAlignment = .center

        previewLabel.numberOfLines = 4
        previewLabel.textAlignment = .center
        previewLabel.textColor = muted
        previewLabel.font = .preferredFont(forTextStyle: .body)
        previewLabel.text = detectedSummary

        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.textColor = muted
        statusLabel.text = "Recall will tag this later when you open the app."

        var config = UIButton.Configuration.filled()
        config.title = "Save"
        config.baseBackgroundColor = ink
        config.baseForegroundColor = .white
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 28, bottom: 14, trailing: 28)
        saveButton.configuration = config
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)

        spinner.hidesWhenStopped = true
        spinner.color = ink

        let stack = UIStackView(arrangedSubviews: [
            titleLabel,
            previewLabel,
            statusLabel,
            spinner,
            saveButton
        ])
        stack.axis = .vertical
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        Task { await inspectSharedContent() }
    }

    private func inspectSharedContent() async {
        do {
            let payload = try await collectSharedPayload(persistMedia: false)
            detectedSummary = payload.previewSummary
            previewLabel.text = detectedSummary
            saveButton.isEnabled = payload.hasContent
        } catch {
            previewLabel.text = "Nothing to save."
            saveButton.isEnabled = false
        }
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

        do {
            let payload = try await collectSharedPayload(persistMedia: true)
            guard payload.hasContent else {
                finishWithError("Could not save this content.")
                return
            }

            let container = try RecallModelContainerFactory.makeContainer()
            let context = ModelContext(container)
            let note = payload.accompanyingNote
            let linkedURL = payload.webURLs.first
            var savedCount = 0

            switch payload.saveMode {
            case .images:
                // Image share (often includes an embedded/page URL) → one image memory.
                for filename in payload.imageFilenames {
                    try ProcessingQueueService.enqueue(
                        contentType: .image,
                        sourceURL: linkedURL,
                        note: note,
                        payloadFilename: filename,
                        modelContext: context
                    )
                    savedCount += 1
                }
            case .pdfs:
                for filename in payload.pdfFilenames {
                    try ProcessingQueueService.enqueue(
                        contentType: .pdf,
                        sourceURL: linkedURL,
                        note: note,
                        payloadFilename: filename,
                        modelContext: context
                    )
                    savedCount += 1
                }
            case .links:
                // One Share action → one link. Safari often attaches the same URL twice
                // (URL item + plain-text URL); dedupe before enqueueing.
                var enqueuedLinkKeys = Set<String>()
                for url in payload.webURLs {
                    let key = Self.canonicalURLKey(url)
                    guard enqueuedLinkKeys.insert(key).inserted else { continue }
                    try ProcessingQueueService.enqueue(
                        contentType: .link,
                        sourceURL: url,
                        note: note,
                        modelContext: context
                    )
                    savedCount += 1
                }
            case .text:
                for text in payload.standaloneTexts {
                    try ProcessingQueueService.enqueue(
                        contentType: .text,
                        note: text,
                        modelContext: context
                    )
                    savedCount += 1
                }
            }

            guard savedCount > 0 else {
                finishWithError("Could not save this content.")
                return
            }

            // Confirm the job is actually in the shared store before dismissing.
            let pendingRaw = ProcessingStatus.pending.rawValue
            let verify = FetchDescriptor<ProcessingJob>(
                predicate: #Predicate { $0.statusRaw == pendingRaw }
            )
            let pendingCount = try context.fetchCount(verify)
            guard pendingCount > 0 else {
                finishWithError("Saved locally, but Recall couldn’t confirm the shared queue. Try again.")
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

    private enum SaveMode {
        case images
        case pdfs
        case links
        case text
    }

    private struct SharedPayload {
        var urls: [URL] = []
        var imageFilenames: [String] = []
        var pdfFilenames: [String] = []
        var imageCount = 0
        var pdfCount = 0
        var texts: [String] = []
        var attributedNotes: [String] = []

        var webURLs: [URL] {
            urls.filter { url in
                let scheme = url.scheme?.lowercased()
                return scheme == "http" || scheme == "https"
            }
        }

        var hasContent: Bool {
            switch saveMode {
            case .images: return !imageFilenames.isEmpty || imageCount > 0
            case .pdfs: return !pdfFilenames.isEmpty || pdfCount > 0
            case .links: return !webURLs.isEmpty
            case .text: return !standaloneTexts.isEmpty
            }
        }

        /// If Safari provides both an image and a URL, keep the image and store the URL on it.
        var saveMode: SaveMode {
            if !imageFilenames.isEmpty || imageCount > 0 { return .images }
            if !pdfFilenames.isEmpty || pdfCount > 0 { return .pdfs }
            if !webURLs.isEmpty { return .links }
            return .text
        }

        /// Text used as a note on link/image/PDF memories; empty when text-only share.
        var accompanyingNote: String? {
            switch saveMode {
            case .text:
                return nil
            case .images, .pdfs, .links:
                break
            }
            let urlStrings = Set(urls.map(\.absoluteString))
            let candidates = (attributedNotes + texts)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .filter { !urlStrings.contains($0) }
            return candidates.first
        }

        var standaloneTexts: [String] {
            texts
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        var previewSummary: String {
            switch saveMode {
            case .images:
                let images = max(imageFilenames.count, imageCount)
                if let url = webURLs.first {
                    return images <= 1
                        ? "Image\n\(url.host ?? url.absoluteString)"
                        : "\(images) images\n\(url.host ?? url.absoluteString)"
                }
                return images <= 1 ? "Image" : "\(images) images"
            case .pdfs:
                let pdfs = max(pdfFilenames.count, pdfCount)
                return pdfs <= 1 ? "PDF" : "\(pdfs) PDFs"
            case .links:
                if let url = webURLs.first {
                    let host = url.host ?? url.absoluteString
                    if let note = accompanyingNote {
                        return "Link: \(host)\n\(note)"
                    }
                    return "Link: \(host)"
                }
                return "Link"
            case .text:
                if let text = standaloneTexts.first {
                    return "Text: \(String(text.prefix(100)))"
                }
                return "Unsupported content."
            }
        }
    }

    private func collectSharedPayload(persistMedia: Bool) async throws -> SharedPayload {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            return SharedPayload()
        }

        var payload = SharedPayload()
        var seenURLs = Set<String>()

        for item in extensionItems {
            if let raw = item.attributedContentText?.string {
                let attributed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !attributed.isEmpty {
                    payload.attributedNotes.append(attributed)
                }
            }

            for provider in item.attachments ?? [] {
                // Pull every representation Safari offers. Image shares often declare URL
                // first; if we only trust that order, photos incorrectly become links.
                if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    if persistMedia {
                        if let filename = try await saveImage(from: provider) {
                            payload.imageFilenames.append(filename)
                        }
                    } else {
                        payload.imageCount += 1
                    }
                }

                if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
                    if persistMedia {
                        if let filename = try await savePDF(from: provider) {
                            payload.pdfFilenames.append(filename)
                        }
                    } else {
                        payload.pdfCount += 1
                    }
                }

                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let url = try await loadURL(from: provider),
                   seenURLs.insert(Self.canonicalURLKey(url)).inserted
                {
                    payload.urls.append(url)
                }

                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                   let text = try await loadText(from: provider)
                {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { continue }

                    if let url = URL(string: trimmed),
                       let scheme = url.scheme?.lowercased(),
                       scheme == "http" || scheme == "https"
                    {
                        if seenURLs.insert(Self.canonicalURLKey(url)).inserted {
                            payload.urls.append(url)
                        }
                    } else {
                        payload.texts.append(trimmed)
                    }
                }
            }
        }

        return payload
    }

    private static func canonicalURLKey(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString.lowercased()
        }
        components.fragment = nil
        if let host = components.host {
            components.host = host.lowercased()
        }
        if components.path.count > 1, components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        components.scheme = components.scheme?.lowercased()
        return (components.url ?? url).absoluteString
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

    private func imageTypeIdentifiers(for provider: NSItemProvider) -> [String] {
        var identifiers = provider.registeredTypeIdentifiers.filter { id in
            if let type = UTType(id), type.conforms(to: .image) { return true }
            let lower = id.lowercased()
            return lower.contains("image")
                || lower.hasSuffix("jpeg")
                || lower.hasSuffix("jpg")
                || lower.hasSuffix("png")
                || lower.hasSuffix("heic")
                || lower.hasSuffix("gif")
                || lower.hasSuffix("webp")
        }
        if identifiers.isEmpty {
            identifiers = [UTType.image.identifier, UTType.jpeg.identifier, UTType.png.identifier]
        }
        return identifiers
    }

    private func saveImage(from provider: NSItemProvider) async throws -> String? {
        guard let mediaDirectory = AppGroupPaths.shared.mediaDirectory else {
            throw RecallStoreError.appGroupUnavailable
        }

        for typeIdentifier in imageTypeIdentifiers(for: provider) {
            if let filename = try await saveImage(from: provider, typeIdentifier: typeIdentifier, to: mediaDirectory) {
                return filename
            }
        }
        return nil
    }

    private func saveImage(
        from provider: NSItemProvider,
        typeIdentifier: String,
        to mediaDirectory: URL
    ) async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                if error != nil {
                    continuation.resume(returning: nil)
                    return
                }

                do {
                    let filename = "\(UUID().uuidString).jpg"
                    let destination = mediaDirectory.appendingPathComponent(filename)

                    if let url = item as? URL {
                        // May be a file URL or a direct image URL from Safari.
                        let data = try Data(contentsOf: url)
                        guard let image = UIImage(data: data),
                              let jpeg = image.jpegData(compressionQuality: 0.75)
                        else {
                            // Not decodable image bytes (e.g. an HTML page URL).
                            continuation.resume(returning: nil)
                            return
                        }
                        try jpeg.write(to: destination)
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
                    continuation.resume(returning: nil)
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
