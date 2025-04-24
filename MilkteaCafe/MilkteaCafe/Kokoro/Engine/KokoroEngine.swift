import Foundation
import Combine
// MARK: - Playback‑state event bus (AsyncStream)

// Broadcast playback‑state changes via Combine CurrentValueSubject.
public final class PlaybackStateBus {
    private let subject: CurrentValueSubject<PlaybackState, Never>
    /// Publisher for playback‑state events.
    public var publisher: AnyPublisher<PlaybackState, Never> { subject.eraseToAnyPublisher() }

    public static let shared = PlaybackStateBus()

    private init() {
        subject = CurrentValueSubject(KokoroEngine.sharedInstance.playbackState)
    }

    /// Send a new playback state to all subscribers.
    public func send(_ state: PlaybackState) {
        subject.send(state)
    }
}

extension KokoroEngine {
    /// Global bus that publishes every playback‑state change.
    public static let playbackBus = PlaybackStateBus.shared
}

/// Main entry point for the Kokoro TTS engine, providing a simple facade for text-to-speech functionality.
public class KokoroEngine {
    private let generator: AudioGenerator
    private let audioPlayer: AudioPlayer
    private let logger: KokoroLogger
    static let sharedInstance = KokoroEngine()
    
    /// Current playback state
    private var _playbackState: PlaybackState = .idle
    
    /// Get the current playback state
    public var playbackState: PlaybackState {
        return _playbackState
    }
    
    // Helper struct to package text and callbacks
    private struct TextEntrance {
        let text: String
        let measureTime: ((TimeInterval) -> Void)?
        let onComplete: (() -> Void)?
    }
    
    // FIFO processor to handle text entrance serialization
    private lazy var entranceProcessor: FifoJobProcessor<TextEntrance, Void> = { [unowned self] in
        FifoJobProcessor(
            jobToRun: { [weak self] entrance in
                guard let self = self else { return }
                if self._playbackState == .idle {
                    // First sentence path - needs initialization
                    try await self.generator.initialize()
                    await self.submitTextToPlayer(entrance)
                } else {
                    // Subsequent sentence path - just queue
                    await self.submitTextToPlayer(entrance)
                }
            },
            onResult: { _, _ in },
            onError: { [weak self] entrance, error in
                self?.logger.e("Error processing text entrance: \(error)", error: error)
                entrance.onComplete?()
            }
        )
    }()
    
    /// Creates a KokoroEngine; may throw if setup of AudioGenerator fails.
    public init() {
        self.logger = KokoroLogger.create(for: KokoroEngine.self)
        self.generator = try! AudioGenerator(logger: logger)
        self.audioPlayer = AudioPlayer(
            audioGenerator: generator,
            initialMinChunkLength: 25,
            logger: logger
        )
    }
    
    /// Returns a list of all available voice names.
    public func getAvailableVoices() -> [String] {
        return VoiceConfig.allCases.map { $0.voiceName }
    }
    
    /// Sets the voice to use for subsequent TTS operations.
    /// If the voiceName is not found, defaults to AF_HEART.
    public func setVoice(_ voiceName: String) async {
        let voice = VoiceConfig.allCases.first { $0.voiceName == voiceName } ?? .afHeart
        logger.i("Setting voice to: \(voice.voiceName)")
        await generator.setVoice(voice)
    }
    
    /// Returns the name of the currently selected voice.
    public func getCurrentVoice() -> String {
        return generator.getVoice()
    }
    
    /// Initializes the TTS engine by unpacking assets and loading the model.
    /// Call this before play if you want to pre-warm the engine.
    public func initializeGenerator() async throws {
        logger.d("Initializing TTS engine for playback")
        try await generator.initialize()
    }
    
    /// Shuts down the TTS engine and releases resources.
    public func shutdownGenerator() {
        generator.shutdown()
    }
    
    /// Converts text to speech and plays the audio.
    /// Ensures the TTS engine is initialized, then streams audio via AudioPlayer.
    public func play(
           _ text: String,
           measureTime: ((TimeInterval) -> Void)? = nil,
           onComplete: (() -> Void)? = nil
    ) async {
        // Package the text and callbacks
        let entrance = TextEntrance(
            text: text,
            measureTime: measureTime,
            onComplete: onComplete
        )
        
        // Submit to entrance processor - this serializes the queueing
        await entranceProcessor.submit(entrance)
    }
    
    // Helper to submit text to player after serialization
    private func submitTextToPlayer(_ entrance: TextEntrance) async {
        if _playbackState == .idle {
            logger.d("Playing text: '\(entrance.text.prefix(50))…'")
            updatePlaybackState(.starting)

            audioPlayer.onPlaybackStarted = { [weak self] in
                self?.updatePlaybackState(.playing)
            }
        }

        do {
            try await audioPlayer.playSentence(
                text: entrance.text,
                measureTime: entrance.measureTime,
                onPlaybackFinished: { [weak self] in
                    self?.updatePlaybackState(.idle)
                    entrance.onComplete?()
                }
            )
        } catch {
            logger.e("Playback error: \(error)", error: error)
            updatePlaybackState(.idle)
            entrance.onComplete?()
        }
    }

    /// Stops any ongoing playback.
    public func stop() {
        updatePlaybackState(.stopping)
        audioPlayer.stop()
        updatePlaybackState(.idle)
        // Clear any pending text entrances so new play() calls run immediately
        Task { await entranceProcessor.clearQueue() }
        // Debug: log current queue sizes asynchronously
        Task { await logPendingCounts() }
    }

    /// Debug: returns number of pending text entrances in the engine queue.
    public func getPendingEntranceCount() async -> Int {
        return await entranceProcessor.getQueueSize()
    }

    /// Debug: returns number of pending audio generation jobs.
    public func getPendingGenerationCount() async -> Int {
        return await generator.getPendingJobCount()
    }

    /// Debug: logs all pending queue sizes.
    public func logPendingCounts() async {
        let entranceCount = await entranceProcessor.getQueueSize()
        let generationCount = await generator.getPendingJobCount()
        let playbackCount = await audioPlayer.getPendingPlaybackCount()
        logger.i("🔍 Debug pending queues — entrance: \(entranceCount), generation: \(generationCount), playback: \(playbackCount)")
    }

    /// Pauses audio playback; generation keeps running so resume is instant.
    public func pause() async {
        await audioPlayer.pause()
        updatePlaybackState(.paused)
    }
    
    /// Resumes playback after a pause.
    public func resume() async {
        await audioPlayer.resume()
        updatePlaybackState(.playing)
    }
    
    /// Updates the playback state and notifies observers
    private func updatePlaybackState(_ newState: PlaybackState) {
        guard _playbackState != newState else { return }
        
        logger.d("KokoroEngine: State changing from \(_playbackState) to \(newState)")
        _playbackState = newState
        
        // Handle specific state transitions
        if newState == .stopping {
            // When stopping, make sure audio player is properly reset
            audioPlayer.stop()
        } else if newState == .starting && _playbackState == .idle {
            // When starting from idle, ensure proper initialization
            logger.d("KokoroEngine: Ensuring proper audio setup for new playback")
            Task {
                // Force audio session configuration
                await AudioSessionManager.shared.configureGlobalSession()
                // Ensure engine is running
                AudioSessionManager.shared.ensureEngineRunning()
            }
        }
        
        // Emit state change to listeners
        logger.d("KokoroEngine: About to send state: \(newState)")
        KokoroEngine.playbackBus.send(newState)
        logger.d("KokoroEngine: Sent state: \(newState)")
    }
}
