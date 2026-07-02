import Foundation

public enum RecallConstants {
    public static let appGroupID = "group.com.jwu0216.recall"
    public static let sharedMediaFolder = "SharedMedia"
    public static let openAIKeychainKey = "openai_api_key"
}

public enum RecallStoreError: Error, LocalizedError {
    case appGroupUnavailable
    case missingAPIKey
    case invalidResponse
    case mediaCopyFailed

    public var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            return "Recall could not access the shared app group container."
        case .missingAPIKey:
            return "Add your OpenAI API key in Settings to enable AI search."
        case .invalidResponse:
            return "Recall received an unexpected response from the AI service."
        case .mediaCopyFailed:
            return "Recall could not save shared media."
        }
    }
}
