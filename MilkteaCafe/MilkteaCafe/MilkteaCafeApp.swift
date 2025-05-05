import SwiftUI

@main
struct MilkteaCafeApp: App {
    // Register app delegate for initialization
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    // Initialize classifiers again to ensure they're loaded
                    // This provides a fallback if AppDelegate doesn't run fully
                    ClassifierSetup.shared.setupClassifiers()
                }
        }
    }
}
