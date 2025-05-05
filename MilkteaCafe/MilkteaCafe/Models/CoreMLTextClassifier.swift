import Foundation
import CoreML
import NaturalLanguage

/// A text classifier that uses CoreML models
class CoreMLTextClassifier: TextClassifierProtocol {
    private let model: MLModel
    let modelName: String
    
    /// Initialize with a CoreML model
    /// - Parameter modelURL: URL to the CoreML model file
    init?(modelURL: URL) {
        do {
            self.model = try MLModel(contentsOf: modelURL)
            self.modelName = modelURL.lastPathComponent.replacingOccurrences(of: ".mlmodel", with: "")
                                   .replacingOccurrences(of: ".mlmodelc", with: "")
        } catch {
            print("Error loading model: \(error)")
            return nil
        }
    }
    
    /// Initialize with a model in the main bundle by name
    /// - Parameter modelName: Name of the CoreML model without extension
    convenience init?(modelName: String) {
        // Try compiled model first
        if let modelURL = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc") {
            self.init(modelURL: modelURL)
            return
        }
        
        // Try uncompiled model if compiled not found
        if let modelURL = Bundle.main.url(forResource: modelName, withExtension: "mlmodel") {
            self.init(modelURL: modelURL)
            return
        }
        
        print("Could not find model \(modelName) in bundle")
        return nil
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
}
