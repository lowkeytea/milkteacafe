import Foundation

public enum LlamaError: Error {
    case couldNotInitializeContext
    case decodingFailed
    case invalidInput
    case modelNotLoaded
    case cancelledByUser
    case embeddingError(Error)
    case underlying(Error)
    case feedRefreshInProgress
    case fileNotFound(path: String)
    
    var localizedDescription: String {
        switch self {
        case .couldNotInitializeContext:
            return "Could not initialize context"
        case .decodingFailed:
            return "Failed to decode response"
        case .invalidInput:
            return "Invalid input provided"
        case .modelNotLoaded:
            return "AI model not loaded"
        case .cancelledByUser:
            return "Operation cancelled by user"
        case .embeddingError(let error):
            return "Embedding error: \(error.localizedDescription)"
        case .underlying(let error):
            return error.localizedDescription
        case .feedRefreshInProgress:
            return "Feed refresh is in progress. Please wait to prevent memory conflicts."
        case .fileNotFound(let path):
            return "Model file not found at: \(path)"
        }
    }
}
