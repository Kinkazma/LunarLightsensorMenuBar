import SwiftUI
import Foundation

@main
struct LunarSensorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Provide an invisible window group to satisfy SwiftUI’s requirement
        // for at least one scene.  EmptyView prevents any actual window
        // content from appearing.  Combined with activationPolicy(.accessory)
        // the app remains hidden from the Dock.
        WindowGroup {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)       // sécurité : agent
        // Touch the logger early so that the log file is cleared on launch.
        Logger.shared.log("Application started")
        // Log static system information for debugging purposes.
        Logger.shared.logSystemInfo()
        OAuthManager.shared.initializeTokens()
        OAuthManager.shared.startAutomaticRefresh()
        statusBarController = StatusBarController() // icône barre-menus
    }
}
