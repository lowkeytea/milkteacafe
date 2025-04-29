/// Represents the current playback state of the KokoroEngine
public enum PlaybackState {
    case idle      // Not playing audio
    case starting  // Preparing to play, but audio hasn't started yet
    case playing   // Audio is actively playing
    case paused    // Audio playback is paused
    case stopping  // In the process of stopping playback
}
