import Foundation
import AppKit

/// Simple logger that records diagnostic information to a log file.
///
/// A single log file is maintained in the user's Library/Logs directory.  On each
/// application launch the existing log is removed so that logs do not accumulate
/// indefinitely.  Messages are appended to the file synchronously as they occur.
final class Logger {
    /// Shared singleton instance.
    static let shared = Logger()
    private let logFileURL: URL

    private init() {
        let fm = FileManager.default
        // Locate the Library directory within the user's domain and create a Logs folder.
        let appSupport = fm.urls(for: .libraryDirectory, in: .userDomainMask).first!
        let logsDir = appSupport.appendingPathComponent("Logs", isDirectory: true)
        try? fm.createDirectory(at: logsDir, withIntermediateDirectories: true)
        // Log file name is fixed; it will be recreated on each launch.
        logFileURL = logsDir.appendingPathComponent("LunarSensorApp.log")
        // Remove any existing log at startup.
        try? fm.removeItem(at: logFileURL)
        fm.createFile(atPath: logFileURL.path, contents: nil)
    }

    /// Append a line to the log file.
    /// - Parameter message: The message to append.  A newline is automatically added.
    func log(_ message: String) {
        guard let data = (message + "\n").data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: logFileURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        }
    }

    /// Copies the current log file to the user's Downloads directory.  If a log
    /// already exists at the destination it is overwritten.
    func exportLogs() {
        let fm = FileManager.default
        guard let downloads = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first else { return }
        let destURL = downloads.appendingPathComponent("LunarSensorApp.log")
        // Remove existing exported log if present
        try? fm.removeItem(at: destURL)
        do {
            try fm.copyItem(at: logFileURL, to: destURL)
        } catch {
            // If copying fails just ignore; logging should not crash the app.
        }
    }

    /// Returns an NSImage representing the application icon.  Tries to load
    /// a WebP asset first and falls back to the PNG if the WebP cannot be
    /// decoded.  Returns nil if no image can be loaded.
    static func loadAppIcon() -> NSImage? {
        // Attempt to load a converted PNG from the original WebP.
        // Many versions of macOS do not support WebP decoding natively in NSImage,
        // so we include a pre‑converted PNG asset.  If that cannot be loaded
        // (for example, if it is accidentally removed from the bundle), we
        // continue to fall back to the previously shipped PNG.
        if let convertedURL = Bundle.main.url(forResource: "tvsamsungok_converted", withExtension: "png"),
           let convertedImage = NSImage(contentsOf: convertedURL) {
            return convertedImage
        }
        // Attempt to load the WebP icon (for future compatibility).  This branch is
        // retained so that if NSImage gains WebP support it will use the higher
        // fidelity asset.
        if let webpURL = Bundle.main.url(forResource: "tvsamsungok", withExtension: "webp"),
           let data = try? Data(contentsOf: webpURL),
           let image = NSImage(data: data) {
            return image
        }
        // Fall back to the original PNG icon as a last resort.
        if let pngURL = Bundle.main.url(forResource: "655F78EF-F162-4EDE-8248-09CE5C8A80EA", withExtension: "png"),
           let image = NSImage(contentsOf: pngURL) {
            return image
        }
        return nil
    }

    /// Logs static system information useful for debugging.  This method can
    /// safely be called multiple times; it will log current values at each call.
    func logSystemInfo() {
        // Gather information from the environment.  Values that may vary at
        // runtime are queried dynamically.  Sensitive information such as
        // tokens or secrets is deliberately excluded.
        let tvName = OAuthConfigManager.shared.tvName.isEmpty ? Constants.tvName : OAuthConfigManager.shared.tvName
        let deviceId = OAuthConfigManager.shared.deviceId.isEmpty ? Constants.deviceId : OAuthConfigManager.shared.deviceId
        let redirectURI = OAuthConfigManager.shared.redirectURI.isEmpty ? Constants.redirectURI : OAuthConfigManager.shared.redirectURI
        let serverPort = 10001
        let bundle = Bundle.main
        let appVersion = (bundle.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "Unknown"
        let osVersionInfo = ProcessInfo.processInfo.operatingSystemVersion
        let osVersion = "\(osVersionInfo.majorVersion).\(osVersionInfo.minorVersion).\(osVersionInfo.patchVersion)"
        let machineName = Host.current().localizedName ?? "Unknown"

        log("System info: TV Name=\(tvName), Device ID=\(deviceId), Server port=\(serverPort), Redirect URI=\(redirectURI)")
        log("System info: App version=\(appVersion), macOS version=\(osVersion), Machine=\(machineName)")
    }
}