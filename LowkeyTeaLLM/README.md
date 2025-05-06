# LowkeyTeaLLM

LowkeyTeaLLM is a Swift library for integrating LLM capabilities into iOS and macOS applications. It provides a bridge to llama.cpp and supports efficient management of LLM models, contexts, and text-to-speech functionality.

## Core Components

### Llama Bridge System

The Llama Bridge System consists of three main components working together to provide efficient LLM functionality:

1. **LlamaBridge**: The central registry that manages model weights and contexts
2. **LlamaModel**: Represents shared model weights that can be used by multiple contexts
3. **LlamaContext**: Represents a specific conversation or interaction with the model

## LlamaBridge

`LlamaBridge` is an actor that serves as the central registry for managing LLM models and contexts. It provides:

- Shared instance via `LlamaBridge.shared`
- Methods for loading, managing and unloading model weights
- Context management with support for weight sharing
- Sequence ID management for context isolation

```swift
// Basic usage
let bridge = LlamaBridge.shared

// Load a model
await bridge.loadModel(modelPath: "/path/to/model.gguf")

// Get the default context
if let context = await bridge.getDefaultContext() {
    // Use the context for inference
}

// Create a context with shared weights
let modelWeights = try await bridge.loadModelWeights(modelPath: "/path/to/model.gguf")
let context = try await bridge.createSharedContext(id: "chat1", weightId: modelWeights.id)
```

## LlamaModel

`LlamaModel` is an actor that encapsulates shared LLM weights, enabling multiple contexts to use the same model weights without duplicating memory. Key features:

- Thread-safe reference counting to manage model lifecycle
- Efficient memory usage by sharing weights among contexts
- Low overhead context switching

```swift
// Loading a model through LlamaBridge (preferred)
let weights = try await LlamaBridge.shared.loadModelWeights(modelPath: "/path/to/model.gguf")

// Direct access (advanced usage)
let model = try LlamaModel(id: "my-model", path: "/path/to/model.gguf")
```

## LlamaContext

`LlamaContext` is an actor representing a specific chat conversation or inference session. Each context:

- Has its own conversation history and KV cache
- Can share model weights with other contexts
- Manages token generation and sampling
- Supports LoRA adapters for agent switching

```swift
// Get a context from the bridge
let context = LlamaBridge.shared.getContext(id: "chat1", path: "/path/to/model.gguf")

// Initialize with a prompt
await context.completionInit("Once upon a time")

// Generate tokens
var currentToken = 0
while let nextToken = await context.completionLoop(maxTokens: 100, currentToken: &currentToken) {
    print(nextToken, terminator: "")
}

// Add a user message in a chat
await context.appendUserMessage(userMessage: "Hello, how are you?")
```

## Memory Efficiency

The design allows for efficient memory usage through weight sharing:

- Load model weights once with `loadModelWeights()`
- Create multiple contexts with `createSharedContext()`
- Each context has its own state but shares the underlying model weights
- Automatically frees resources when no longer needed via reference counting

---

## Advanced Usage

### Multi-Context Pattern with Shared Weights

One of the most powerful features of LowkeyTeaLLM is the ability to create multiple conversation contexts that share the same model weights, greatly reducing memory usage.

#### Loading Model Weights

First, load model weights as a shared resource that multiple contexts can use:

```swift
// Load the model weights once
let modelPath = "/path/to/model.gguf"
let weights = try await LlamaBridge.shared.loadModelWeights(modelPath: modelPath, weightId: "gemma-7b")
```

#### Creating Multiple Contexts

Then create multiple contexts that use these weights:

```swift
// Create multiple isolated chat contexts sharing the same weights
let context1 = try await LlamaBridge.shared.createSharedContext(id: "chat1", weightId: "gemma-7b")
let context2 = try await LlamaBridge.shared.createSharedContext(id: "chat2", weightId: "gemma-7b")
let thinkingContext = try await LlamaBridge.shared.createSharedContext(id: "thinking", weightId: "gemma-7b")

// Initialize each context
await context1.loadModel(modelPath: modelPath)
await context2.loadModel(modelPath: modelPath)
await thinkingContext.loadModel(modelPath: modelPath)
```

#### Memory Management Strategy

To optimize memory usage:

```swift
// Unload a specific context but keep the weights loaded
await LlamaBridge.shared.unloadContext(id: "thinking")

// Later, recreate the context using the existing weights
let thinkingContext = try await LlamaBridge.shared.createSharedContext(id: "thinking", weightId: "gemma-7b")
await thinkingContext.loadModel(modelPath: modelPath)

// When done with all contexts using these weights, unload the weights
_ = await LlamaBridge.shared.unloadModelWeights(weightId: "gemma-7b")
```

#### Real-World Example: Thinking and Chat Contexts

In MilkteaCafe, this pattern is used to create separate contexts for analysis and chat:

```swift
// Load model weights once
try await LlamaBridge.shared.loadModelWeights(modelPath: path, weightId: modelId)

// Create two contexts sharing weights: chat and thinking
let chatContext = await LlamaBridge.shared.getContext(id: "chat", path: path)
let thinkingContext = await LlamaBridge.shared.getContext(id: "thinking", path: path)

// Initialize both contexts
await chatContext.loadModel(modelPath: path)
await thinkingContext.loadModel(modelPath: path)

// Use thinking context for analysis
var analysisResult = await generateThoughtAnalysis(context: thinkingContext)

// Use chat context for user interaction
await generateResponse(context: chatContext)

// When thinking is no longer needed, unload just that context
await LlamaBridge.shared.unloadContext(id: "thinking")
```

### Working with ResponseGenerator

The `ResponseGenerator` provides a higher-level API for text generation with LlamaContext, including:

- Handling message formatting
- Streaming tokens
- Different response filtering options

#### Basic Usage

```swift
// Create a response generator
let generator = ResponseGenerator.shared

// Generate tokens with pass-through filter (default)
let tokenStream = await generator.generate(
    llama: context,
    history: previousMessages,
    systemPrompt: "You are a helpful assistant.",
    newUserMessage: LlamaMessage(role: .user, content: "Hello!")
)

// Process the token stream
for await token in tokenStream {
    print(token, terminator: "")
}
```

#### Using Different Filters

ResponseGenerator supports different token filters:

```swift
// Sentence filter - emits complete sentences
let sentenceStream = await generator.generate(
    llama: context,
    history: previousMessages,
    systemPrompt: "You are a helpful assistant.",
    newUserMessage: LlamaMessage(role: .user, content: "Tell me a story."),
    filter: SentenceFilter(minLength: 30) // Emit sentences with min length
)

// Process sentences
for await sentence in sentenceStream {
    // Process complete sentences
    print(sentence)
    
    // Optionally send to TTS
    await kokoroEngine.play(sentence)
}

// Full response filter - only emits the entire response at the end
let fullResponseStream = await generator.generate(
    llama: context,
    history: previousMessages,
    systemPrompt: "You are a helpful assistant.",
    newUserMessage: LlamaMessage(role: .user, content: "Hello!"),
    filter: FullResponseFilter()
)

// Wait for the complete response
for await fullResponse in fullResponseStream {
    // Handle the complete response
    print(fullResponse)
}
```

#### Real-World Example: Streaming Chat Response with TTS

In MilkteaCafe, the ResponseGenerator is used with sentence filtering for real-time TTS:

```swift
// Create a chat action group
let actionGroup = FunctionCallActionGroup(viewModel: self)

// Subscribe to chat tokens for live updates and TTS
actionGroup.subscribeToProgress(for: FunctionCallActionGroup.ActionId.chat) { token in
    Task { @MainActor in
        // Update UI with new token
        self.assistantMessage.content += token
        
        // Use TTS for the token
        if token.count > 1 { // Avoid tiny tokens
            await KokoroEngine.sharedInstance.play(token)
        }
    }
}

// Execute the action group which uses ResponseGenerator internally
await actionGroup.execute(with: userMessage)
```

---

## Kokoro Engine

### KokoroEngine

The `KokoroEngine` provides text-to-speech capabilities using the sherpa-onnx framework. It offers a simple interface for generating and playing speech from text.

## Key Features

- Voice selection and configuration
- Streaming audio generation and playback
- Asynchronous operation with completion callbacks
- Playback state management (idle, starting, playing, paused, stopping)

## Basic Usage

```swift
import LowkeyTeaLLM

// Get the shared instance
let kokoroEngine = KokoroEngine.sharedInstance

// Initialize (optional pre-warming)
try await kokoroEngine.initializeGenerator()

// Set voice
await kokoroEngine.setVoice("AF_HEART")

// Play text
await kokoroEngine.play("Hello, world!") {
    print("Playback completed")
}

// Control playback
await kokoroEngine.pause()
await kokoroEngine.resume()
kokoroEngine.stop()
```

## Voice Management

The engine supports multiple voices through the `VoiceConfig` enum:

```swift
// Get available voices
let voices = kokoroEngine.getAvailableVoices()

// Get current voice
let currentVoice = kokoroEngine.getCurrentVoice()
```

## Playback State Observation

You can observe playback state changes using Combine:

```swift
import Combine

// Subscribe to playback state changes
let cancellable = KokoroEngine.playbackBus.publisher
    .sink { state in
        switch state {
        case .idle:
            print("Engine is idle")
        case .starting:
            print("Starting playback")
        case .playing:
            print("Audio is playing")
        case .paused:
            print("Playback paused")
        case .stopping:
            print("Stopping playback")
        }
    }
```

## Resource Management

The engine handles resource allocation and deallocation automatically, but you can explicitly control the lifecycle:

```swift
// Initialize the engine (pre-warming)
try await kokoroEngine.initializeGenerator()

// Release resources when done
kokoroEngine.shutdownGenerator()
```