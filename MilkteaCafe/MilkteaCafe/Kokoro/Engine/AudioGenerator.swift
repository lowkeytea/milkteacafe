import Foundation

/// Manages text-to-speech audio generation using the ONNX runtime and a FIFO queue.
public class AudioGenerator {
    private struct SentenceRequest {
        let chunks: [String]
        let onComplete: () -> Void
        let onError: (Error) -> Void
        let onAudioGenerated: (SherpaOnnxGeneratedAudioWrapper) -> Void
    }
    
    // MARK: - Properties
    private let logger: KokoroLogger
    private var tts: SherpaOnnxOfflineTtsWrapper?
    private let resourceProvider = ResourceProvider()
    private var currentVoice: VoiceConfig = .afHeart
    private lazy var jobProcessor: FifoJobProcessor<SentenceRequest, Void> = { [unowned self] in
        FifoJobProcessor(
            jobToRun: { [weak self] request in
                guard let self = self, let engine = self.tts else {
                    throw NSError(
                        domain: "AudioGenerator",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "TTS engine not initialized."]
                    )
                }
                
                // Process each chunk in the sentence sequentially
                for chunk in request.chunks {
                    // Check for cancellation before starting each chunk
                    try Task.checkCancellation()
                    self.logger.d("Generating audio for chunk: '\(chunk.prefix(30))...' with voice \(self.currentVoice.rawValue)")
                    let audio = autoreleasepool {
                        engine.generate(text: chunk, sid: self.currentVoice.rawValue, speed: 1.2)
                    }
                    // Send the audio piece to playback
                    request.onAudioGenerated(audio)
                }
            },
            onResult: { request, _ in
                request.onComplete()
            },
            onError: { request, error in
                request.onError(error)
            }
        )
    }()
    
    // MARK: - Initialization
    /// Initializes the generator but does not load the TTS engine until `initialize()` is called.
    /// Throws if the application support directory cannot be created.
    public init(logger: KokoroLogger = KokoroLogger.create(for: AudioGenerator.self)) throws {
        self.logger = logger
    }

    // MARK: - Public API

    /// Loads or reloads the TTS engine by unpacking assets and initializing OfflineTts.
    /// Call this before using `generateAudio`. Re-initializes if `forceReinitialize`.
    public func initialize(forceReinitialize: Bool = false) async throws {
        if tts != nil && !forceReinitialize {
            logger.d("TTS engine already initialized.")
            return
        }

        do {
            // Resource loading
            let modelPath = resourceProvider.resourceURL(for: "kokoro.onnx")
            let voicesPath = resourceProvider.resourceURL(for: "voices.bin")
            let tokensPath = resourceProvider.resourceURL(for: "tokens.txt")
            let lexiconPath = resourceProvider.resourceURL(for: VoiceConfig.getLexiconFileForId(currentVoice.rawValue))
            let dataDir = resourceProvider.resourceURL(for: "espeak-ng-data")
            let dictDir = resourceProvider.resourceURL(for: "dict")
            
            guard !modelPath.isEmpty && !voicesPath.isEmpty && !tokensPath.isEmpty else {
                logger.e("❌ TTSGenerationManager: Missing required resource files")
                throw NSError(domain: "TTSGenerationManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing required resource files"])
            }
            
            let kokoroConfig = sherpaOnnxOfflineTtsKokoroModelConfig(
                model: modelPath,
                voices: voicesPath,
                tokens: tokensPath,
                dataDir: dataDir,
                dictDir: dictDir,
                lexicon: lexiconPath
            )
            
            // Use fewer threads if constrained, but ensure at least 1
            let threads = max(2, ProcessInfo.processInfo.processorCount / 2)
            let modelConfig = sherpaOnnxOfflineTtsModelConfig(kokoro: kokoroConfig, numThreads: threads)
            var config = sherpaOnnxOfflineTtsConfig(model: modelConfig)
            
            let wrapper = SherpaOnnxOfflineTtsWrapper(config: &config)
            tts = wrapper
            logger.d("✅ TTSGenerationManager: Engine initialized successfully")
        } catch {
            logger.d("❌ TTSGenerationManager: Failed to initialize engine: \(error.localizedDescription)")
            tts = nil
        }
    }

    /// Change voice; re-inits engine if lexicon differs.
    public func setVoice(_ voice: VoiceConfig) async {
        let oldLex = VoiceConfig.getLexiconFileForId(currentVoice.rawValue)
        guard voice != currentVoice else { return }
        logger.d("Switching voice \(currentVoice.rawValue) → \(voice.rawValue)")
        currentVoice = voice
        let newLex = VoiceConfig.getLexiconFileForId(voice.rawValue)
        if newLex != oldLex {
            logger.d("Lexicon changed → reinitializing engine")
            do { try await initialize(forceReinitialize: true) }
            catch { logger.e("Re-init after voice change failed", error: error) }
        }
    }

    public func generateAudioForSentence(
            text: String,
            onAudioGenerated: @escaping (SherpaOnnxGeneratedAudioWrapper) -> Void,
            onComplete: @escaping () -> Void,
            onError: @escaping (Error) -> Void
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            logger.w("Skipping blank text submission.")
            onComplete()
            return
        }
        
        // Create chunks using TextChunker
        let chunker = TextChunker(minChunkLength: 15, maxChunkLength: 80)
        let chunks = chunker.chunk(trimmed)
        
        // Create sentence request
        let request = SentenceRequest(
            chunks: chunks,
            onComplete: onComplete,
            onError: onError,
            onAudioGenerated: onAudioGenerated
        )
        
        // Auto-init on demand
        if tts == nil {
            logger.w("Engine not initialized – initializing now.")
            Task {
                do {
                    try await initialize()
                    await jobProcessor.submit(request)
                } catch {
                    logger.e("Auto-init failed", error: error)
                    await MainActor.run { onError(error) }
                }
            }
            return
        }
        
        // Submit the sentence for processing
        Task { await jobProcessor.submit(request) }
    }

    /// Remove all pending jobs; does not cancel in-flight.
    public func clearPendingJobs() {
        Task { await jobProcessor.clearQueue() }
    }

    /// Count of queued but not yet processed jobs.
    public func getPendingJobCount() async -> Int {
        return await jobProcessor.getQueueSize()
    }

    /// Release engine resources.
    public func shutdown() {
        Task { await jobProcessor.clearQueue() }
        tts = nil
    }

    /// Gets the name of the currently selected voice.
    public func getVoice() -> String {
        return currentVoice.voiceName
    }

    // MARK: - Helpers
    private func calculateOptimalThreads() -> Int {
        let cores = ProcessInfo.processInfo.processorCount
        return max(1, min(cores / 2, 8))
    }
}
