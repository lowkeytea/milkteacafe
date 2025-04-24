import AVFAudio
import Combine
import Foundation
import os

/// Monitors audio route changes and provides information about current audio routing
class AudioRouteMonitor {
    // MARK: - Shared Instance
    
    static let shared = AudioRouteMonitor()
    
    // MARK: - Properties
    
    /// True when audio output is routed to headphones, earbuds, or Bluetooth audio
    @Published private(set) var isRoutedToHeadphones = false
    
    /// The current audio output route description
    @Published private(set) var currentRouteDescription = ""
    
    /// Logger for debugging
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "AudioRouteMonitor")
    
    /// Last update time to prevent too frequent logging
    private var lastUpdateTime: Date = Date(timeIntervalSince1970: 0)
    
    /// Last route description to prevent duplicate logging
    private var lastRouteDescription = ""
    
    // MARK: - Initialization
    
    private init() {
        // Register for audio route change notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
        
        // Perform initial check of audio routes
        updateCurrentRouteInfo()
    }
    
    // MARK: - Route Detection
    
    /// Updates the current route information
    func updateCurrentRouteInfo() {
        let session = AVAudioSession.sharedInstance()
        
        // Get current output routes
        let outputs = session.currentRoute.outputs
        
        // Check if we have any outputs
        guard !outputs.isEmpty else {
            isRoutedToHeadphones = false
            currentRouteDescription = "No output"
            return
        }
        
        // Determine if any output is headphones, earbuds, or Bluetooth
        let headphoneTypes: [AVAudioSession.Port] = [
            .headphones,         // Wired headphones
            .bluetoothA2DP,      // Bluetooth stereo audio
            .bluetoothHFP,       // Bluetooth hands-free profile
            .bluetoothLE,        // Bluetooth Low Energy
            .airPlay,            // AirPlay devices
            .carAudio            // Car audio systems
        ]
        
        // Check if any output is a headphone type
        let usingHeadphones = outputs.contains { headphoneTypes.contains($0.portType) }
        
        // Create a description of current outputs
        let description = outputs.map { "\($0.portName) (\($0.portType.rawValue))" }.joined(separator: ", ")
        
        // Only log if route has actually changed and not too frequently
        let now = Date()
        if description != lastRouteDescription && now.timeIntervalSince(lastUpdateTime) > 1.0 {
            // If routing changed, log it
            if usingHeadphones != isRoutedToHeadphones {
                logger.debug("Audio route changed: \(usingHeadphones ? "Using headphones" : "Using speaker")")
            }
            
            lastRouteDescription = description
            lastUpdateTime = now
            logger.debug("Current audio route: \(description)")
        }
        
        // Update published properties
        isRoutedToHeadphones = usingHeadphones
        currentRouteDescription = description
    }
    
    // MARK: - Notification Handling
    
    @objc private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        // Only log important route changes
        switch reason {
        case .newDeviceAvailable, .oldDeviceUnavailable, .override:
            // Log the reason for the route change
            logger.debug("Audio route changed: \(self.routeChangeReasonDescription(for: reason))")
        default:
            // Don't log routine changes
            break
        }
        
        // Update our route information
        updateCurrentRouteInfo()
    }
    
    // Provides a human-readable description of route change reasons
    private func routeChangeReasonDescription(for reason: AVAudioSession.RouteChangeReason) -> String {
        switch reason {
        case .unknown:
            return "Unknown"
        case .newDeviceAvailable:
            return "New device available"
        case .oldDeviceUnavailable:
            return "Old device unavailable"
        case .categoryChange:
            return "Category change"
        case .override:
            return "Override"
        case .wakeFromSleep:
            return "Wake from sleep"
        case .noSuitableRouteForCategory:
            return "No suitable route for category"
        case .routeConfigurationChange:
            return "Route configuration change"
        @unknown default:
            return "Unknown (\(reason.rawValue))"
        }
    }
}
