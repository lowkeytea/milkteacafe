# Text Classification System

This document describes the text classification system implemented in the MilkteaCafe project.

## Architecture Overview

The text classification system is designed to support multiple classification models with a modular and extensible architecture. It consists of:

1. **Base Protocol** (`TextClassifierProtocol`): Defines the interface for all text classifiers.
2. **Model Implementations**: Concrete implementations of the protocol for different model types.
3. **Registry** (`TextClassifierRegistry`): Manages and provides access to registered classifiers.
4. **Function Classifier** (`BaseFunctionClassifier`): Special classifier that determines if input should trigger specific functions.
5. **Coordination Service** (`TextClassificationService`): Orchestrates the classification process.

## Components

### TextClassifierProtocol

The base protocol that all text classifiers must conform to:

```swift
protocol TextClassifierProtocol {
    var modelName: String { get }
    func classify(_ text: String) -> ClassificationResult?
}
```

### CoreMLTextClassifier

Implementation of the protocol that uses CoreML models:

```swift
class CoreMLTextClassifier: TextClassifierProtocol {
    // Uses CoreML to classify text
}
```

### BaseFunctionClassifier

Specialized classifier that determines if text input should trigger specific functions:

```swift
enum FunctionClassification: String {
    case changeSystemPrompt
    case noOperation
    case rememberName
    case voiceCommand
}

class BaseFunctionClassifier {
    func classify(_ text: String) -> FunctionClassificationResult?
}
```

### TextClassifierRegistry

Registry that manages available classifiers:

```swift
class TextClassifierRegistry {
    static let shared = TextClassifierRegistry()
    func register(classifier: TextClassifierProtocol, forKey key: String)
    func classifier(forKey key: String) -> TextClassifierProtocol?
}
```

### TextClassificationService

Service that coordinates the classification process:

```swift
class TextClassificationService {
    func processUserInput(_ text: String, textClassifierKey: String = "default") -> ProcessedInput
}
```

## Usage Examples

### Basic Usage

```swift
// Initialize the classification service
let classificationService = TextClassifierFactory.createClassificationService()

// Process user input
let result = classificationService.processUserInput("What's the weather like today?")

// Handle the result
switch result.type {
case .function(let functionClass):
    // Handle function command
    
case .text(let textResult):
    // Handle text classification
    
case .error(let error):
    // Handle error
}
```

### Adding a Custom Classifier

```swift
// Register a new classifier
TextClassifierFactory.setupClassifier(modelName: "CustomModel", forKey: "custom")

// Use the custom classifier
let result = classificationService.processUserInput("Input text", textClassifierKey: "custom")
```

## FunctionClassifications Model

The `functionClassifications.mlmodel` provides classification for specific function intents:

- `changeSystemPrompt`: Text requesting a change to the system prompt
- `noOperation`: Regular text with no special function (default)
- `rememberName`: Text requesting to remember user's name
- `voiceCommand`: Text representing a voice command

When text is classified as anything other than `noOperation`, the specific function handling code should be triggered.
