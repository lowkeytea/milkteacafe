/// Provides access to necessary resources

import Foundation
final class ResourceProvider {
    func resourceURL(for resourceName: String) -> String {
        guard let resourceURL = Bundle.main.url(forResource: resourceName, withExtension: nil) else {
            print("❌ Resource not found: \(resourceName)")
            return ""
        }
        return resourceURL.path
    }
}
