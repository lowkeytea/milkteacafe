import Foundation
import Speech
import AVFoundation
import os

/**
 * Handles speech recognition functionality for the AudioCoordinator.
 * This provides the actual speech recognition implementation that
 * the coordinator will use.
 */
class SpeechRecognizer {
    // MARK: - Properties
    
    /// Callback for when transcription is updated
    typealias TranscriptionCallback = (String, Bool) -> Void
    
    /// The audio engine to use for recognition
    private let audioEngine: AVAudioEngine
    
    /// Logger for debug messages
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "SpeechRecognizer")
    
    /// Current recognition request
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    
    /// Current recognition task
    private var recognitionTask: SFSpeechRecognitionTask?
    
    /// Speech recognizer
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    
    /// Callback to inform about transcription updates
    private var transcriptionCallback: TranscriptionCallback?
    
    /// Whether recognition is active
    private(set) var isRecognizing = false
    
    private(set) var isUserCancelled = false
    
    // MARK: - Initialization
    
    /// Initialize with an audio engine
    /// - Parameter audioEngine: The audio engine to use
    init(audioEngine: AVAudioEngine) {
        self.audioEngine = audioEngine
        logger.debug("SpeechRecognizer: Initialized with audio engine")
    }
    
    deinit {
        stopRecognition()
        logger.debug("SpeechRecognizer: Deinitialized")
    }
    
    // MARK: - Public Methods
    
    /// Set the callback for transcription updates
    /// - Parameter callback: The callback to call when transcription is updated
    func setTranscriptionCallback(_ callback: @escaping TranscriptionCallback) {
        self.transcriptionCallback = callback
        logger.debug("SpeechRecognizer: Set transcription callback")
    }
    
    /// Start speech recognition
    /// - Returns: True if recognition started successfully
    func startRecognition() -> Bool {
        logger.debug("SpeechRecognizer: Starting recognition")
        
        // Ensure recognition isn't already in progress
        if isRecognizing {
            logger.debug("SpeechRecognizer: Recognition already in progress")
            return true
        }
        
        // Ensure the recognizer is available
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            logger.error("SpeechRecognizer: Speech recognizer not available")
            return false
        }
        
        // Add small delay for Bluetooth devices to stabilize
        let currentRoute = AVAudioSession.sharedInstance().currentRoute
        let usingBluetooth = currentRoute.outputs.contains {
            $0.portType == .bluetoothHFP || $0.portType == .bluetoothA2DP || $0.portType == .bluetoothLE
        }
        
        if usingBluetooth {
            // Log the current audio route for debugging
            if let input = currentRoute.inputs.first, let output = currentRoute.outputs.first {
                logger.debug("SpeechRecognizer: Using Bluetooth - Input: \(input.portName) (\(input.portType.rawValue)), Output: \(output.portName) (\(output.portType.rawValue))")
            }
        }
        
        // Cancel any existing recognition task
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // End any existing recognition request
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            logger.error("SpeechRecognizer: Could not create recognition request")
            return false
        }
        
        // Configure request
        recognitionRequest.shouldReportPartialResults = true
        if #available(iOS 13, *) {
            recognitionRequest.requiresOnDeviceRecognition = speechRecognizer.supportsOnDeviceRecognition
        }
        
        // Access input node from the audio engine
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        #if DEBUG
        logger.debug("SpeechRecognizer: Using input format: \(recordingFormat), channels: \(recordingFormat.channelCount)")
        #endif
        // Remove any existing tap
        if inputNode.engine != nil {
            inputNode.removeTap(onBus: 0)
        }
        let currentFormat = inputNode.outputFormat(forBus: 0)
        
        // Install tap on the input node
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: currentFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        
        // Prepare and start the audio engine
        do {
            if !audioEngine.isRunning {
                audioEngine.prepare()
                try audioEngine.start()
                logger.debug("SpeechRecognizer: Started audio engine")
            }
            
            isRecognizing = true
        } catch {
            logger.error("SpeechRecognizer: Could not start audio engine: \(error.localizedDescription)")
            return false
        }
        
        // Start recognition task with better error handling
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            var isFinal = false
            var shouldRestart = false
            
            if let result = result {
                let transcript = result.bestTranscription.formattedString
                isFinal = result.isFinal
                
                // Call the transcription callback˝
                DispatchQueue.main.async {
                    self.transcriptionCallback?(transcript, isFinal)
                    // Log transcription update
                    #if DEBUG
                    self.logger.debug("SpeechRecognizer: Transcribed: \"\(transcript)\"")
                    #endif
                }
            }
            
            if let error = error {
                // Check for Bluetooth-specific errors
                let nsError = error as NSError
                let isBluetoothError = nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 1101
                
                if isBluetoothError {
                    self.logger.warning("SpeechRecognizer: Bluetooth audio error detected: \(error.localizedDescription)")
                    shouldRestart = true
                } else {
                    self.logger.error("SpeechRecognizer: Recognition error: \(error.localizedDescription)")
                }
            }
            
            if error != nil || isFinal {
                // Stop the audio engine and recognition
                if self.audioEngine.isRunning {
                    self.audioEngine.stop()
                }
                
                if self.audioEngine.inputNode.engine != nil {
                    self.audioEngine.inputNode.removeTap(onBus: 0)
                }
                
                self.recognitionRequest = nil
                self.recognitionTask = nil
                
                // Update state
                self.isRecognizing = false
                
                // Handle final result
                if isFinal {
                    self.logger.debug("SpeechRecognizer: Final result received")
                }
                
                // For user cancellation, don't automatically restart
                let nsError = error as NSError?
                let userCancelled = (nsError?.domain == NSCocoaErrorDomain && nsError?.code == NSUserCancelledError) ||
                                   (nsError?.domain == "kAFAssistantErrorDomain" && nsError?.code == 216)
                
                if !self.isUserCancelled && !isFinal {
                    // For non-cancellation errors, try to restart after a short delay
                    // Use a longer delay for Bluetooth errors to allow more time for the audio session to stabilize
                    let delay: TimeInterval = shouldRestart ? 1.0 : 0.5
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                        guard let self = self else { return }
                        if !self.isRecognizing {
                            self.logger.debug("SpeechRecognizer: Attempting restart after error")
                            // Reconfigure audio session first
                            NotificationCenter.default.post(name: .needsAudioSessionReconfiguration, object: nil)
                            
                            // Give the audio session time to reconfigure
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                _ = self.startRecognition()
                            }
                        }
                    }
                    self.isUserCancelled = false
                }
            }
        }
        
        logger.debug("SpeechRecognizer: Started recognition task")
        return true
    }
    
    /// Stop speech recognition
    func stopRecognition() {
        logger.debug("SpeechRecognizer: Stopping recognition")
        
        isUserCancelled = true
        // Cancel recognition task
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // End audio request
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        // Stop audio engine
        if audioEngine.isRunning {
            audioEngine.stop()
            logger.debug("SpeechRecognizer: Stopped audio engine")
        }
        
        // Remove tap from input node
        if audioEngine.inputNode.engine != nil {
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        
        // Update state
        isRecognizing = false
        
        logger.debug("SpeechRecognizer: Recognition stopped")
    }
    
    /// Check if we have permission to use speech recognition
    /// - Parameter completion: Callback with the result (true if granted)
    static func checkPermissions(completion: @escaping (Bool) -> Void) {
        var speechGranted = false
        var audioGranted = false
        let group = DispatchGroup()
        
        group.enter()
        SFSpeechRecognizer.requestAuthorization { status in
            speechGranted = status == .authorized
            group.leave()
        }
        
        group.enter()
        AVAudioApplication.requestRecordPermission { granted in
            audioGranted = granted
            group.leave()
        }
        
        group.notify(queue: .main) {
            let bothGranted = speechGranted && audioGranted
            completion(bothGranted)
        }
    }
}
