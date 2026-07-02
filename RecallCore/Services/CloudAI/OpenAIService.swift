import Foundation

public protocol CloudAIService: Sendable {
    func describeImage(_ imageData: Data, ocrText: String?) async throws -> AIEnrichment
    func summarizeText(_ text: String) async throws -> AIEnrichment
    func embed(_ text: String) async throws -> [Float]
    func chat(system: String, messages: [ChatTurn], context: [MemoryItemSnapshot]) async throws -> String
}

public struct OpenAIConfiguration: Sendable {
    public var apiKey: String
    public var chatModel: String
    public var visionModel: String
    public var embeddingModel: String

    public init(
        apiKey: String,
        chatModel: String = "gpt-4o-mini",
        visionModel: String = "gpt-4o-mini",
        embeddingModel: String = "text-embedding-3-small"
    ) {
        self.apiKey = apiKey
        self.chatModel = chatModel
        self.visionModel = visionModel
        self.embeddingModel = embeddingModel
    }
}

public final class OpenAIService: CloudAIService {
    private let configuration: OpenAIConfiguration
    private let session: URLSession

    public init(configuration: OpenAIConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    public func describeImage(_ imageData: Data, ocrText: String?) async throws -> AIEnrichment {
        let base64 = imageData.base64EncodedString()
        let ocrHint = ocrText.map { "OCR text:\n\($0)" } ?? ""
        let content: [[String: Any]] = [
            [
                "type": "text",
                "text": "Describe this saved memory for search. Return JSON with keys title, summary, tags (array of short strings). \(ocrHint)"
            ],
            [
                "type": "image_url",
                "image_url": ["url": "data:image/jpeg;base64,\(base64)"]
            ]
        ]

        let responseText = try await requestChatCompletion(
            model: configuration.visionModel,
            messages: [
                ["role": "system", "content": "You label personal memories for a search app. Respond with compact JSON only."],
                ["role": "user", "content": content]
            ]
        )

        return parseEnrichment(from: responseText)
    }

    public func summarizeText(_ text: String) async throws -> AIEnrichment {
        let responseText = try await requestChatCompletion(
            model: configuration.chatModel,
            messages: [
                ["role": "system", "content": "Summarize saved content for search. Respond with JSON: title, summary, tags."],
                ["role": "user", "content": text]
            ]
        )
        return parseEnrichment(from: responseText)
    }

    public func embed(_ text: String) async throws -> [Float] {
        let body: [String: Any] = [
            "model": configuration.embeddingModel,
            "input": text
        ]

        let data = try await postJSON(path: "embeddings", body: body)
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let rows = root["data"] as? [[String: Any]],
            let first = rows.first,
            let vector = first["embedding"] as? [Double]
        else {
            throw RecallStoreError.invalidResponse
        }

        return vector.map(Float.init)
    }

    public func chat(system: String, messages: [ChatTurn], context: [MemoryItemSnapshot]) async throws -> String {
        let contextBlock = context.map { item in
            let title = item.title ?? "Untitled"
            let body = item.searchableText
            return "- \(title): \(body)"
        }.joined(separator: "\n")

        var apiMessages: [[String: Any]] = [
            ["role": "system", "content": system],
            ["role": "system", "content": "Memories:\n\(contextBlock)"]
        ]

        apiMessages.append(contentsOf: messages.map { ["role": $0.role, "content": $0.content] })

        return try await requestChatCompletion(model: configuration.chatModel, messages: apiMessages)
    }

    private func requestChatCompletion(model: String, messages: [[String: Any]]) async throws -> String {
        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": 0.2
        ]

        let data = try await postJSON(path: "chat/completions", body: body)
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = root["choices"] as? [[String: Any]],
            let first = choices.first,
            let message = first["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw RecallStoreError.invalidResponse
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func postJSON(path: String, body: [String: Any]) async throws -> Data {
        guard let url = URL(string: "https://api.openai.com/v1/\(path)") else {
            throw RecallStoreError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw RecallStoreError.invalidResponse
        }
        return data
    }

    private func parseEnrichment(from text: String) -> AIEnrichment {
        let cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if
            let data = cleaned.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            let title = json["title"] as? String
            let summary = json["summary"] as? String
            let tags = json["tags"] as? [String] ?? []
            return AIEnrichment(title: title, summary: summary, tags: tags)
        }

        return AIEnrichment(summary: cleaned, tags: [])
    }
}
