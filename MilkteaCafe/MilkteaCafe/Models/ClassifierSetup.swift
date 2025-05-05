import Foundation

/// Helper class for setting up the classifier system on app startup
class ClassifierSetup {
    /// Singleton instance
    static let shared = ClassifierSetup()
    
    /// Private initializer for singleton pattern
    private init() {}
    
    /// Whether the classifiers have been set up
    private var isSetUp = false
    
    /// Set up all required classifiers for the application
    /// - Returns: Whether setup was successful
    @discardableResult
    func setupClassifiers() -> Bool {
        // Prevent multiple setups
        guard !isSetUp else {
            LoggerService.shared.debug("Classifiers already set up, skipping")
            return true
        }
        
        LoggerService.shared.info("Setting up text classifiers...")
        
        // Track setup success
        var setupSuccess = true
        
        // Setup short/long classifier
        let shortLongSuccess = TextClassifierFactory.setupShortLongClassifier()
        if shortLongSuccess {
            LoggerService.shared.info("Short/Long classifier set up successfully")
        } else {
            LoggerService.shared.warning("Failed to set up Short/Long classifier")
            setupSuccess = false
        }
        
        // Setup the function classifier
        let functionClassifier = TextClassifierFactory.setupFunctionClassifier()
        if functionClassifier != nil {
            LoggerService.shared.info("Function classifier set up successfully")
        } else {
            LoggerService.shared.warning("Failed to set up Function classifier")
            setupSuccess = false
        }
        
        // Mark setup as complete
        isSetUp = setupSuccess
        return setupSuccess
    }
    
    /// Get the TextClassificationService
    /// - Returns: A configured TextClassificationService
    func getClassificationService() -> TextClassificationService? {
        // Ensure classifiers are set up
        if !isSetUp {
            _ = setupClassifiers()
        }
        
        // Create and return the service
        return TextClassifierFactory.createClassificationService()
    }
}
