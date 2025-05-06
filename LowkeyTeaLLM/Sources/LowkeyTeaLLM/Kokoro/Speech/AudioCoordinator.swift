import Foundation
import AVFoundation
import Combine
import Speech

/**
 * Central coordinator for managing the relationship between speech input and TTS playback.
 * Handles state transitions and ensures proper coordination between listening and speaking.
 */
class AudioCoordinator: ObservableObject {
    // MARK: - Singleton
    
    /// Shared instance for app-wide access
    static let shared = AudioCoordinator()
    let logger = KokoroLogger.create(for: AudioCoordinator.self)
    
    // MARK: - State Management
    
    /// Represents the possible states of the audio system
    enum AudioState {
        case idle            // No audio activity
        case listening       // Actively listening for speech input
        case playingTTS      // Playing TTS response
    }
    
    /// Current state of the audio system
    @Published private(set) var currentState: AudioState = .idle
    
    /// Whether headphones are currently connected
    @Published private(set) var isUsingHeadphones = false
    
    /// Whether listening mode is enabled by the user
    @Published private(set) var isListeningEnabled = false
    
    
    // MARK: - Component References
    
    /// The audio session manager for accessing the shared audio engine
    private let audioSessionManager = AudioSessionManager.shared
    
    /// The microphone input node from the shared audio engine
    private var microphoneInputNode: AVAudioInputNode {
        return audioSessionManager.audioEngine.inputNode
    }
    
    /// The player node for TTS playback
    private let ttsPlayerNode = AVAudioPlayerNode()
    
    /// Speech recognizer for converting audio to text
    private lazy var speechRecognizer = SpeechRecognizer(audioEngine: audioSessionManager.audioEngine)
    
    // MARK: - Subscriptions
    
    /// Cancellables for managing Combine subscriptions
    private var cancellables = Set<AnyCancellable>()
    /// Subscriptions for Combine publishers
    
    // MARK: - Configuration
    
    /// Time of inactivity in seconds before auto-submission
    private let inactivityThresholdForSubmit: TimeInterval = 1.2
    
    /// Format for audio recording
    private var recordingFormat: AVAudioFormat?
    
    // MARK: - State Tracking
    
    /// The last time transcribed text was updated
    private var lastTranscribedUpdateTime: Date?
    
    /// The current transcribed text
    @Published private(set) var transcribedText = ""
    
    /// Whether speech recognition has detected the user is speaking
    @Published private(set) var isUserSpeaking = false
    
    /// Timer for checking inactivity
    private var inactivityTimer: Timer?
    
    /// Was listening before interruption
    private var wasListeningBeforeInterruption = false
    
    // MARK: - Initialization
    
    private init() {
        // Set up audio nodes with the session manager
        setupAudioNodes()
        
        // Start monitoring for audio route changes (headphones)
        setupRouteMonitoring()
        
        // Set up speech recognition callback
        setupSpeechRecognition()
        // Listen for KokoroEngine playback events
        setupPlaybackStateListener()
        logger.d("AudioCoordinator: Initialized")
    }
    
    // MARK: - Setup Methods
    
    /// Set up audio nodes with the session manager
    private func setupAudioNodes() {
        // Attach TTS player node if needed
        audioSessionManager.attachNodeIfNeeded(ttsPlayerNode)
        
        // Get recording format from input node
        recordingFormat = microphoneInputNode.outputFormat(forBus: 0)
        
        logger.d("AudioCoordinator: Audio nodes set up")
    }
    
    /// Set up monitoring for audio route changes (headphones connected/disconnected)
    private func setupRouteMonitoring() {
        AudioRouteMonitor.shared.$isRoutedToHeadphones
            .sink { [weak self] isUsingHeadphones in
                self?.handleHeadphoneStateChange(isUsingHeadphones)
            }
            .store(in: &cancellables)
        
        // Initialize with current state
        isUsingHeadphones = AudioRouteMonitor.shared.isRoutedToHeadphones
        logger.d("AudioCoordinator: Initial headphone state - \(isUsingHeadphones)")
    }
    
    /// Listen to KokoroEngine playback events via Combine publisher subscription
    private func setupPlaybackStateListener() {
        // Subscribe to playback state changes via Combine CurrentValueSubject
        KokoroEngine.playbackBus.publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.handleKokoroPlaybackState(state)
            }
            .store(in: &cancellables)
    }

    /// Map KokoroEngine.PlaybackState to local AudioState handling
    private func handleKokoroPlaybackState(_ state: PlaybackState) {
        switch state {
        case .playing, .starting:
            handleTTSStarted()
        case .idle, .paused, .stopping:
            handleTTSStopped()
        }
    }
    
    /// Set up speech recognition callback
    private func setupSpeechRecognition() {
        // Set the transcription callback to update our state
        speechRecognizer.setTranscriptionCallback { [weak self] transcription, isFinal in
            guard let self = self else { return }
            
            // Update transcribed text
            self.transcribedText = transcription
            
            // Update user speaking state
            self.isUserSpeaking = !transcription.isEmpty
            
            // Update last transcription time
            self.lastTranscribedUpdateTime = Date()
            
            // If final result, submit
            if isFinal {
                self.submitTranscribedText()
            }
        }
    }
    
    // MARK: - Public Methods
    
    /// Toggle listening mode on/off
    func toggleListening() {
        isListeningEnabled.toggle()
        logger.d("AudioCoordinator: Toggled listening to \(isListeningEnabled)")
        
        if isListeningEnabled {
            // Check permissions before starting
            SpeechRecognizer.checkPermissions { [weak self] granted in
                guard let self = self else { return }
                
                if granted {
                    self.startListening()
                } else {
                    DispatchQueue.main.async {
                        self.isListeningEnabled = false
                    }
                    logger.w("AudioCoordinator: Speech recognition permission denied")
                }
            }
        } else {
            stopListening()
        }
    }
    
    /// Start listening for user speech
    func startListening() {
        guard isListeningEnabled else { return }
        
        // If TTS is playing and we're in speaker mode, we can't listen
        if currentState == .playingTTS && !isUsingHeadphones {
            logger.d("AudioCoordinator: Can't start listening - TTS playing in speaker mode")
            return
        }
        
        // Configure audio session
        Task {
            await audioSessionManager.configureGlobalSession()
            
            // Start listening
            startMicrophoneCapture()
        }
    }
    
    func stopListeningIfUsingSpeakers() {
        if (!isUsingHeadphones) {
            logger.i("Stopping listening as we're using speakers")
            stopListening()
        }
    }
    
    /// Stop listening for user speech
    func stopListening() {
        if currentState == .listening {
            stopMicrophoneCapture()
            
            // Update state
            if currentState != .playingTTS {
                currentState = .idle
            }
        }
        
        logger.d("AudioCoordinator: Stopped listening")
    }
    
    /// Submit the transcribed text
    func submitTranscribedText() {
        guard !transcribedText.isEmpty else { return }
        
        // Capture the text to submit
        let textToSubmit = transcribedText
        logger.d("AudioCoordinator: Submitting text: \(textToSubmit)")
        
        // Stop listening
        stopListeningIfUsingSpeakers()
        
        // Post notification with the text
        NotificationCenter.default.post(
            name: .speechTextSubmissionNotification,
            object: nil,
            userInfo: ["text": textToSubmit]
        )
        
        // Clear transcribed text
        transcribedText = ""
        isUserSpeaking = false
        
        // Restart listening after a delay if still enabled and using headphones
        if isListeningEnabled && isUsingHeadphones {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.startListening()
            }
        }
    }
    
    // MARK: - Private Methods
    
    /// Start capturing audio from the microphone
    private func startMicrophoneCapture() {
        Task {
            audioSessionManager.prepareForMicrophone()
        }
        
        // Add a small delay before starting speech recognition when using Bluetooth
        // This allows the audio session to fully apply the new configuration
        let startupDelay: TimeInterval = isUsingHeadphones ? 0.3 : 0.1
        
        DispatchQueue.main.asyncAfter(deadline: .now() + startupDelay) { [weak self] in
            guard let self = self else { return }
            
            // Start speech recognition
            if self.speechRecognizer.startRecognition() {
                // Start inactivity timer for auto-submission
                self.startInactivityTimer()
                // Update state
                self.currentState = .listening
                logger.d("AudioCoordinator: Started listening")
            } else {
                logger.e("AudioCoordinator: Failed to start speech recognition")
            }
        }
    }
    
    /// Stop capturing audio from the microphone
    private func stopMicrophoneCapture() {
        // Stop inactivity timer
        inactivityTimer?.invalidate()
        inactivityTimer = nil
        // Stop speech recognition
        speechRecognizer.stopRecognition()
        
        logger.d("AudioCoordinator: Stopped microphone capture")
    }
    
    /// Start timer to check for speech inactivity
    private func startInactivityTimer() {
        // First invalidate any existing timer
        inactivityTimer?.invalidate()
        inactivityTimer = nil
        
        // Create a new timer on the main thread to ensure it runs properly
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Create timer on main thread
            self.inactivityTimer = Timer.scheduledTimer(
                timeInterval: 0.5,
                target: self,
                selector: #selector(self.checkForInactivityFromTimer),
                userInfo: nil,
                repeats: true
            )
            
            // Add to common run loop mode to ensure it fires during scrolling, etc.
            if let timer = self.inactivityTimer {
                RunLoop.main.add(timer, forMode: .common)
            }
            
            logger.d("AudioCoordinator: Started inactivity timer on main thread")
        }
    }
    
    @objc private func checkForInactivityFromTimer() {
        checkForInactivity()
    }
    
    /// Check if there has been a period of silence that should trigger submission
    private func checkForInactivity() {
        // Only check if we have text and a last update time
        guard !transcribedText.isEmpty, let lastUpdate = lastTranscribedUpdateTime else { return }
        
        // Calculate time since last update
        let timeSinceLastUpdate = Date().timeIntervalSince(lastUpdate)
        
        #if DEBUG
        logger.d("AudioCoordinator: Checking inactivity - time since last update: \(timeSinceLastUpdate)s")
        #endif
        
        // Auto-submit if threshold reached
        if timeSinceLastUpdate >= inactivityThresholdForSubmit {
            #if DEBUG
            logger.i("AudioCoordinator: No new transcription for \(timeSinceLastUpdate)s — auto-submitting")
            #endif
            
            DispatchQueue.main.async { [weak self] in
                self?.isUserSpeaking = false
                self?.submitTranscribedText()
            }
        }
    }
    
    /// Handle headphone connection state change
    private func handleHeadphoneStateChange(_ isUsingHeadphones: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let stateChanged = self.isUsingHeadphones != isUsingHeadphones
            self.isUsingHeadphones = isUsingHeadphones  // Now safe on main thread
            
            logger.d("AudioCoordinator: Headphone status changed to \(isUsingHeadphones)")
            
            if stateChanged {
                Task {
                    NotificationCenter.default.post(name: .needsAudioSessionReconfiguration, object: nil)
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }

            if self.isListeningEnabled {
                if isUsingHeadphones {
                    if self.currentState == .playingTTS {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            self.startListening()
                        }
                    }
                } else {
                    if self.currentState == .playingTTS {
                        self.stopListening()
                    }
                }
            }
        }
    }
    
    /// Handle TTS playback started
    private func handleTTSStarted() {
        logger.d("AudioCoordinator: TTS playback started")
        
        // Update state
        currentState = .playingTTS
        
        // If not using headphones, stop listening
        stopListeningIfUsingSpeakers()
    }
    
    /// Handle TTS playback stopped
    private func handleTTSStopped() {
        logger.d("AudioCoordinator: TTS playback stopped")
        
        // Update state
        currentState = .idle
        KokoroEngine.sharedInstance.shutdownGenerator()
        
        // Resume listening if enabled
        if isListeningEnabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.startListening()
            }
        }
    }
    
    // MARK: - Interruption Handling
    
    /// Handle audio session interruption
    private func handleInterruption(began: Bool) {
        logger.d("AudioCoordinator: Handling audio interruption, began: \(began)")
        
        if began {
            // Store state before interruption
            wasListeningBeforeInterruption = currentState == .listening
            
            // Stop listening if active
            if currentState == .listening {
                stopMicrophoneCapture()
            }
        } else {
            // Let AudioSessionManager handle resuming the session
            // We'll receive audioSessionResume notification if needed
        }
    }
    
    /// Handle audio session resume after interruption
    private func handleSessionResume() {
        logger.d("AudioCoordinator: Handling audio session resume")
        
        // Resume listening if it was active before interruption
        if wasListeningBeforeInterruption && isListeningEnabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.startListening()
            }
        }
        
        // Reset flag
        wasListeningBeforeInterruption = false
    }
    deinit {
        // Combine subscriptions automatically cancelled
    }
}

// Extension to define notification names
extension Notification.Name {
    static let speechTextSubmissionNotification = Notification.Name("speechTextSubmissionNotification")
    static let audioSessionInterruption = Notification.Name("audioSessionInterruption")
    static let audioSessionResume = Notification.Name("audioSessionResume")
    static let needsAudioSessionReconfiguration = Notification.Name("needsAudioSessionReconfiguration")
}
