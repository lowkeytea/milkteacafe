import Foundation
import AVFoundation

/// Streams TTS playback in a chunk → generate → play pipeline.
public class AudioPlayer {
    // MARK: - Properties
    private let audioGenerator: AudioGenerator
    public var minChunkLength: Int {
        didSet {
            // Clamp to a sensible floor and avoid writing to ourselves repeatedly
            if minChunkLength < 10 { minChunkLength = 10 }
        }
    }
    private let logger: KokoroLogger
    // Identifier for current playback session, used to cancel in-flight callbacks
    private var currentSessionId: UUID?
    private var sentenceContinuation: CheckedContinuation<Void, Error>?
    
    // Playback and metrics
    private var totalChunks = 0
    private var processedChunks = 0
    private var chunkingCompleted = false
    private var firstChunkTime: TimeInterval?
    private var playStartTime: TimeInterval?
    private var onComplete: (() -> Void)?
    private var measureTime: ((TimeInterval) -> Void)?
    private let audioEngine = AudioSessionManager.shared.audioEngine
    private var hasPlaybackStarted = false
    public var onPlaybackStarted: (@Sendable () -> Void)?
    
    // Safety flags
    private var isNodeAttached = false
    private var audioSetupInProgress = false
    
    // Core AVAudio components
    private let audioPlayer = AVAudioPlayerNode()
    private let mixer = AVAudioMixerNode()
    
    // Pause state
    private var isPaused = false
    
    // Sequential playback queue
    private lazy var playbackProcessor: FifoJobProcessor<SherpaOnnxGeneratedAudioWrapper, Void> = { [unowned self] in
        FifoJobProcessor(
            jobToRun: { [weak self] audio in
                guard let self = self else { return }
                try await self.playAudioInternal(audio)
            },
            onResult: { [weak self] _, _ in
                self?.checkCompletion()
            },
            onError: { [weak self] _, error in
                self?.logger.e("Playback error: \(error)", error: error)
                self?.checkCompletion()
            }
        )
    }()
    
    // Fixed sample rate for consistency
    private let fixedSampleRate: Double = 24000.0
    
    // MARK: - Initialization
    public init(
        audioGenerator: AudioGenerator,
        initialMinChunkLength: Int = 15,
        logger: KokoroLogger = KokoroLogger.create(for: AudioPlayer.self)
    ) {
        self.audioGenerator = audioGenerator
        self.minChunkLength = max(10, initialMinChunkLength)
        self.logger = logger
        
        // Initialize audio engine and player node
        Task {
            await setupAudioNodesAndConnections()
        }
    }
    
    // MARK: - Public API
    
    /// Generate *all* chunks for one sentence and enqueue them in order,
    /// then return as soon as the **last** chunk is queued.
    /// Playback continues in the background.
    public func playSentence(
        text: String,
        measureTime: ((TimeInterval) -> Void)? = nil,
        onPlaybackFinished: (() -> Void)? = nil
    ) async throws {

        // set up per‑sentence bookkeeping
        currentSessionId   = UUID()
        onComplete         = onPlaybackFinished
        self.measureTime   = measureTime
        processedChunks    = 0
        totalChunks        = 0
        chunkingCompleted  = false
        playStartTime      = CACurrentMediaTime()

        try await withCheckedThrowingContinuation { cont in
            self.sentenceContinuation = cont
            let mySession = currentSessionId          // capture for safety

            audioGenerator.generateAudioForSentence(
                text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                onAudioGenerated: { [weak self] audio in
                    guard let self = self, self.currentSessionId == mySession else { return }
                    totalChunks += 1
                    Task { await self.playbackProcessor.submit(audio) }
                },
                onComplete: { [weak self] in
                    guard let self = self, self.currentSessionId == mySession else { return }
                    self.sentenceContinuation = nil
                    chunkingCompleted = true
                    cont.resume()                     // ✅ generation for this sentence finished
                },
                onError: { [weak self] error in
                    guard let self = self, self.currentSessionId == mySession else { return }
                    self.sentenceContinuation = nil
                    cont.resume(throwing: error)
                }
            )
        }
    }
    /// Begin streaming playback for `text`. Non-blocking; audio starts as soon as the first chunk is generated.
    public func play(
        text: String,
        onSuccess: @escaping (SherpaOnnxGeneratedAudioWrapper) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            logger.w("Skipping blank text submission.")
            return
        }
        
        // Use currentSessionId to track this request
        let mySession = currentSessionId
        
        // Process the full sentence atomically
        audioGenerator.generateAudioForSentence(
            text: trimmed,
            onAudioGenerated: { [weak self] audio in
                guard let self = self, self.currentSessionId == mySession else { return }
                // Each chunk's audio gets submitted to playback queue
                Task { await self.playbackProcessor.submit(audio) }
            },
            onComplete: { [weak self] in
                guard let self = self, self.currentSessionId == mySession else { return }
                self.logger.d("Completed processing sentence: '\(trimmed.prefix(30))...'")
            },
            onError: { [weak self] error in
                guard let self = self, self.currentSessionId == mySession else { return }
                onError(error)
            }
        )
    }
    
    // Add enqueue to allow appending new text segments into the current playback
    public func enqueue(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            logger.w("Skipping blank text submission.")
            return
        }
        
        // Use currentSessionId to track this request
        let mySession = currentSessionId
        
        audioGenerator.generateAudioForSentence(
            text: trimmed,
            onAudioGenerated: { [weak self] audio in
                guard let self = self, self.currentSessionId == mySession else { return }
                Task { await self.playbackProcessor.submit(audio) }
            },
            onComplete: { [weak self] in
                guard let self = self, self.currentSessionId == mySession else { return }
                self.logger.d("Completed processing enqueued sentence: '\(trimmed.prefix(30))...'")
            },
            onError: { [weak self] error in
                guard let self = self, self.currentSessionId == mySession else { return }
                self.logger.e("Error processing enqueued sentence", error: error)
            }
        )
    }
    
    // MARK: - Pause / Resume
    
    /// Pauses current playback while letting audio generation continue.
    public func pause() async {
        guard !isPaused else { return }
        logger.i("Pause requested.")
        isPaused = true
        audioPlayer.pause()
        // also pause the sequential playback queue so we don't schedule
        // additional buffers while playback is halted
        await playbackProcessor.pause()
    }
    
    /// Resumes playback from the point where it was paused.
    public func resume() async {
        guard isPaused else { return }
        logger.i("Resume requested.")
        isPaused = false
        // restart the queue first so new buffers get scheduled again
        await playbackProcessor.resume()
        audioPlayer.play()
    }
    
    /// Stop playback and clear queues.
    public func stop() {
        logger.i("Stop requested.")
        if let cont = sentenceContinuation {
            cont.resume(throwing: CancellationError())
            sentenceContinuation = nil
        }
        // Cancel the session to drop in-flight callbacks
        currentSessionId = nil
        
        // First, stop the AVAudioPlayerNode
        audioPlayer.stop()
        audioPlayer.reset()
        
        // Make sure we clear all our state flags
        hasPlaybackStarted = false
        isPaused = false
        
        // Clear the audio generation queue
        audioGenerator.clearPendingJobs()
        
        // Clear the playback queue and make sure it's not in a paused state
        Task {
            await playbackProcessor.clearQueue()
            // do not resume after stop, so any late submits are ignored
        }
        
        // Instead of pausing the engine, stop and restart it to ensure clean state
        if AudioSessionManager.shared.audioEngine.isRunning {
            AudioSessionManager.shared.audioEngine.stop()
            
            // Short delay to ensure engine fully stops
            Task {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                AudioSessionManager.shared.ensureEngineRunning()
            }
        }
        
        resetState(fullCleanup: true)
    }
    
    /// Debug: returns number of audio chunks pending playback in the queue.
    public func getPendingPlaybackCount() async -> Int {
        return await playbackProcessor.getQueueSize()
    }
    
    // MARK: - Internal Helpers
    
    private func setupAudioNodesAndConnections() async {
        // Stop any existing operations first
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.reset()
            logger.d("🔄 Audio engine stopped and reset before node setup")
        }
        
        // Detach existing nodes if needed
        await detachAudioNodes()
        
        // Use the shared manager to attach nodes
        AudioSessionManager.shared.attachNodeIfNeeded(audioPlayer)
        AudioSessionManager.shared.attachNodeIfNeeded(mixer)
        
        let format = AVAudioFormat(standardFormatWithSampleRate: 24000.0, channels: 2)!
        
        // Set up connections
        audioEngine.connect(audioPlayer, to: mixer, format: format)
        audioEngine.connect(mixer, to: audioEngine.mainMixerNode, format: format)
        
        // Prepare engine
        audioEngine.prepare()
        
        // Mark as attached
        isNodeAttached = true
        
        // Make sure engine is running
        if !AudioSessionManager.shared.ensureEngineRunning() {
            logger.w("⚠️ AudioProcessingManager: Failed to start audio engine during setup")
        } else {
            logger.d("✅ AudioProcessingManager: Audio setup complete - engine is running")
        }
    }
    
    /**
     * Safely detaches audio nodes
     */
    private func detachAudioNodes() async {
        if isNodeAttached {
            AudioSessionManager.shared.detachNodeIfNeeded(audioPlayer)
            AudioSessionManager.shared.detachNodeIfNeeded(mixer)
            isNodeAttached = false
            logger.d("🔄 AudioProcessingManager: Detached audio nodes")
        }
    }
    
    private func resetState(fullCleanup: Bool) {
        // Always clear bookkeeping
        isPaused            = false
        hasPlaybackStarted  = false
        processedChunks     = 0
        totalChunks         = 0
        chunkingCompleted   = false
        playStartTime       = nil
        firstChunkTime      = nil
        onComplete          = nil
        measureTime         = nil

        if fullCleanup {
            audioPlayer.stop()
            audioPlayer.reset()
            audioGenerator.clearPendingJobs()
            Task { await playbackProcessor.clearQueue() }
            logger.d("Playback state **fully** reset.")
        } else {
            logger.d("Playback counters reset (engine/player left running).")
        }
    }
    
    private func checkCompletion() {
        processedChunks += 1
        if chunkingCompleted && processedChunks >= totalChunks {
            logger.i("All audio processed and played.")
            onComplete?()
            resetState(fullCleanup: false)
        }
    }
    
    private func createPCMBuffer(from output: SherpaOnnxGeneratedAudioWrapper) -> AVAudioPCMBuffer? {
        guard let audioFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 24000.0,
            channels: 2,
            interleaved: false
        ) else {
            logger.e("❌ TTSGenerationManager: Failed to create AVAudioFormat")
            return nil
        }
        
        let frameCount = AVAudioFrameCount(output.n)
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: frameCount) else {
            logger.e("❌ TTSGenerationManager: Failed to create AVAudioPCMBuffer")
            return nil
        }

        pcmBuffer.frameLength = frameCount
        let bufferSize = Int(frameCount) * MemoryLayout<Float>.size
        memcpy(pcmBuffer.floatChannelData![0], output.samples, bufferSize)
        return pcmBuffer
    }
    
    private func playAudioInternal(_ audio: SherpaOnnxGeneratedAudioWrapper) async throws {
        logger.d("Playing audio chunk")
        guard !audio.samples.isEmpty else {
            logger.w("Empty audio; skipping.")
            return
        }
        
        // Build a PCM buffer in the generator's native format (mono @ fixedSampleRate)
        guard let buffer = createPCMBuffer(from: audio) else {
            logger.e("PCM buffer creation failed")
            return
        }
        let bufferDuration = Double(buffer.frameLength) / buffer.format.sampleRate
        
        // Check if this is the first buffer before the continuation
        let isFirstBuffer = !hasPlaybackStarted && !audioPlayer.isPlaying
        
        // Make sure the engine is running before scheduling
        if !AudioSessionManager.shared.audioEngine.isRunning {
            logger.d("Audio engine not running, attempting to start...")
            if !AudioSessionManager.shared.ensureEngineRunning() {
                logger.e("Failed to start audio engine, cannot play audio chunk")
                return
            }
        }
        
        // If player node is not attached to the engine, reattach it
        if !(audioPlayer.engine?.isRunning ?? false) {
            logger.d("AudioPlayer node needs reattachment, setting up nodes...")
            await setupAudioNodesAndConnections()
        }
        
        // Schedule and play the buffer, then block until it's fully played back
        await withCheckedContinuation { continuation in
            audioPlayer.scheduleBuffer(
                buffer,
                at: nil,
                options: [],
                completionCallbackType: .dataPlayedBack
            ) { [self] _ in
                Task {
                    try? await Task.sleep(nanoseconds: UInt64(0.05 * 1_000_000_000)) // 50ms safety margin
                    logger.d("Buffer fully played back after \(bufferDuration) seconds")
                    continuation.resume()
                }
            }
            
            // Force check if player is in a valid state to play
            if !audioPlayer.isPlaying {
                audioPlayer.play()
                logger.d("Audio player node started playing")
                
                // If this is the first buffer played, notify via callback on main thread
                if isFirstBuffer {
                    hasPlaybackStarted = true
                    let callback = onPlaybackStarted
                    Task { @MainActor in
                        callback?()
                    }
                }
            }
        }
    }
}
