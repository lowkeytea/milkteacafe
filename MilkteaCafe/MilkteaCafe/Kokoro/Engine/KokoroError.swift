import Foundation

/// Errors specific to the AudioGenerator component.
public enum AudioGeneratorError: LocalizedError {
    case engineNotInitialized
    case initializationFailed(reason: String)
    case missingResource(name: String)
    case generationFailed(underlyingError: Error)

    public var errorDescription: String? {
        switch self {
        case .engineNotInitialized:
            return "The TTS engine has not been initialized. Call initialize() first."
        case .initializationFailed(let reason):
            return "Failed to initialize the TTS engine: \(reason)"
        case .missingResource(let name):
            return "A required resource file is missing: \(name)"
        case .generationFailed(let underlyingError):
            return "Audio generation failed: \(underlyingError.localizedDescription)"
        }
    }
}

/// Errors specific to the AudioPlayer component.
public enum AudioPlayerError: LocalizedError {
    case bufferCreationFailed
    case audioFormatCreationFailed
    case engineStartFailed(underlyingError: Error)
    case playbackFailed(underlyingError: Error)
    case invalidAudioData

    public var errorDescription: String? {
        switch self {
        case .bufferCreationFailed:
            return "Failed to create AVAudioPCMBuffer."
        case .audioFormatCreationFailed:
            return "Failed to create AVAudioFormat."
        case .engineStartFailed(let underlyingError):
            return "Failed to start the AVAudioEngine: \(underlyingError.localizedDescription)"
        case .playbackFailed(let underlyingError):
            return "Audio playback failed: \(underlyingError.localizedDescription)"
        case .invalidAudioData:
            return "Received invalid or empty audio data."
        }
    }
}

/// Errors specific to the KokoroEngine facade.
public enum KokoroEngineError: LocalizedError {
    case setupFailed(underlyingError: Error)
    case playbackSetupFailed(underlyingError: Error)

    public var errorDescription: String? {
        switch self {
        case .setupFailed(let underlyingError):
            return "Failed to set up KokoroEngine: \(underlyingError.localizedDescription)"
        case .playbackSetupFailed(let underlyingError):
            return "Failed to set up for playback: \(underlyingError.localizedDescription)"
        }
    }
}
