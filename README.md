# LowkeyTeaLLM & Milktea Cafe Sample

A Swift platform for integrating large language models and text-to-speech capabilities on Apple platforms. LowkeyTeaLLM combines the power of llama.cpp for local LLM inference with sherpa-onnx for high-quality text-to-speech.

## Demo

https://github.com/lowkeytea/milkteacafe/assets/MilkteaCafe.mp4

## Overview

LowkeyTeaLLM is a lightweight native Swift library that wraps llama.cpp, aiming to emulate core features of llama-server while minimizing overhead. The library provides an efficient way to run LLMs locally on Apple devices with optimized memory usage through weight sharing.

MilkteaCafe is a sample app demonstrating advanced functionality:

- **Action System**: Chain multiple LLM interactions together
- **Function Calling**: Use LLMs to dynamically invoke functions based on user input
- **Model Sharing**: Run multiple LLM contexts with shared weights
- **ML Model Integration**: Utilize lightweight classifiers to optimize LLM usage

## Key Demonstrations

The MilkteaCafe sample demonstrates:

1. **Efficient Model Usage**: Runs Gemma 3 4B with two shared instances:
   - Main instance for user chat interaction
   - Secondary instance for function calling when needed

2. **Smart Response Optimization**:
   - Text classifier ML model determines if a response should be "short" or "long"
   - Makes the model more conversational without complex system prompts

3. **Intelligent Function Calling**:
   - Uses a lightweight ML model to predict if the user query needs a function call
   - Only activates the secondary LLM instance when function calls are likely needed
   - Conserves resources on mobile devices

4. **Implemented Function Calls**:
   - **Voice Control**: Turn TTS voice on and off through natural language requests
   - **System Prompt Management**: Change the LLM's behavior through requests like "be more sarcastic"
   - **Memory Management**: Remember user and LLM names, persisting across chat resets
   - **No-Op Classification**: Intelligently decides when no function call is needed

## Components

### LowkeyTeaLLM

[LowkeyTeaLLM](LowkeyTeaLLM/README.md) is a Swift library that provides:

- Integration with llama.cpp for LLM inference
- Memory-efficient model management with weight sharing
- Context management for conversations
- Text-to-speech via the Kokoro Engine

Key features:

- **LlamaBridge** - Central registry for managing models and contexts
- **LlamaModel** - Shared model weights for memory efficiency
- **LlamaContext** - Individual conversation contexts
- **KokoroEngine** - Text-to-speech capabilities

Documentation:
- [LowkeyTeaLLM Documentation](LowkeyTeaLLM/README.md)
- [KokoroEngine Documentation](LowkeyTeaLLM/KokoroEngine.md)

## Getting Started

### Prerequisites

- Xcode 15.0+
- macOS 13.0+ or iOS 16.0+
- Git with LFS support (for model downloading)
- CMake (for building dependencies)

### Setup and Building

1. **Clone the repository with submodules**

```bash
git clone https://github.com/lowkeytea/milkteacafe.git
cd milkteacafe
git submodule update --init --recursive
```

2. **Build dependencies**

The project includes two build scripts for the required dependencies:

```bash
# Build llama.cpp
./build-llama.sh

# Build sherpa-onnx for iOS/macOS
./build-sherpa-ios.sh
```

3. **Download the Kokoro TTS model**

Download the required files from the [sherpa-onnx Kokoro model page](https://k2-fsa.github.io/sherpa/onnx/tts/pretrained_models/kokoro.html#download-the-model):

```bash
# Create the KokoroData directory
mkdir -p MilkteaCafe/KokoroData

# Download and extract files into the KokoroData directory
cd MilkteaCafe/KokoroData

# Download model files (use the links from the sherpa-onnx page)
curl -LO https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro.onnx
curl -LO https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/tokens.txt
curl -LO https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/voices.bin

# Download lexicon files
curl -LO https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/lexicon-gb-en.txt
curl -LO https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/lexicon-us-en.txt

# Download espeak-ng-data (3MB) for pronunciation
curl -L https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/espeak-ng-data.tar.bz2 | tar xf -
```

4. **Open the project in Xcode**

```bash
open MilkteaCafe/MilkteaCafe.xcworkspace
```

5. **Build and run the project**

Select your target device and click the Run button in Xcode. Note that the first run may take longer as it downloads the Gemma 3 4B model.

### LLM Models

The app is configured to use Google's Gemma 3 4B model by default. The app will automatically download the model file on first launch. If you want to use different models:

1. Update the model paths in `ModelManager.swift`
2. Place your GGUF model files in the application's document directory

## Basic Usage

### LLM Integration

```swift
import LowkeyTeaLLM

// Initialize LLM
let bridge = LlamaBridge.shared
await bridge.loadModel(modelPath: "/path/to/model.gguf")

// Send messages
if let context = await bridge.getDefaultContext() {
    await context.appendUserMessage(userMessage: "Hello!")
    
    // Generate response
    var currentToken = 0
    var response = ""
    while let token = await context.completionLoop(maxTokens: 100, currentToken: &currentToken) {
        response += token
    }
    
    // Text-to-speech
    let tts = KokoroEngine.sharedInstance
    await tts.play(response)
}
```

### Text-to-Speech

```swift
// Get available voices
let voices = KokoroEngine.sharedInstance.getAvailableVoices()

// Set voice - examples include "af_heart" (American Female), "bm_daniel" (British Male)
await KokoroEngine.sharedInstance.setVoice("af_heart")

// Play text with completion callback
await KokoroEngine.sharedInstance.play("Hello, world!") {
    print("Speech completed")
}
```

## Advanced Features

### Memory-Efficient Model Management

```swift
// Load model weights once
let modelPath = "/path/to/model.gguf"
let weights = try await LlamaBridge.shared.loadModelWeights(modelPath: modelPath, weightId: "gemma-7b")

// Create multiple contexts sharing the same model weights
let chatContext = try await LlamaBridge.shared.createSharedContext(id: "chat", weightId: "gemma-7b")
let analysisContext = try await LlamaBridge.shared.createSharedContext(id: "analysis", weightId: "gemma-7b")

// Initialize both contexts
await chatContext.loadModel(modelPath: modelPath)
await analysisContext.loadModel(modelPath: modelPath) 

// Use each context independently
await chatContext.appendUserMessage(userMessage: "Tell me a story")
await analysisContext.appendUserMessage(userMessage: "Analyze this sentence")

// Memory optimization: unload context but keep weights
await LlamaBridge.shared.unloadContext(id: "analysis")
```

### Action and Function Call System

MilkteaCafe demonstrates a powerful Action and Function Call system. Here's a simplified example:

```swift
// Define a function call specification
let functionSpec = FunctionCallSpec(
    name: "changeVoiceState", 
    description: "Enable or disable text-to-speech voice output",
    parameters: [
        Parameter(name: "enabled", type: .boolean, description: "Whether to enable voice")
    ]
)

// Register the function
FunctionRegistry.shared.registerFunction(functionSpec) { params in
    guard let enabled = params["enabled"] as? Bool else { return FunctionResponse.error("Missing parameter") }
    
    // Perform the actual function
    UserDefaults.standard.set(enabled, forKey: "ttsEnabled")
    NotificationCenter.default.post(name: .voiceSupportSettingChanged, 
                                  object: nil, 
                                  userInfo: ["enabled": enabled])
    
    return FunctionResponse.success("Voice \(enabled ? "enabled" : "disabled")")
}

// Create an action group
let actionGroup = FunctionCallActionGroup(viewModel: chatViewModel)

// Execute the action group with a user message
await actionGroup.execute(with: userMessage)
```

For more examples of the Function Call system, check the sample app's implementation in:
- `FunctionCallActionGroup.swift`
- `FunctionRegistry.swift`
- `SystemPromptFunctionHandler.swift`

## Project Structure

- **LowkeyTeaLLM/** - Core library with LLM and TTS capabilities
  - **Sources/Llama/** - LLM integration with llama.cpp
  - **Sources/Kokoro/** - TTS integration with sherpa-onnx
- **MilkteaCafe/** - Sample application using the library
  - **ViewModels/** - Application logic
  - **Views/** - SwiftUI interface components
  - **Llama/** - LLM management
  - **Functions/** - Function call implementations

## Building from Source

### Building llama.cpp

The `build-llama.sh` script builds the llama.cpp library with optimizations for Apple platforms:

```bash
#!/bin/bash
cd llama.cpp
mkdir -p build
cd build
cmake .. -DBUILD_SHARED_LIBS=OFF -DLLAMA_METAL=ON
cmake --build . --config Release
cd ../..
```

### Building sherpa-onnx

The `build-sherpa-ios.sh` script builds the sherpa-onnx library for iOS/macOS:

```bash
#!/bin/bash
cd sherpa-onnx
./build-ios.sh
cd ..
```

## Production Examples

LowkeyTeaLLM is used in production apps:
- [What the Fluff](https://apps.apple.com/us/app/what-the-fluff/id6741672065) - An iOS app with advanced RAG capabilities

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.