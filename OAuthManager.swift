
import Foundation

class OAuthManager {
    static let shared = OAuthManager()
    private init() {}

    private let tokenKey = "smartthingsAccessToken"
    private let refreshKey = "smartthingsRefreshToken"
    private let expiryKey = "smartthingsTokenExpiry"
    private let defaults = UserDefaults.standard

    private var refreshTimer: Timer?

    var accessToken: String? {
        return defaults.string(forKey: tokenKey)
    }

    private var expirationDate: Date? {
        let ts = defaults.double(forKey: expiryKey)
        return ts == 0 ? nil : Date(timeIntervalSince1970: ts)
    }

    func saveTokens(access: String, refresh: String, expiresIn: Int) {
        defaults.set(access, forKey: tokenKey)
                defaults.set(refresh, forKey: refreshKey)
        let expiry = Date().addingTimeInterval(TimeInterval(expiresIn))
        defaults.set(expiry.timeIntervalSince1970, forKey: expiryKey)
    }

    func clearTokens() {
        defaults.removeObject(forKey: tokenKey)
                defaults.removeObject(forKey: refreshKey)
                defaults.removeObject(forKey: expiryKey)
    }

    func hasValidToken() -> Bool {
        guard accessToken != nil, let expiry = expirationDate else { return false }
        return Date() < expiry
    }

    /// Copies the refresh token from `Constants` if none exists and tries to refresh the access token.
    func initializeTokens() {
        if defaults.string(forKey: tokenKey) == nil {
                    defaults.set(Constants.accessToken, forKey: tokenKey)
        }
        if defaults.string(forKey: refreshKey) == nil {
            defaults.set(Constants.refreshToken, forKey: refreshKey)
        }
        validateAccessToken()
    }

    /// Refreshes the access token if it's missing or will expire within the next 22 hours.
    func refreshAccessTokenIfNeeded(force: Bool = false) {
        guard let refreshToken = defaults.string(forKey: refreshKey) else { return }

        let shouldRefresh: Bool
        if force {
                    shouldRefresh = true
                } else if let expiry = expirationDate {
                    shouldRefresh = Date() >= expiry.addingTimeInterval(-60)
        } else {
            shouldRefresh = true
        }
        guard shouldRefresh else { return }

        let config = OAuthConfigManager.shared
        guard !config.clientId.isEmpty, !config.clientSecret.isEmpty else { return }
        let semaphore = DispatchSemaphore(value: 0)
        var newAccess: String?
        var newRefresh: String?
        var expires: Int?

        OAuthTokenManager.requestNewTokens(clientId: config.clientId,
                                           clientSecret: config.clientSecret,
                                                                                      refreshToken: refreshToken) { access, refresh, exp in
                                                       newAccess = access
                                                       newRefresh = refresh
                                                       expires = exp
                                                       semaphore.signal()
        }
        semaphore.wait()

        if let a = newAccess, let r = newRefresh, let exp = expires {
                    saveTokens(access: a, refresh: r, expiresIn: exp)
                    scheduleRefreshTimer(interval: TimeInterval(max(60, exp - 60)))
                } else if let a = newAccess, let r = newRefresh {
                    let fallback = 23 * 3600
                    saveTokens(access: a, refresh: r, expiresIn: fallback)
                    scheduleRefreshTimer(interval: TimeInterval(fallback - 60))
        }
    }

    func startAutomaticRefresh() {
        // Validate the token immediately when starting automatic refresh.  A refresh will be
        // triggered if the token is expired or invalid.
        validateAccessToken()
    }

    private func scheduleRefreshTimer(interval: TimeInterval? = nil) {
        // Cancel any existing timer.
        refreshTimer?.invalidate()
        // Choose a delay: explicit interval or expiry minus one minute.  Default to one hour.
        let delay: TimeInterval
        if let i = interval {
            delay = i
        } else if let expiry = expirationDate {
            delay = max(60, expiry.timeIntervalSinceNow - 60)
        } else {
            delay = 3600
        }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.refreshAccessTokenIfNeeded()
        }
        if let timer = refreshTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }
    
    private func validateAccessToken() {
        guard let token = defaults.string(forKey: tokenKey) else {
            refreshAccessTokenIfNeeded(force: true)
            return
        }
        var req = URLRequest(url: URL(string: "https://api.smartthings.com/v1/devices")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let sema = DispatchSemaphore(value: 0)
        var unauthorized = false
        let task = URLSession.shared.dataTask(with: req) { _, response, _ in
            if let http = response as? HTTPURLResponse, http.statusCode == 401 {
                unauthorized = true
            }
            sema.signal()
        }
        task.resume()
        sema.wait()
        if unauthorized {
            refreshAccessTokenIfNeeded(force: true)
        } else {
            scheduleRefreshTimer()
        }
    }
}
