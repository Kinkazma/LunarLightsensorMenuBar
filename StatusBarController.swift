import AppKit
import Foundation
import Swifter
import Darwin
import SwiftUI

class StatusBarController {
    private let smoothStepsKey = "LunarSensorAppSmoothSteps"
    private var numberOfSmoothSteps: Int {
        get {
            let saved = UserDefaults.standard.integer(forKey: smoothStepsKey)
            return (10...100).contains(saved) ? saved : 40 // 40 par défaut si non défini
        }
        set {
            UserDefaults.standard.set(newValue, forKey: smoothStepsKey)
        }
    }
    private let smoothModeKey = "LunarSensorAppSmoothMode"
    private var isSmoothModeEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: smoothModeKey) }
        set { UserDefaults.standard.set(newValue, forKey: smoothModeKey) }
    }
    private var statusItem: NSStatusItem
    private var timer: Timer?
    private var smartthingsTimer: Timer?
    private var smoothTimerSource: DispatchSourceTimer?
    private var targetLux: Int = 0
    private var isTVPresent = false
    private let server = HttpServer()
    private var serverRunning = true
    private var currentLux: Int = 0
    private var forceScale = false
    // History of lux values for computing median over the last two hours.  Each entry is
    // a timestamp and the corresponding lux measurement.
    private var luxHistory: [(Date, Int)] = []
    // Time of the last median computation logged.  Used to throttle median logging to
    // once every two hours.
    private var lastMedianLogDate: Date?

    // Flag to log only once when the first lux value is received.  Subsequent values
    // are not logged individually to avoid polluting the logs.
    private var hasLoggedFirstLux = false
    private var configWindow: NSWindow?

    private let pollingIntervals: [(label: String, value: Int)] = [
        ("10s", 10),
        ("20s", 20),
        ("30s", 30),
        ("1min", 60),
        ("2min", 120),
        ("8min", 480)
    ]
    private let pollingIntervalKey = "LunarSensorAppPollingIntervalIndex"
    private var selectedPollingIntervalIndex: Int = {
        let saved = UserDefaults.standard.integer(forKey: "LunarSensorAppPollingIntervalIndex")
        return (0..<6).contains(saved) ? saved : 0
    }()

    // Configuration utilisateur
    var tvName: String { OAuthConfigManager.shared.tvName }
    var smartthingsDeviceId: String { OAuthConfigManager.shared.deviceId }

    init() {
        killZombieOnPort(10001)
        sleep(1)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // Do not set a custom image for the status item.  We rely on a textual
        // title to represent the state (ALS Mac / TV Samsung).  An image can
        // confuse the user if no action is associated with it.
        updateStatusBar(state: .mac)
        // --- Routes Lunar Pro ---
        // 1. REST ponctuel Lunar Pro
        server["/sensor/ambient_light"] = { [weak self] _ in
            let rawLux = self?.currentLux ?? 0
            let lux = (self?.forceScale ?? false) ? self!.luxForLunar(from: rawLux) : rawLux
            let payload: [String: Any] = [
                "id":    "sensor-ambient_light",
                "state": "\(lux) lx",
                "value": Double(lux)
            ]
            return .ok(.json(payload))
        }
        // 2. Flux SSE Lunar Pro
        server["/events"] = { [weak self] _ in
            let headers = [
                "Content-Type": "text/event-stream",
                "Cache-Control": "no-cache",
                "Connection":    "keep-alive"
            ]
            return HttpResponse.raw(200, "OK", headers) { writer in
                while self?.serverRunning == true {
                    let rawLux = self?.currentLux ?? 0
                    let lux = (self?.forceScale ?? false) ? self!.luxForLunar(from: rawLux) : rawLux
                    let json = #"{"id":"sensor-ambient_light","state":"\#(lux) lx","value":\#(lux)}"#
                    try? writer.write(Array("event: state\ndata: \(json)\n\n".utf8))
                    sleep(0)
                }
            }
        }
        do {
            try server.start(10001, forceIPv4: true)
            print("Serveur HTTP Lunar lancé sur le port 10001")
        } catch {
            print("Erreur lancement serveur HTTP: \(error)")
        }
        // Ajoute le menu contextuel à la barre
        statusItem.menu = buildMenu()
        // Rafraîchit la valeur affichée dans le menu à chaque minute (optionnel)
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            self.refreshMenu()
        }
        scheduleDetection()

        // Log initial configuration state for diagnostics.
        Logger.shared.log("Initial settings: pollingInterval=\(pollingIntervals[selectedPollingIntervalIndex].label), smoothMode=\(isSmoothModeEnabled), forceScale=\(forceScale), tvName=\(tvName), deviceId=\(smartthingsDeviceId)")
    }

    /// Mapping linéaire 2 lx → 10 %, 800 lx → 100 %
    private func luxForLunar(from brutLux: Int) -> Int {
        let minLux = 2.0, maxLux = 800.0
        let minPct = 0.10, maxPct = 1.00

        let clamped = max(minLux, min(maxLux, Double(brutLux)))
        let t = (clamped - minLux) / (maxLux - minLux)
        let pct = minPct + t * (maxPct - minPct)
        return Int(pct * maxLux)
    }

    enum SensorState {
        case mac, tv
    }

    func updateStatusBar(state: SensorState) {
        DispatchQueue.main.async {
            // Always update the title to reflect the current state.  We no
            // longer use an image for the status item, so the title is
            // displayed directly in the menu bar.
            switch state {
            case .mac:
                self.statusItem.button?.title = "ALS Mac"
            case .tv:
                // Display the configured TV name instead of a generic label.
                self.statusItem.button?.title = self.tvName.isEmpty ? "TV" : self.tvName
            }
        }
    }

    // Construction dynamique du menu (à chaque ouverture)
    func buildMenu() -> NSMenu {
        let menu = NSMenu()
        // Ligne de luminosité avec titre enrichi
        let luxString = "Luminosité : \(currentLux) lux"
        let item = NSMenuItem(title: luxString, action: #selector(copyLuxToPasteboard(_:)), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        let tvStatus = isTVPresent ? "connecté" : "non connecté"
              let tvItem = NSMenuItem(title: "\(tvName) : \(tvStatus)", action: nil, keyEquivalent: "")
              menu.addItem(tvItem)
        menu.addItem(NSMenuItem.separator())

        // 1. Délai de rafraîchissement
        let refreshMenu = NSMenu()
        for (i, interval) in pollingIntervals.enumerated() {
            let item = NSMenuItem(title: interval.label, action: #selector(selectPollingInterval(_:)), keyEquivalent: "")
            item.target = self
            item.state = (i == selectedPollingIntervalIndex) ? .on : .off
            item.representedObject = i
            refreshMenu.addItem(item)
        }
        let refreshMenuItem = NSMenuItem(title: "Délai de rafraîchissement", action: nil, keyEquivalent: "")
        refreshMenuItem.submenu = refreshMenu
        menu.addItem(refreshMenuItem)

        // 2. Seconde coulante (toggle)
        let smoothItem = NSMenuItem(title: "Seconde coulante", action: #selector(toggleSmoothMode(_:)), keyEquivalent: "")
        smoothItem.target = self
        smoothItem.state = isSmoothModeEnabled ? .on : .off
        menu.addItem(smoothItem)

        // 3. Nombre d'intervalles (sous-menu visible si "seconde coulante" activé)
        if isSmoothModeEnabled {
            let intervalsMenu = NSMenu()
            for value in stride(from: 10, through: 100, by: 10) {
                let intervalItem = NSMenuItem(title: "\(value)", action: #selector(selectNumberOfSmoothSteps(_:)), keyEquivalent: "")
                intervalItem.target = self
                intervalItem.state = (value == numberOfSmoothSteps) ? .on : .off
                intervalItem.representedObject = value
                intervalsMenu.addItem(intervalItem)
            }
            let intervalsMenuItem = NSMenuItem(title: "Nombre d’intervalles", action: nil, keyEquivalent: "")
            intervalsMenuItem.submenu = intervalsMenu
            menu.addItem(intervalsMenuItem)
        }

        // 4. Sous‑menu « Connexion » regroupant les actions liées à SmartThings
        let connectionMenu = NSMenu()
        let configItem = NSMenuItem(title: "Renseignez vos données", action: #selector(openConfigWindow), keyEquivalent: "")
        configItem.target = self
        connectionMenu.addItem(configItem)

        let verifyItem = NSMenuItem(title: "Vérifier les jetons", action: #selector(checkTokens), keyEquivalent: "")
        verifyItem.target = self
        connectionMenu.addItem(verifyItem)

        let reconnectItem = NSMenuItem(title: "Reconnecter SmartThings", action: #selector(openAuthPage), keyEquivalent: "")
        reconnectItem.target = self
        connectionMenu.addItem(reconnectItem)

        let connectionItem = NSMenuItem(title: "Connexion", action: nil, keyEquivalent: "")
        connectionItem.submenu = connectionMenu
        menu.addItem(connectionItem)

        // Autres items du menu
        let scaleItem = NSMenuItem(title: "Imposer l’échelle", action: #selector(toggleForceScale), keyEquivalent: "")
        scaleItem.target = self
        scaleItem.state = forceScale ? .on : .off
        menu.addItem(scaleItem)

        // Exporter les logs juste au-dessus de Quitter
        let exportItem = NSMenuItem(title: "Exporter les logs", action: #selector(exportLogs), keyEquivalent: "")
        exportItem.target = self
        menu.addItem(exportItem)

        let quitItem = NSMenuItem(title: "Quitter", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        quitItem.isEnabled = true
        menu.addItem(quitItem)
        return menu
    }

    @objc private func toggleSmoothMode(_ sender: NSMenuItem) {
        isSmoothModeEnabled.toggle()
        restartSmartThingsTimer()
        refreshMenu()
        Logger.shared.log("User toggled second coulante: \(isSmoothModeEnabled ? "on" : "off")")
    }

    @objc private func selectNumberOfSmoothSteps(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Int else { return }
        numberOfSmoothSteps = value
        refreshMenu()
        Logger.shared.log("User selected number of smooth steps: \(value)")
    }

    @objc private func selectPollingInterval(_ sender: NSMenuItem) {
        guard let idx = sender.representedObject as? Int else { return }
        selectedPollingIntervalIndex = idx
        UserDefaults.standard.set(selectedPollingIntervalIndex, forKey: pollingIntervalKey)
        restartSmartThingsTimer()
        refreshMenu()
        // Log user action and new setting.
        let intervalInfo = pollingIntervals[idx]
        Logger.shared.log("User selected polling interval: \(intervalInfo.label) (\(intervalInfo.value)s)")
    }

    private func restartSmartThingsTimer() {
        smartthingsTimer?.invalidate()
        smartthingsTimer = nil
        if isTVPresent {
            let interval = TimeInterval(pollingIntervals[selectedPollingIntervalIndex].value)
            smartthingsTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
                self.pollSmartThings()
            }
            pollSmartThings()
            Logger.shared.log("SmartThings polling interval set to \(Int(interval)) seconds")
        }
    }

    @objc private func toggleForceScale(_ sender: NSMenuItem) {
        forceScale.toggle()
        sender.state = forceScale ? .on : .off
        refreshMenu()
        Logger.shared.log("User toggled force scale: \(forceScale ? "on" : "off")")
    }

    @objc private func openOAuthPage() {
        let config = OAuthConfigManager.shared
        guard !config.clientId.isEmpty,
              !config.redirectURI.isEmpty else { return }
        var comps = URLComponents(string: "https://api.smartthings.com/oauth/authorize")!
        comps.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: config.clientId),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI),
            URLQueryItem(name: "scope", value: Constants.scopes)
        ]
        if let url = comps.url {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openConfigWindow() {
        Logger.shared.log("User clicked on Renseignez vos données")
        OAuthConfigManager.shared.reload()
        if configWindow == nil {
            let view = OAuthConfigView()
            let controller = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: controller)
            window.title = "Renseignez vos données"
            window.styleMask.insert(.closable)
            window.isReleasedWhenClosed = false
            configWindow = window
            // Add the application icon to the window’s document icon button.
            if let icon = Logger.loadAppIcon() {
                window.standardWindowButton(.documentIconButton)?.image = icon
            }
        }
        configWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func checkTokens() {
        Logger.shared.log("User clicked on Vérifier les jetons")
        DispatchQueue.global(qos: .background).async {
            // Simply verify that a token exists and appears valid without
            // triggering an automatic refresh.  If the token is present we
            // perform a lightweight API call to confirm it is accepted by
            // SmartThings.  This avoids opening the authorization page when
            // verifying tokens.
            var tokensAreValid = OAuthManager.shared.hasValidToken()
            if tokensAreValid, let token = OAuthManager.shared.accessToken {
                var req = URLRequest(url: URL(string: "https://api.smartthings.com/v1/devices")!)
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                let sema = DispatchSemaphore(value: 0)
                var success = false
                let task = URLSession.shared.dataTask(with: req) { _, response, _ in
                    if let http = response as? HTTPURLResponse {
                        success = (200...299).contains(http.statusCode)
                    }
                    sema.signal()
                }
                task.resume()
                sema.wait()
                tokensAreValid = success
            }
            DispatchQueue.main.async {
                let alert = NSAlert()
                if tokensAreValid {
                    alert.messageText = "Jetons valides"
                    alert.informativeText = "Les jetons OAuth sont valides."
                    Logger.shared.log("Tokens valid")
                } else {
                    alert.messageText = "Jetons invalides"
                    alert.informativeText = "Les jetons sont invalides ou expirés. Utilisez le menu \"Reconnecter SmartThings\" pour réautoriser l’application."
                    Logger.shared.log("Tokens invalid")
                }
                // Assign the application icon (WebP preferred) to the alert.
                if let icon = Logger.loadAppIcon() {
                    alert.icon = icon
                }
                alert.runModal()
            }
        }
        }

    func refreshMenu() {
        // Mise à jour du menu pour afficher la dernière valeur de lux
        statusItem.menu = buildMenu()
    }
    
    @objc private func copyLuxToPasteboard(_ sender: NSMenuItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("Display : \(currentLux) Lux", forType: .string)
    }

    @objc func quitApp() {
        serverRunning = false
        print("Serveur HTTP arrêté, fermeture de l’application…")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApplication.shared.terminate(nil)
        }
    }

    /// Exports the log file to the user's Downloads directory and shows a confirmation alert.
    @objc private func exportLogs() {
        Logger.shared.log("User exported logs")
        Logger.shared.exportLogs()
        let alert = NSAlert()
        alert.messageText = "Logs exportés"
        alert.informativeText = "Le fichier log a été sauvegardé dans votre dossier Téléchargements."
        if let icon = Logger.loadAppIcon() {
            alert.icon = icon
        }
        alert.runModal()
    }
    @objc private func openAuthPage() {
        Logger.shared.log("User clicked on Reconnecter SmartThings")
        // Open the dynamic authorization URL generated from the current configuration.
        let authURLString = OAuthConfigManager.shared.authorizationURLString
        if let url = URL(string: authURLString) {
            NSWorkspace.shared.open(url)
        }
        // Immediately prompt the user to enter the authorization code.  The
        // dialog allows the user to paste the `code` parameter obtained from
        // SmartThings and will exchange it for new tokens automatically.
        OAuthTokenManager.shared.promptForAuthCode()
    }

    func scheduleDetection() {
        // Poll toutes les 10 min
        timer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { _ in
            self.detectAndSwitch()
        }
        detectAndSwitch()
    }

    func detectAndSwitch() {
        let tvIsPresent = isTVDected()
        if tvIsPresent {
            if !self.isTVPresent {
                Logger.shared.log("TV detected: switching to TV mode")
            }
            updateStatusBar(state: .tv)
            self.setLunarForTV()
            if smartthingsTimer == nil {
                let interval = TimeInterval(pollingIntervals[selectedPollingIntervalIndex].value)
                smartthingsTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
                    self.pollSmartThings()
                }
                pollSmartThings()
            }
        } else {
            if self.isTVPresent {
                Logger.shared.log("TV disconnected: switching to Mac mode")
            }
            updateStatusBar(state: .mac)
            self.setLunarForMac()
            smartthingsTimer?.invalidate()
            smartthingsTimer = nil
        }
        isTVPresent = tvIsPresent
    }

    func isTVDected() -> Bool {
        let process = Process()
        process.launchPath = "/usr/sbin/system_profiler"
        process.arguments = ["SPDisplaysDataType"]
        let pipe = Pipe()
        process.standardOutput = pipe
        do {
            try process.run()
        } catch {
            return false
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return false }
        return output.contains(tvName)
    }
    /*
    Détection automatique d’un écran “exotique” (typiquement TV ou projecteur non Apple).

    Cette version extrait toutes les lignes d’écran du retour de system_profiler,
    cherche les noms qui ne contiennent pas “Display” (cas des moniteurs Apple/LG UltraFine/Studio Display etc.).
    Dès qu’un nom “atypique” est détecté (par ex. une TV Samsung), on retourne true.

    func isTVDected() -> Bool {
        let process = Process()
        process.launchPath = "/usr/sbin/system_profiler"
        process.arguments = ["SPDisplaysDataType"]
        let pipe = Pipe()
        process.standardOutput = pipe
        do {
            try process.run()
        } catch {
            return false
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return false }
        
        // Recherche de toutes les lignes d'écran
        // On extrait les lignes type "XXX:" (nom d'écran) et on filtre celles sans "Display"
        let pattern = #"^\s*([^\:]+):$"#
        let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        let nsrange = NSRange(output.startIndex..<output.endIndex, in: output)
        let matches = regex?.matches(in: output, options: [], range: nsrange) ?? []
        
        for match in matches {
            if let range = Range(match.range(at: 1), in: output) {
                let screenName = output[range]
                if !screenName.localizedCaseInsensitiveContains("Display") {
                    // On a trouvé un écran non-Apple → mode TV !
                    return true
                }
            }
        }
        // Aucun écran "exotique" trouvé, c'est du Apple Display only
        return false
    }
    */
    func setLunarForTV() {
        shell("defaults write fyi.lunar.Lunar sensorHostname 127.0.0.1")
        shell("defaults write fyi.lunar.Lunar sensorPort 10001")
        shell("defaults write fyi.lunar.Lunar sensorPathPrefix /")
        Logger.shared.log("Configured Lunar for TV mode (hostname=127.0.0.1, port=10001)")
    }

    func setLunarForMac() {
        shell("defaults delete fyi.lunar.Lunar sensorHostname")
        shell("defaults delete fyi.lunar.Lunar sensorPort")
        shell("defaults delete fyi.lunar.Lunar sensorPathPrefix")
        Logger.shared.log("Configured Lunar for Mac mode (reset sensor settings)")
    }

    func pollSmartThings() {
        Logger.shared.log("Connecting to SmartThings to fetch status")
        // Actualise le jeton si nécessaire avant l'appel
        OAuthManager.shared.refreshAccessTokenIfNeeded()
        guard let token = OAuthManager.shared.accessToken else { return }
        let urlStr = "https://api.smartthings.com/v1/devices/\(smartthingsDeviceId)/status"
        var req = URLRequest(url: URL(string: urlStr)!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let task = URLSession.shared.dataTask(with: req) { data, response, error in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let components = json["components"] as? [String: Any],
                  let main = components["main"] as? [String: Any],
                  let illum = main["illuminanceMeasurement"] as? [String: Any],
                  let lux = (illum["illuminance"] as? [String: Any])?["value"] as? Int
            else {
                Logger.shared.log("Failed to parse SmartThings response")
                return
            }
            if !self.hasLoggedFirstLux {
                Logger.shared.log("Lux data has been received")
                self.hasLoggedFirstLux = true
            }
            // Maintain a history of lux readings for median computation.
            let now = Date()
            self.luxHistory.append((now, lux))
            // Remove entries older than 2 hours
            let cutoff = now.addingTimeInterval(-7200)
            self.luxHistory.removeAll { $0.0 < cutoff }
            // If two hours have passed since the last median log, compute and log the median
            if let last = self.lastMedianLogDate {
                if now.timeIntervalSince(last) >= 7200 {
                    let values = self.luxHistory.map { $0.1 }.sorted()
                    if !values.isEmpty {
                        let median: Int
                        let mid = values.count / 2
                        if values.count % 2 == 1 {
                            median = values[mid]
                        } else {
                            median = (values[mid] + values[mid - 1]) / 2
                        }
                        Logger.shared.log("Median lux (last 2h): \(median) lx")
                        self.lastMedianLogDate = now
                    }
                }
            } else {
                // First time computing median
                let values = self.luxHistory.map { $0.1 }.sorted()
                if !values.isEmpty {
                    let mid = values.count / 2
                    let median = values.count % 2 == 1 ? values[mid] : (values[mid] + values[mid - 1]) / 2
                    Logger.shared.log("Median lux (last 2h): \(median) lx")
                    self.lastMedianLogDate = now
                }
            }
            print("Lux = \(lux)")
            DispatchQueue.main.async {
                if self.isSmoothModeEnabled {
                    self.startSmoothLuxTransition(to: lux)
                } else {
                    self.currentLux = lux
                    self.refreshMenu()
                }
            }
        }
        task.resume()
    }

    private func startSmoothLuxTransition(to newLux: Int) {
        smoothTimerSource?.cancel()
        let oldLux = currentLux
        targetLux = newLux
        let duration = TimeInterval(pollingIntervals[selectedPollingIntervalIndex].value)
        let steps = numberOfSmoothSteps
        let interval = duration / Double(steps)
        let delta = Double(targetLux - oldLux) / Double(steps)
        var n = 0

        let queue = DispatchQueue(label: "lux.smooth.timer")
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: interval)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            n += 1
            let nextLux = Int(round(Double(oldLux) + delta * Double(n)))
            self.currentLux = nextLux
            DispatchQueue.main.async {
                self.refreshMenu()
            }
            if n >= steps {
                timer.cancel()
                self.currentLux = self.targetLux
                DispatchQueue.main.async {
                    self.refreshMenu()
                }
            }
        }
        self.smoothTimerSource = timer
        timer.resume()
    }

    @discardableResult
    func shell(_ command: String) -> Int32 {
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", command]
        task.launch()
        task.waitUntilExit()
        return task.terminationStatus
    }
    deinit {
        server.stop()
    }
}
/// Tuer tout process qui occupe le port 10001
func killZombieOnPort(_ port: Int) {
        let myPid = getpid()
    let task = Process()
    let pipe = Pipe()
    task.launchPath = "/usr/sbin/lsof"
    task.arguments = ["-ti", ":\(port)"]
    task.standardOutput = pipe

    do {
        try task.run()
        task.waitUntilExit()
    } catch {
        print("Erreur lors de l'exécution de lsof : \(error)")
        return
    }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard let pidsString = String(data: data, encoding: .utf8) else { return }
    let pids = pidsString
        .split(separator: "\n")
        .compactMap { Int($0) }
            .filter { $0 != myPid }

    for pid in pids {
        let killTask = Process()
        killTask.launchPath = "/bin/kill"
        killTask.arguments = ["-9", "\(pid)"]
        do {
            try killTask.run()
            killTask.waitUntilExit()
            print("Processus \(pid) tué sur le port \(port)")
        } catch {
            print("Erreur lors de la tentative de kill : \(error)")
        }
    }
}
