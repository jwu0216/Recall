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
        let ocrHint = ocrText.map { "OCR text from the image:\n\($0)" } ?? ""
        let content: [[String: Any]] = [
            [
                "type": "text",
                "text": """
                Label this saved personal memory for search.
                Return JSON with keys title, summary, tags (array of short strings).
                \(ocrHint)
                """
            ],
            [
                "type": "image_url",
                "image_url": ["url": "data:image/jpeg;base64,\(base64)"]
            ]
        ]

        let responseText = try await requestChatCompletion(
            model: configuration.visionModel,
            messages: [
                ["role": "system", "content": Self.faithfulLabelingSystemPrompt],
                ["role": "user", "content": content]
            ]
        )

        return parseEnrichment(from: responseText)
    }

    public func summarizeText(_ text: String) async throws -> AIEnrichment {
        let responseText = try await requestChatCompletion(
            model: configuration.chatModel,
            messages: [
                ["role": "system", "content": Self.faithfulLabelingSystemPrompt],
                [
                    "role": "user",
                    "content": """
                    Label this saved personal note for search.
                    Return JSON with keys title, summary, tags (array of short strings).

                    Note:
                    \(text)
                    """
                ]
            ]
        )
        return parseEnrichment(from: responseText)
    }

    private static let faithfulLabelingSystemPrompt = """
    You label personal memories for a private search app. Respond with compact JSON only: title, summary, tags.

    Critical rules:
    - Title and summary must be faithful to the source. Only use facts explicitly present in the user's note, URL, OCR text, or image.
    - Do NOT invent details, adjectives, quality claims, or atmosphere in title/summary (e.g. "fresh ingredients", "authentic", "must-try", "cozy").
    - If the note is short, keep the summary short. Paraphrase lightly; do not expand.
    - Title: concise label from the source (keep proper names).
    - Summary: 1 sentence max that restates only what was said.
    - Tags: include words from the source PLUS a few strongly implied search categories so Ask works in plain English.
      Examples: foundation/lipstick → makeup, cosmetics; margherita/Sole Uptown → pizza, restaurant; wings recipe → food, recipe.
      Do not add unrelated tags. Prefer 3–8 short tags total.
    """

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
        let contextBlock = Self.formatMemories(context)
        let userQuestion = messages.last(where: { $0.role == "user" })?.content ?? ""

        let systemPrompt = """
        \(system)

        Rules:
        - The memories below were already selected as matches for the user's question.
        - You MUST answer using those memories. Quote or paraphrase the memory title.
        - Do NOT say you could not find anything when memories are listed.
        - Only if the memories list is empty may you say you could not find it.
        """

        let userPrompt = """
        Question: \(userQuestion)

        Matched memories:
        \(contextBlock.isEmpty ? "(none)" : contextBlock)

        Answer the question from the matched memories above.
        """

        let apiMessages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": userPrompt]
        ]

        return try await requestChatCompletion(model: configuration.chatModel, messages: apiMessages)
    }

    public static func formatMemories(_ context: [MemoryItemSnapshot]) -> String {
        context.enumerated().map { index, item in
            var lines = ["\(index + 1). Title: \(item.title ?? "Untitled")"]
            if let summary = item.summary, !summary.isEmpty {
                lines.append("   Summary: \(summary)")
            }
            if let extractedText = item.extractedText, !extractedText.isEmpty {
                lines.append("   Text: \(extractedText)")
            }
            if !item.tags.isEmpty {
                lines.append("   Tags: \(item.tags.joined(separator: ", "))")
            }
            if let sourceURL = item.sourceURL {
                lines.append("   URL: \(sourceURL.absoluteString)")
            }
            return lines.joined(separator: "\n")
        }.joined(separator: "\n")
    }

    private func requestChatCompletion(model: String, messages: [[String: Any]]) async throws -> String {
        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": 0
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
