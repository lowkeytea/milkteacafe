import Foundation

/// Structure to parse the function call JSON response
struct FunctionCallResponse: Codable {
    let name: String
    let arguments: [String: Any]
    
    enum CodingKeys: String, CodingKey {
        case name
        case arguments
    }
    
    /// Custom decoding for handling Any type arguments
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        
        // Handle arguments as a dynamic dictionary
        let argumentsContainer = try container.nestedContainer(keyedBy: DynamicCodingKeys.self, forKey: .arguments)
        var decodedArguments: [String: Any] = [:]
        
        for key in argumentsContainer.allKeys {
            // Try to decode as various types
            if let boolValue = try? argumentsContainer.decodeIfPresent(Bool.self, forKey: key) {
                decodedArguments[key.stringValue] = boolValue
            } else if let stringValue = try? argumentsContainer.decodeIfPresent(String.self, forKey: key) {
                decodedArguments[key.stringValue] = stringValue
            } else if let intValue = try? argumentsContainer.decodeIfPresent(Int.self, forKey: key) {
                decodedArguments[key.stringValue] = intValue
            } else if let doubleValue = try? argumentsContainer.decodeIfPresent(Double.self, forKey: key) {
                decodedArguments[key.stringValue] = doubleValue
            } else {
                // If it's a complex type like array or object, we'll just set it to nil for now
                // In a more complete implementation, we could add more type handling
                decodedArguments[key.stringValue] = nil
            }
        }
        
        arguments = decodedArguments
    }
    
    /// Placeholder for encoding (not used but required for Codable)
    func encode(to encoder: Encoder) throws {
        // We don't need encoding for this use case, but must implement for Codable
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        
        // For a real implementation, we would need to handle encoding the arguments
        // But since we don't need to encode in our use case, this is just a placeholder
    }
}

/// Helper struct for dynamic JSON keys
struct DynamicCodingKeys: CodingKey {
    var stringValue: String
    var intValue: Int?
    
    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }
    
    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}
