import Foundation

/// Factory for creating and configuring text classifiers
class TextClassifierFactory {
    /// Create a classifier for short/long text classification and register it
    /// - Returns: Whether the operation was successful
    static func setupShortLongClassifier() -> Bool {
        guard let classifier = CoreMLTextClassifier(modelName: "PromptClassifierShortLong") else {
            return false
        }
        
        TextClassifierRegistry.shared.register(classifier: classifier, forKey: "shortLong")
        return true
    }
    
    /// Create a custom classifier with a provided model name and register it
    /// - Parameters:
    ///   - modelName: Name of the model to use
    ///   - key: Key to register the classifier with
    /// - Returns: Whether the operation was successful
    static func setupClassifier(modelName: String, forKey key: String) -> Bool {
        guard let classifier = CoreMLTextClassifier(modelName: modelName) else {
            return false
        }
        
        TextClassifierRegistry.shared.register(classifier: classifier, forKey: key)
        return true
    }
    
    /// Setup the function classifier
    /// - Returns: The created function classifier or nil if failed
    static func setupFunctionClassifier() -> BaseFunctionClassifier? {
        do {
            return try BaseFunctionClassifier()
        } catch {
            print("Failed to create function classifier: \(error)")
            return nil
        }
    }
    
    /// Create and configure the TextClassificationService with all classifiers
    /// - Returns: Configured TextClassificationService or nil if setup failed
    static func createClassificationService() -> TextClassificationService? {
        // Setup text classifiers
        let shortLongSuccess = setupShortLongClassifier()
        if !shortLongSuccess {
            print("Warning: Failed to set up short/long classifier")
        }
        
        // Setup function classifier
        let functionClassifier = setupFunctionClassifier()
        if functionClassifier == nil {
            print("Warning: Failed to set up function classifier")
        }
        
        // Create the service
        return TextClassificationService(
            registry: TextClassifierRegistry.shared,
            functionClassifier: functionClassifier
        )
    }
}
