import Foundation

/// Describes an LLM model available for download and use
struct ModelDescriptor: Identifiable, Equatable {
    let id: String              // Unique identifier for the model
    let displayName: String     // User-friendly name
    let url: URL                // Remote download URL
    let fileName: String        // Local filename for storage
    let defaultDownloadSize: Int64   // Approximate download size in bytes
    let memoryRequirement: String    // Rough memory requirement (e.g. "8GB")
} 