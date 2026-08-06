import Foundation

public enum RecallConstants {
    public static let appGroupID = "group.com.jwu0216.recall"
    public static let sharedMediaFolder = "SharedMedia"
    public static let openAIKeychainKey = "openai_api_key"
    public static let storeNeedsRefreshNotification = Notification.Name("RecallStoreNeedsRefresh")
}

public enum RecallStoreError: Error, LocalizedError {
    case appGroupUnavailable
    case missingAPIKey
    case invalidAPIKey
    case apiKeyVerificationFailed
    case invalidResponse
    case mediaCopyFailed

    public var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            return "Recall could not access the shared app group container."
        case .missingAPIKey:
            return "Add your OpenAI API key in Settings to enable AI search."
        case .invalidAPIKey:
            return "Invalid API key. Check the key and try again."
        case .apiKeyVerificationFailed:
            return "Couldn't verify the API key. Check your connection and try again."
        case .invalidResponse:
            return "Recall received an unexpected response from the AI service."
        case .mediaCopyFailed:
            return "Recall could not save shared media."
        }
    }
}
