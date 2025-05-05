import Foundation

/// Examples of how to use the new classifier architecture
class ClassifierExamples {
    
    /// Example of initializing and using all the classifiers
    static func setupExample() {
        // Create and configure the service
        guard let classificationService = TextClassifierFactory.createClassificationService() else {
            print("Failed to create classification service")
            return
        }
        
        // Example text inputs
        let textExamples = [
            "What's the weather like today?",
            "Change my system prompt to be more friendly",
            "Remember my name is John",
            "Set a timer for 10 minutes",
            "Tell me a short story"
        ]
        
        // Process each example
        for text in textExamples {
            let result = classificationService.processUserInput(text)
            
            switch result.type {
            case .function(let functionClass):
                print("[\(text)] - Function: \(functionClass)")
                
                // Handle specific function types
                switch functionClass {
                case .changeSystemPrompt:
                    print("  -> Handling system prompt change")
                case .rememberName:
                    print("  -> Remembering user's name")
                case .voiceCommand:
                    print("  -> Processing voice command")
                case .noOperation:
                    print("  -> No special operation needed")
                }
                
            case .text(let textResult):
                print("[\(text)] - Text classification: \(textResult.label) (confidence: \(textResult.confidence))")
                
                // Handle text classification
                if textResult.isShort {
                    print("  -> Text is classified as short")
                } else if textResult.isLong {
                    print("  -> Text is classified as long")
                } else {
                    print("  -> Other classification: \(textResult.label)")
                }
                
            case .error(let error):
                print("[\(text)] - Error: \(error)")
            }
        }
    }
    
    /// Example of registering a new classifier at runtime
    static func dynamicClassifierExample() {
        // Register a new classifier
        let success = TextClassifierFactory.setupClassifier(
            modelName: "AnotherClassifier", 
            forKey: "custom"
        )
        
        if success {
            print("Successfully registered custom classifier")
            
            // Create a service that uses this classifier
            let registry = TextClassifierRegistry.shared
            let service = TextClassificationService(registry: registry)
            
            // Use the custom classifier
            let result = service.processUserInput("Test input", textClassifierKey: "custom")
            
            // Process result
            switch result.type {
            case .text(let textResult):
                print("Classification: \(textResult.label)")
            case .function, .error:
                print("Unexpected result type")
            }
        } else {
            print("Failed to register custom classifier")
        }
    }
}
