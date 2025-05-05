import Foundation
import CoreML

/// Defines the possible function classifications that can be returned
enum FunctionClassification: String {
    case changeSystemPrompt
    case noOperation
    case rememberName
    case voiceCommand
    
    /// Creates a FunctionClassification from a string, defaulting to noOperation if invalid
    /// - Parameter string: The string value to convert
    /// - Returns: The matching FunctionClassification or .noOperation if not found
    static func fromString(_ string: String) -> FunctionClassification {
        return FunctionClassification(rawValue: string) ?? .noOperation
    }
}

/// Classifier that determines if a text input represents a function command
class BaseFunctionClassifier {
    private let model: MLModel
    let modelName: String = "functionClassifications"
    
    /// Represents a function classification result
    struct FunctionClassificationResult {
        let classification: FunctionClassification
        let confidence: Double
        let allPredictions: [String: Double]
        let analyzedBy: AnalysisMethod
        
        var isNoOperation: Bool { classification == .noOperation }
        
        /// Method used to analyze the text
        enum AnalysisMethod {
            case wholeText
            case sentenceLevel
        }
    }
    
    /// Initialize the classifier with the functionClassifications model
    init() throws {
        // Look for compiled model first
        if let modelURL = Bundle.main.url(forResource: "functionClassifications", withExtension: "mlmodelc") {
            self.model = try MLModel(contentsOf: modelURL)
        }
        // Try uncompiled model if compiled not found
        else if let modelURL = Bundle.main.url(forResource: "functionClassifications", withExtension: "mlmodel") {
            self.model = try MLModel(contentsOf: modelURL)
        }
        else {
            throw ClassifierError.modelNotFound
        }
    }
    
    /// Classify text to determine if it represents a function command
    /// Uses a two-step approach:
    /// 1. First checks the entire text
    /// 2. If initial result is "noOperation", then analyzes individual sentences
    /// - Parameter text: The text to classify
    /// - Returns: FunctionClassificationResult containing the classification and confidence
    func classify(_ text: String) -> FunctionClassificationResult? {
        // Step 1: Analyze the full text first
        guard let wholeTextResult = classifyText(text) else {
            LoggerService.shared.error("Failed to classify text: \(text)")
            return nil
        }
        
        // If the full text is classified as a function (not noOperation),
        // return that result immediately
        if !wholeTextResult.isNoOperation {
            return FunctionClassificationResult(
                classification: wholeTextResult.classification,
                confidence: wholeTextResult.confidence,
                allPredictions: wholeTextResult.allPredictions,
                analyzedBy: .wholeText
            )
        }
        
        // Step 2: If it's classified as noOperation, analyze individual sentences
        let sentences = text.splitIntoSentences()
        sentences.forEach {
            LoggerService.shared.debug("Sentence: \($0)")
        }
        // Skip sentence analysis if there's only one sentence
        if sentences.count <= 1 {
            return FunctionClassificationResult(
                classification: wholeTextResult.classification,
                confidence: wholeTextResult.confidence,
                allPredictions: wholeTextResult.allPredictions,
                analyzedBy: .wholeText
            )
        }
        
        // Log for debugging
        #if DEBUG
        LoggerService.shared.debug("Analyzing \(sentences.count) sentences for function classification")
        #endif
        
        // Check each sentence
        for (index, sentence) in sentences.enumerated() {
            // Skip very short sentences
            if sentence.count < 3 {
                continue
            }
            
            if let sentenceResult = classifyText(sentence), !sentenceResult.isNoOperation {
                #if DEBUG
                LoggerService.shared.debug("Found function in sentence \(index + 1): \(sentenceResult.classification.rawValue) with confidence \(sentenceResult.confidence)")
                #endif
                
                // If any sentence is classified as a function, return that result
                return FunctionClassificationResult(
                    classification: sentenceResult.classification,
                    confidence: sentenceResult.confidence,
                    allPredictions: sentenceResult.allPredictions,
                    analyzedBy: .sentenceLevel
                )
            }
        }
        
        // If no sentence was classified as a function, return the original result
        return FunctionClassificationResult(
            classification: wholeTextResult.classification,
            confidence: wholeTextResult.confidence,
            allPredictions: wholeTextResult.allPredictions,
            analyzedBy: .wholeText
        )
    }
    
    /// Internal method to classify a single text string
    /// - Parameter text: The text to classify
    /// - Returns: Classification result or nil if classification failed
    func classifyText(_ text: String) -> FunctionClassificationResult? {
        do {
            // Create input for prediction
            let inputFeatures = try MLDictionaryFeatureProvider(dictionary: ["text": text as NSString])
            
            // Make prediction
            let prediction = try model.prediction(from: inputFeatures)
            
            // Extract results
            guard let outputLabel = prediction.featureValue(for: "label")?.stringValue else {
                return nil
            }
            
            // Extract probabilities if available
            var allPredictions: [String: Double] = [:]
            
            if let probabilities = prediction.featureValue(for: "labelProbability")?.dictionaryValue as? [String: NSNumber] {
                for (label, probability) in probabilities {
                    allPredictions[label] = probability.doubleValue
                }
            }
            
            // Find the confidence for the predicted class
            let confidence = allPredictions[outputLabel] ?? 1.0
            
            // Convert to enum
            let classification = FunctionClassification.fromString(outputLabel)
            
            return FunctionClassificationResult(
                classification: classification,
                confidence: confidence,
                allPredictions: allPredictions,
                analyzedBy: .wholeText // This is just a default, will be overridden by the caller
            )
        } catch {
            LoggerService.shared.error("Function classification error: \(error)")
            return nil
        }
    }
}
