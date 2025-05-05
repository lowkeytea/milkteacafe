import Foundation
import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // Initialize classifiers at app launch
        ClassifierSetup.shared.setupClassifiers()
        
        LoggerService.shared.info("App launched with classifier initialization")
        return true
    }
}
