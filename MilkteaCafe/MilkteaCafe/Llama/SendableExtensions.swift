import Foundation
import llama

// Mark OpaquePointer as Sendable to allow it to cross actor boundaries
extension OpaquePointer: @unchecked Sendable {}
