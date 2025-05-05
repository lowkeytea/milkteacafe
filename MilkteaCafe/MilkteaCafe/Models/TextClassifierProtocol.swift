import Foundation

/// Protocol defining the interface for all text classifiers
protocol TextClassifierProtocol {
    /// The name of the classifier model
    var modelName: String { get }
    
    /// Represents a classification result with confidence scores
    typealias ClassificationResult = TextClassifierResult
    
    /// Classifies input text and returns a result
    /// - Parameter text: The text to classify
    /// - Returns: Classification result or nil if classification failed
    func classify(_ text: String) -> ClassificationResult?
}

/// Standard result type for all text classifiers
struct TextClassifierResult {
    /// The predicted label
    let label: String
    /// Confidence value for the prediction (0-1)
    let confidence: Double
    /// Dictionary of all prediction labels and their confidence scores
    let allPredictions: [String: Double]
    
    /// Convenience computed properties for specific label types
    var isShort: Bool { label == "short" }
    var isLong: Bool { label == "long" }
}

/// Errors that can occur during classification
enum ClassifierError: Error {
    case modelNotFound
    case modelLoadFailed(Error)
    case predictionFailed(Error)
    case classifierNotFound
    case invalidInput
}
