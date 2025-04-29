import AVFAudio
import os

/**
 * Centralized manager for the app's audio session and audio engine.
 *
 * This class provides a single source of truth for audio session configuration,
 * audio engine management, and audio routing/interruption handling. All components
 * that need to use audio should access it through this manager.
 */
class AudioSessionManager {
    /// Shared singleton instance
    static let shared = AudioSessionManager()
    
    
    
    /// The centralized audio engine instance used by all audio components
    let audioEngine = AVAudioEngine()
    
    /// Lazy-initialized speech recognition manager
    private var speechRecognitionObserver: Any?
    
    /// Logger for audio session events
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "AudioSessionManager")
    
    /// Whether the audio session has been successfully configured
    private var isSessionConfigured = false
    
    // Track attached nodes
    private var attachedNodes = Set<AVAudioNode>()
    
    // Track last successful audio setup
    private var lastSuccessfulSetup: Date?
    
    // Flag to prevent reacting to our own configuration changes
    private var isConfiguringSession = false
    
    private var lastReconfigurationTime = Date(timeIntervalSince1970: 0)
    private let reconfigurationCooldown: TimeInterval = 2.0
    
    // Setup at initialization
    private init() {
        // Register for notifications immediately
        registerForRouteChangeNotifications()
        setupAudioSessionInterruptionObserver()
        setupInterruptionNotification()
        setupReconfigurationNotification()
        
        // Configure session asynchronously
        Task { await configureGlobalSession() }
    }
    
    private func setupReconfigurationNotification() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionReconfiguration),
            name: .needsAudioSessionReconfiguration,
            object: nil
        )
    }
    
    @objc private func handleAudioSessionReconfiguration(_ notification: Notification) {
        Task {
            // Check if we're within the cooldown period
            let now = Date()
            let timeSinceLastReconfiguration = now.timeIntervalSince(lastReconfigurationTime)
            
            if timeSinceLastReconfiguration < reconfigurationCooldown {
                logger.debug("🔄 AudioSessionManager: Reconfiguration request ignored (cooldown: \(String(format: "%.1f", timeSinceLastReconfiguration))s < \(self.reconfigurationCooldown)s)")
                return
            }
            
            logger.debug("🔄 AudioSessionManager: Processing reconfiguration request")
            
            // Update timestamp before reconfiguring
            lastReconfigurationTime = now
            
            // Force reconfiguration
            isConfiguringSession = false // Reset this flag to avoid skipping in handleRouteChange
            isSessionConfigured = false
            await configureGlobalSession()
        }
    }
    
    @objc private func handleAudioRouteChange(_ notification: Notification) {
        // Skip if we're the ones causing the route change
        if isConfiguringSession {
            return
        }
        
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        // Log the route change
        logger.debug("🔊 Audio route changed: \(self.reasonDescription(for: reason))")
        
        // Check if we're within the cooldown period for reconfigurations
        let now = Date()
        let timeSinceLastReconfiguration = now.timeIntervalSince(lastReconfigurationTime)
        
        if timeSinceLastReconfiguration < reconfigurationCooldown {
            // Just update route information without reconfiguring
            AudioRouteMonitor.shared.updateCurrentRouteInfo()
            logger.debug("🔄 Audio route change handling limited (within cooldown period)")
            return
        }
        
        // For critical routing changes, reconfigure session
        switch reason {
        case .newDeviceAvailable, .oldDeviceUnavailable:
            // Update timestamp before reconfiguring
            lastReconfigurationTime = now
            
            // Reconfigure session immediately to adapt to the new route
            Task {
                await configureGlobalSession()
                
                // Update AudioRouteMonitor
                AudioRouteMonitor.shared.updateCurrentRouteInfo()
                
                // Notify speech manager about route change if needed
                if let previousRoute = userInfo[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription {
                    let hadHeadphones = previousRoute.outputs.contains { headphonePortTypes.contains($0.portType) }
                    let hasHeadphones = AudioRouteMonitor.shared.isRoutedToHeadphones
                    
                    if hadHeadphones != hasHeadphones {
                        logger.debug("🔊 Headphone connection state changed: \(hasHeadphones ? "connected" : "disconnected")")
                    }
                }
            }
        default:
            // For other changes, just update route monitor without reconfiguring
            AudioRouteMonitor.shared.updateCurrentRouteInfo()
        }
    }
    
    // Node management
    func attachNodeIfNeeded(_ node: AVAudioNode) {
        if !attachedNodes.contains(node) {
            audioEngine.attach(node)
            attachedNodes.insert(node)
            #if DEBUG
            logger.debug("🔊 Attached node: \(node)")
            #endif
        }
    }
    
    func detachNodeIfNeeded(_ node: AVAudioNode) {
        if attachedNodes.contains(node) {
            audioEngine.detach(node)
            attachedNodes.remove(node)
            #if DEBUG
            logger.debug("🔊 Detached node: \(node)")
            #endif
        }
    }
    
    /**
     * Configures the audio session for simultaneous playback and recording.
     * This is the central configuration method that sets up the audio session
     * with options suitable for all audio use cases in the app.
     */
    func configureGlobalSession() async {
        // Set flag to prevent reacting to our own configuration changes
        isConfiguringSession = true
        defer { isConfiguringSession = false }
        
        let audioSession = AVAudioSession.sharedInstance()
        
        // Check if session is already configured with the right category and options
        if isSessionConfigured &&
            audioSession.category == .playAndRecord &&
            Date().timeIntervalSince(lastSuccessfulSetup ?? Date(timeIntervalSince1970: 0)) < 30 {
            // Session is already configured recently, no need to reconfigure
            logger.debug("✅ Audio session already configured correctly, skipping")
            return
        }
        
        // Check if current route is Bluetooth before configuring
        let currentRoute = audioSession.currentRoute
        let usingBluetooth = currentRoute.outputs.contains {
            $0.portType == .bluetoothHFP || $0.portType == .bluetoothA2DP || $0.portType == .bluetoothLE
        }
        
        do {
            // Options that enable both Bluetooth and wired headset connectivity
            var options: AVAudioSession.CategoryOptions = [
                .allowBluetooth,        // Enable basic Bluetooth audio
                .allowBluetoothA2DP,    // Enable high-quality Bluetooth stereo
                .allowAirPlay,          // Enable AirPlay connectivity
                .defaultToSpeaker       // Default to speaker when no headphones
            ]
            
            // For Bluetooth connections, adjust the mode and options
            let mode: AVAudioSession.Mode = usingBluetooth ? .voiceChat : .default
            
            if usingBluetooth {
                logger.debug("🎧 Configuring audio session with Bluetooth-specific settings")
                // Bluetooth devices work better with these options
                options = [
                    .allowBluetooth,      // Enable basic Bluetooth audio (HFP protocol - better for voice)
                    .allowBluetoothA2DP,  // Enable high-quality Bluetooth stereo
                    .mixWithOthers        // Allow mixing with other apps' audio
                ]
            }
            
            // Configure for both playback and recording
            try audioSession.setCategory(.playAndRecord, mode: mode, options: options)
            
            // Only set sample rate and buffer duration if not Bluetooth
            // This can cause issues with some Bluetooth devices
            if !usingBluetooth {
                try audioSession.setPreferredSampleRate(24000)
                try audioSession.setPreferredIOBufferDuration(0.005) // 5ms buffer for lower latency
            }
            
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            
            // Record successful setup
            isSessionConfigured = true
            lastSuccessfulSetup = Date()
            
            // Log current routing once (not every time)
            if let inputs = audioSession.currentRoute.inputs.first,
               let outputs = audioSession.currentRoute.outputs.first {
                logger.debug("🔊 Current route - Input: \(inputs.portName) (\(inputs.portType.rawValue)), Output: \(outputs.portName) (\(outputs.portType.rawValue))")
            }
        } catch {
            logger.error("❌ Failed to configure audio session: \(error.localizedDescription)")
        }
    }
    
    /**
     * Prepares the audio session specifically for microphone usage.
     * This should be called before starting to record from the microphone.
     */
    func prepareForMicrophone() {
        // Ensure the session is in the right state for microphone
        Task {
            // Check if we need to reconfigure due to time elapsed
            if let lastSetup = lastSuccessfulSetup, Date().timeIntervalSince(lastSetup) > 60 {
                logger.debug("🔊 Audio session last configured over 60s ago, reconfiguring for microphone")
                await configureGlobalSession()
            } else if !isSessionConfigured {
                logger.debug("🔊 Audio session not previously configured, configuring for microphone")
                await configureGlobalSession()
            }
            
            // Ensure microphone is available
            if #available(iOS 17.0, *) {
                let session = AVAudioApplication.shared
                if session.recordPermission != .granted {
                    logger.warning("⚠️ Record permission not granted for microphone")
                }
            } else {
                // Fallback on earlier versions
            }
        
        }
    }
    
    /**
     * Prepares the audio session specifically for playback.
     * This should be called before starting audio playback.
     */
    func prepareForPlayback() {
        Task {
            // Ensure session is configured
            if !isSessionConfigured {
                logger.debug("🔊 Audio session not configured, configuring for playback")
                await configureGlobalSession()
            }
        }
    }
    
    /**
     * Ensures the audio engine is running, starting it if necessary.
     * Returns true if the engine is running successfully after the call.
     */
    @discardableResult
    func ensureEngineRunning() -> Bool {
        guard !audioEngine.isRunning else {
            return true
        }
        
        // Prepare engine with current graph
        audioEngine.prepare()
        
        do {
            // Start the audio engine
            try audioEngine.start()
            logger.debug("✅ Audio engine started successfully")
            return true
        } catch {
            logger.error("❌ Audio engine start failed: \(error.localizedDescription)")
            
            // Try to recover by resetting and reconfiguring
            Task {
                audioEngine.reset()
                await configureGlobalSession()
            }
            return false
        }
    }
    
    
    // Known headphone port types
    private let headphonePortTypes: [AVAudioSession.Port] = [
        .headphones,
        .bluetoothA2DP,
        .bluetoothHFP,
        .bluetoothLE,
        .airPlay,
        .carAudio
    ]
    
    /**
     * Returns a human-readable description for an audio route change reason.
     */
    private func reasonDescription(for reason: AVAudioSession.RouteChangeReason) -> String {
        switch reason {
        case .unknown: return "Unknown"
        case .newDeviceAvailable: return "New device available"
        case .oldDeviceUnavailable: return "Old device unavailable"
        case .categoryChange: return "Category change"
        case .override: return "Override"
        case .wakeFromSleep: return "Wake from sleep"
        case .noSuitableRouteForCategory: return "No suitable route for category"
        case .routeConfigurationChange: return "Route configuration change"
        @unknown default: return "Unknown (\(reason.rawValue))"
        }
    }
    
    /**
     * Registers for audio route change notifications from the system.
     */
    private func registerForRouteChangeNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
        
        // Force an initial route update
        AudioRouteMonitor.shared.updateCurrentRouteInfo()
    }
    
    // MARK: - Interruption Handling
    
    /**
     * Sets up the observer for audio session interruptions.
     */
    private func setupAudioSessionInterruptionObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }
    
    private func setupInterruptionNotification() {
        // Remove previous observer if any
        if let observer = speechRecognitionObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        
        // Add new audio session interruption observer
        speechRecognitionObserver = NotificationCenter.default.addObserver(
            forName: .audioSessionInterruption,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            
            // Handle audio session interruption
            if let began = notification.userInfo?["began"] as? Bool {
                if began {
                    // Interruption began
                    self.logger.debug("🔊 AudioSessionManager received notification that interruption began")
                    // You could perform additional actions here if needed
                } else {
                    // Interruption ended
                    self.logger.debug("🔊 AudioSessionManager received notification that interruption ended")
                    // You could perform additional actions here if needed
                }
            }
        }
    }
    
    /**
     * Handles audio session interruptions, coordinating with registered components.
     */
    @objc private func handleAudioSessionInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        Task {
            if type == .began {
                logger.debug("🔊 Audio session interrupted: Began")
                // Notify AudioCoordinator that interruption began
                NotificationCenter.default.post(
                    name: .audioSessionInterruption,
                    object: nil,
                    userInfo: ["began": true]
                )
                
            } else if type == .ended {
                logger.debug("🔊 Audio session interruption ended")
                // Notify AudioCoordinator that interruption ended
                NotificationCenter.default.post(
                    name: .audioSessionInterruption,
                    object: nil,
                    userInfo: ["began": false]
                )
                
                // If system indicates we should resume
                if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt,
                   AVAudioSession.InterruptionOptions(rawValue: optionsValue).contains(.shouldResume) {
                    
                    // Reconfigure session
                    await configureGlobalSession()
                    
                    // Small delay for system to stabilize
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    
                    // Tell AudioCoordinator to resume if it was active
                    NotificationCenter.default.post(
                        name: .audioSessionResume,
                        object: nil
                    )
                }
            }
        }
    }
}
extension Notification.Name {
    static let kokoroPlaybackStateChanged = Notification.Name("kokoroPlaybackStateChanged")
}
