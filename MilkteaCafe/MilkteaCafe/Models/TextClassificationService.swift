import Foundation

/// Service that coordinates text classification across different classifiers
class TextClassificationService {
    /// The registry of text classifiers
    private let classifierRegistry: TextClassifierRegistry
    
    /// The function classifier
    private let functionClassifier: BaseFunctionClassifier?
    
    /// The result of processing a user input
    struct ProcessedInput {
        /// The type of classification result
        enum InputType {
            case function(FunctionClassification)
            case text(TextClassifierResult)
            case error(Error)
        }
        
        let type: InputType
        
        /// Whether this input represents a no-operation
        var isNoOperation: Bool {
            switch type {
            case .function(let functionClass):
                return functionClass == .noOperation
            default:
                return false
            }
        }
    }
    
    /// Initialize with registry and function classifier
    /// - Parameters:
    ///   - registry: The text classifier registry
    ///   - functionClassifier: Optional function classifier
    init(registry: TextClassifierRegistry, functionClassifier: BaseFunctionClassifier? = nil) {
        self.classifierRegistry = registry
        self.functionClassifier = functionClassifier
    }
    
    /// Process user input text through appropriate classifiers
    /// - Parameters:
    ///   - text: The input text to process
    ///   - textClassifierKey: The key for which text classifier to use if needed
    /// - Returns: A ProcessedInput with the classification result
    func processUserInput(_ text: String, textClassifierKey: String = "default") -> ProcessedInput {
        // First check if this is a function command (if function classifier is available)
        if let functionClassifier = functionClassifier,
           let functionResult = functionClassifier.classify(text) {
            
            // If it's not a noOperation, handle as a function command
            if !functionResult.isNoOperation {
                return ProcessedInput(type: .function(functionResult.classification))
            }
        }
        
        // Otherwise, classify with text classifiers
        guard let textClassifier = classifierRegistry.classifier(forKey: textClassifierKey) else {
            return ProcessedInput(type: .error(ClassifierError.classifierNotFound))
        }
        
        guard let textResult = textClassifier.classify(text) else {
            return ProcessedInput(type: .error(ClassifierError.predictionFailed(NSError(domain: "TextClassification", code: 1, userInfo: nil))))
        }
        
        return ProcessedInput(type: .text(textResult))
    }
}
