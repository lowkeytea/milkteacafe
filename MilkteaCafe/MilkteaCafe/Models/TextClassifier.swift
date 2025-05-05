import Foundation

/// @deprecated Use CoreMLTextClassifier instead
/// This class is kept for backward compatibility
class TextClassifier {
    private let coreMLClassifier: CoreMLTextClassifier
    
    /// @deprecated Use CoreMLTextClassifier.ClassificationResult instead
    typealias ClassificationResult = TextClassifierResult
    
    /// Initialize with a CoreML model
    /// - Parameter modelURL: URL to the CoreML model file
    init?(modelURL: URL) {
        guard let classifier = CoreMLTextClassifier(modelURL: modelURL) else {
            return nil
        }
        self.coreMLClassifier = classifier
    }
    
    /// Initialize with a model in the main bundle by name
    /// - Parameter modelName: Name of the CoreML model without extension
    convenience init?(modelName: String) {
        guard let classifier = CoreMLTextClassifier(modelName: modelName) else {
            return nil
        }
        self.init(modelURL: Bundle.main.url(forResource: modelName, withExtension: "mlmodelc")!)
    }
    
    /// Classify text and return the result
    /// - Parameter text: The input text to classify
    /// - Returns: ClassificationResult containing the predicted label and confidence scores
    func classify(_ text: String) -> ClassificationResult? {
        return coreMLClassifier.classify(text)
    }
    
    /// Classify text as either short or long
    /// - Parameter text: The input text to classify
    /// - Returns: ClassificationResult with short/long prediction
    func classifyShortLong(_ text: String) -> ClassificationResult? {
        return classify(text)
    }
}
