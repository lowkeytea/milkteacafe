import Foundation

/// Registry that manages multiple text classifiers
class TextClassifierRegistry {
    /// Shared singleton instance
    static let shared = TextClassifierRegistry()
    
    /// Dictionary of registered classifiers
    private var classifiers: [String: TextClassifierProtocol] = [:]
    
    /// Private initializer for singleton
    private init() {}
    
    /// Register a classifier with a specific key
    /// - Parameters:
    ///   - classifier: The classifier to register
    ///   - key: The key to use for this classifier
    func register(classifier: TextClassifierProtocol, forKey key: String) {
        classifiers[key] = classifier
    }
    
    /// Retrieve a classifier by key
    /// - Parameter key: The key of the classifier to retrieve
    /// - Returns: The requested classifier or nil if not found
    func classifier(forKey key: String) -> TextClassifierProtocol? {
        return classifiers[key]
    }
    
    /// List all available classifier keys
    /// - Returns: Array of classifier keys
    func availableClassifiers() -> [String] {
        return Array(classifiers.keys)
    }
    
    /// Remove a classifier from the registry
    /// - Parameter key: The key of the classifier to remove
    func unregister(forKey key: String) {
        classifiers.removeValue(forKey: key)
    }
    
    /// Reset the registry, removing all classifiers
    func reset() {
        classifiers.removeAll()
    }
}
