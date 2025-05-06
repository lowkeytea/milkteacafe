# Kokoro Engine

Kokoro is a high-quality text-to-speech (TTS) engine integrated into LowkeyTeaLLM. It provides seamless, low-latency speech synthesis with support for multiple voices, streaming playback, and efficient resource management.

## Architecture

The Kokoro Engine consists of several key components working together:

1. **KokoroEngine** - Main façade providing a simple API for text-to-speech
2. **AudioGenerator** - Handles text processing and audio synthesis using sherpa-onnx
3. **AudioPlayer** - Manages audio playback with chunking and streaming capabilities
4. **TextChunker** - Breaks text into optimal chunks for real-time processing
5. **VoiceConfig** - Defines available voices and their properties
6. **FifoJobProcessor** - Provides sequential, cancelable job processing
7. **PlaybackStateBus** - Broadcasts playback state changes via Combine

## Voice Configuration

Kokoro supports over 50 different voices across multiple languages and accents. The naming convention follows a pattern:

- First letter: Language code (a=American English, b=British English, j=Japanese, z=Chinese, etc.)
- Second letter: Gender (f=female, m=male)
- Followed by voice name

For example:
- `af_heart` - American Female "Heart" voice
- `bm_george` - British Male "George" voice
- `jf_nezumi` - Japanese Female "Nezumi" voice
- `zm_yunxi` - Chinese Male "Yunxi" voice

```swift
// Access all available voices
let voices = KokoroEngine.sharedInstance.getAvailableVoices()

// Current selection of voices (partial list)
public enum VoiceConfig: Int, CaseIterable {
    // American Female voices
    case afAlloy = 0
    case afAoede = 1
    case afBella = 2
    case afHeart = 3
    // ...and many more
    
    // American Male voices
    case amAdam = 11
    case amEcho = 12
    case amEric = 13
    
    // British voices
    case bfAlice = 20
    case bmDaniel = 24
    
    // Japanese voices
    case jfAlpha = 37
    case jfNezumi = 39
    
    // Chinese voices
    case zfXiaoxiao = 47
    case zmYunxi = 50
    
    // Gets the internal voice name used by the TTS engine
    var voiceName: String { ... }
    
    // Gets a human-friendly display name
    var displayName: String { ... }
}
```

## Basic Usage

```swift
import LowkeyTeaLLM

// Get shared instance
let engine = KokoroEngine.sharedInstance

// Initialize (optional pre-warming)
try await engine.initializeGenerator()

// Check and set voice
let voices = engine.getAvailableVoices()
print("Available voices: \(voices)")

// Set voice
await engine.setVoice("af_heart")  // American Female "Heart" voice

// Play text
await engine.play("Hello, world!") {
    print("Playback completed")
}
```

## Advanced Features

### Measuring Generation Time

```swift
// Track how long speech generation takes
await engine.play(
    "This is a test of speech generation performance.",
    measureTime: { duration in
        print("Generation took \(duration) seconds")
    },
    onComplete: {
        print("Playback finished")
    }
)
```

### Streaming Long Content

The engine automatically breaks text into chunks for streaming playback:

```swift
// Long text is automatically chunked and streamed
let longText = """
    This is a very long passage that will be automatically chunked into 
    smaller pieces for efficient processing. The AudioGenerator uses a 
    TextChunker to split this text into optimal segments, typically between 
    80-250 characters each, prioritizing natural break points like periods 
    and commas. This approach enables low-latency streaming playback while 
    maintaining natural-sounding speech, even for very lengthy content.
    """

await engine.play(longText)
```

### Playback Control

```swift
// Pause ongoing playback
await engine.pause()

// Resume paused playback
await engine.resume()

// Stop and cancel all pending speech
engine.stop()
```

### Playback State Observation

Monitor playback state changes in real-time using Combine:

```swift
import Combine

class SpeechMonitor {
    private var cancellables = Set<AnyCancellable>()
    
    func monitorPlaybackState() {
        KokoroEngine.playbackBus.publisher
            .sink { state in
                switch state {
                case .idle:
                    print("Ready for new speech")
                case .starting:
                    print("Processing speech, preparing to play")
                case .playing:
                    print("Currently speaking")
                case .paused:
                    print("Speech paused")
                case .stopping:
                    print("Speech stopping")
                }
            }
            .store(in: &cancellables)
    }
}
```

## Technical Architecture

### KokoroEngine

The main engine facade orchestrates the entire TTS pipeline:

- Manages initialization and resource lifecycle
- Provides a simple play/pause/resume/stop API
- Handles voice configuration
- Broadcasts state changes via PlaybackStateBus

### AudioGenerator

Responsible for text-to-speech conversion:

- Uses SherpaOnnx for high-quality TTS synthesis
- Loads and manages TTS models and voice data
- Processes text chunks asynchronously
- Provides a queuing system for batched processing

### AudioPlayer

Handles audio streaming and playback:

- Manages AVAudioEngine setup and configuration
- Creates PCM buffers from generated audio samples
- Handles audio session management
- Provides real-time audio streaming with chunking
- Supports pause/resume functionalities

### TextChunker

Optimizes text segmentation for efficient processing:

- Breaks text into chunks of configurable size (default 80-250 chars)
- Prioritizes natural breaks like periods and commas
- Ensures optimal chunk size for low-latency playback

### Resource Management

The engine automatically manages resources:

```swift
// Pre-warming (optional)
try await engine.initializeGenerator()

// Check pending operations
let entranceCount = await engine.getPendingEntranceCount()
let generationCount = await engine.getPendingGenerationCount()

// Log queue statistics
await engine.logPendingCounts()

// Explicitly shutdown when completely done
engine.shutdownGenerator()
```

## Internal Pipeline

1. **Text Input**: User provides text via `play()`
2. **Text Chunking**: `TextChunker` breaks text into optimal segments
3. **Audio Generation**: Each chunk is sent to `AudioGenerator` for TTS conversion
4. **Audio Queuing**: Generated audio is enqueued in the `AudioPlayer`
5. **Streaming Playback**: Audio is played in real-time as chunks complete
6. **State Broadcasting**: State changes are published via `PlaybackStateBus`
7. **Completion Callbacks**: User is notified when playback completes

## Best Practices

1. **Voice Selection**: Choose appropriate voices for your app's context
   ```swift
   // For personalized voices
   await engine.setVoice("af_heart")  // Warm, friendly American female
   
   // For formal applications
   await engine.setVoice("bm_daniel") // Professional British male
   
   // For language-specific content
   await engine.setVoice("jf_nezumi") // Japanese female for Japanese text
   ```

2. **Resource Management**: Initialize early, release when done
   ```swift
   // Pre-warm during app startup
   try? await engine.initializeGenerator()
   
   // Release in app background/termination
   engine.shutdownGenerator()
   ```

3. **Sentence-Based Playback**: For best results with TTS and voice inflection
   ```swift
   // Better to play complete sentences
   await engine.play("Hello! How are you today?")
   
   // Rather than fragments
   await engine.play("Hello!")
   await engine.play("How are you today?")
   ```

4. **State Handling**: Always observe playback state for UI updates
   ```swift
   // UI indicators for speech
   KokoroEngine.playbackBus.publisher
       .receive(on: DispatchQueue.main)
       .sink { [weak self] state in
           self?.updateSpeechIndicator(isActive: state != .idle)
       }
       .store(in: &cancellables)
   ```

5. **Error Handling**: Properly handle TTS failures
   ```swift
   do {
       try await engine.initializeGenerator()
       await engine.play("Hello world")
   } catch {
       // Gracefully handle TTS errors
       print("TTS failed: \(error.localizedDescription)")
   }
   ```

## Performance Considerations

1. **Pre-warming**: Initialize the engine at app startup to reduce initial latency
2. **Chunk Size**: Balance between responsive start (smaller chunks) and processing efficiency (larger chunks)
3. **Voice Switching**: Changing voices may require engine re-initialization if lexicon changes
4. **Memory Usage**: Each voice has its own memory footprint; release resources when not in use
5. **Concurrent Requests**: The engine properly queues and serializes multiple play requests