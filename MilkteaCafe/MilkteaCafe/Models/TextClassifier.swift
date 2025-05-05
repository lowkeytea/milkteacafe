import Foundation
import CoreML
import NaturalLanguage

/// A lightweight text classifier that can classify text using CoreML models
class TextClassifier {
    private let model: MLModel
    private let modelName: String
    
    /// Represents the classification result with confidence scores
    struct ClassificationResult {
        let label: String
        let confidence: Double
        let allPredictions: [String: Double]
        
        var isShort: Bool { label == "short" }
        var isLong: Bool { label == "long" }
    }
    
    /// Initialize with a CoreML model
    /// - Parameter modelURL: URL to the CoreML model file
    init?(modelURL: URL) {
        do {
            self.model = try MLModel(contentsOf: modelURL)
            self.modelName = modelURL.lastPathComponent.replacingOccurrences(of: ".mlmodel", with: "")
        } catch {
            print("Error loading model: \(error)")
            return nil
        }
    }
    
    /// Initialize with a model in the main bundle by name
    /// - Parameter modelName: Name of the CoreML model without extension
    convenience init?(modelName: String) {
        guard let modelURL = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc") else {
            print("Could not find model \(modelName) in bundle")
            return nil
        }
        self.init(modelURL: modelURL)
    }
    
    /// Classify text and return the result
    /// - Parameter text: The input text to classify
    /// - Returns: ClassificationResult containing the predicted label and confidence scores
    func classify(_ text: String) -> ClassificationResult? {
        do {
            // Create input for prediction
            let inputFeatures = try MLDictionaryFeatureProvider(dictionary: ["text": text as NSString])
            
            // Make prediction
            let prediction = try model.prediction(from: inputFeatures)
            
            // Extract results
            guard let outputFeatures = prediction.featureValue(for: "label")?.stringValue else {
                return nil
            }
            
            // Extract probabilities (CoreML typically provides this as a dictionary)
            var allPredictions: [String: Double] = [:]
            
            // If the model provides probability outputs, extract them
            if let probabilities = prediction.featureValue(for: "labelProbability")?.dictionaryValue as? [String: NSNumber] {
                for (label, probability) in probabilities {
                    allPredictions[label] = probability.doubleValue
                }
            }
            
            // Find the highest confidence
            let confidence = allPredictions[outputFeatures] ?? 1.0
            
            return ClassificationResult(
                label: outputFeatures,
                confidence: confidence,
                allPredictions: allPredictions
            )
        } catch {
            print("Prediction error: \(error)")
            return nil
        }
    }
    
    /// Classify text as either short or long
    /// - Parameter text: The input text to classify
    /// - Returns: ClassificationResult with short/long prediction
    func classifyShortLong(_ text: String) -> ClassificationResult? {
        return classify(text)
    }
}

/// Factory for creating TextClassifier instances
class TextClassifierFactory {
    /// Create a classifier for short/long text classification
    static func createShortLongClassifier() -> TextClassifier? {
        return TextClassifier(modelName: "PromptClassifierShortLong")
    }
    
    /// Create a custom classifier with a provided model
    static func createClassifier(modelName: String) -> TextClassifier? {
        return TextClassifier(modelName: modelName)
    }
}