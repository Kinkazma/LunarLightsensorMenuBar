import Foundation
import AppKit

/// Simple manager to obtain and refresh SmartThings OAuth tokens.
final class OAuthTokenManager {
    static let shared = OAuthTokenManager()
    private init() { loadTokens() }

    private let clientId = Constants.clientId
    private let clientSecret = Constants.clientSecret
    private let deviceId = Constants.deviceId

    // Stored access and refresh tokens along with their expiration date.  These are
    // initialized from the Constants values and updated whenever a refresh occurs.
    private var accessToken: String = Constants.accessToken
    private var refreshToken: String = Constants.refreshToken
    private var expirationDate: Date?

        private let defaults = UserDefaults.standard
        private let tokenKey = "smartthingsAccessToken"
        private let refreshKey = "smartthingsRefreshToken"
        private let expiryKey = "smartthingsTokenExpiry"

    private var refreshTimer: Timer?
    
    private func loadTokens() {
        if let storedAccess = defaults.string(forKey: tokenKey) {
            accessToken = storedAccess
        }
        if let storedRefresh = defaults.string(forKey: refreshKey) {
            refreshToken = storedRefresh
        }
        let ts = defaults.double(forKey: expiryKey)
        if ts != 0 { expirationDate = Date(timeIntervalSince1970: ts) }
    }

    private func saveTokens(access: String, refresh: String, expiresIn: Int) {
        accessToken = access
        refreshToken = refresh
        expirationDate = Date().addingTimeInterval(TimeInterval(expiresIn))
        defaults.set(access, forKey: tokenKey)
        defaults.set(refresh, forKey: refreshKey)
        defaults.set(expirationDate!.timeIntervalSince1970, forKey: expiryKey)
    }
    
    /// Refresh the SmartThings tokens using the provided credentials.
    /// - Parameters:
    ///   - clientId: OAuth client identifier
    ///   - clientSecret: OAuth client secret
    ///   - refreshToken: Current refresh token
    ///   - completion: Completion handler with optional new access and refresh tokens and the expiration interval in seconds.
    static func requestNewTokens(clientId: String,
                                 clientSecret: String,
                                 refreshToken: String,
                                 completion: @escaping (String?, String?, Int?) -> Void) {
        guard let url = URL(string: "https://api.smartthings.com/oauth/token") else {
            completion(nil, nil, nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let credentials = "\(clientId):\(clientSecret)"
        guard let encoded = credentials.data(using: .utf8)?.base64EncodedString() else {
            completion(nil, nil, nil)
            return
        }
        request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "grant_type=refresh_token&refresh_token=\(refreshToken)"
        request.httpBody = body.data(using: .utf8)

        URLSession.shared.dataTask(with: request) { data, response, _ in
            if let httpResponse = response as? HTTPURLResponse {
                print("Code HTTP :", httpResponse.statusCode)
                Logger.shared.log("requestNewTokens: HTTP \(httpResponse.statusCode)")
            }
            if let data = data {
                print("Réponse du refresh token :", String(data: data, encoding: .utf8) ?? "aucune donnée")
                if let string = String(data: data, encoding: .utf8) {
                    Logger.shared.log("requestNewTokens response: \(string)")
                }
            }
            guard
                let data = data,
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                print("Erreur lors de la requête de rafraîchissement du token")
                completion(nil, nil, nil)
                return
            }
            
            if let error = json["error"] as? String, error == "invalid_grant" {
                // When the refresh token is no longer valid the user must reauthorize.
                Logger.shared.log("Error refreshing token: invalid_grant")
                DispatchQueue.main.async {
                    let authURLString = OAuthConfigManager.shared.authorizationURLString
                    if let url = URL(string: authURLString) {
                        NSWorkspace.shared.open(url)
                    }
                    // Prompt the user to enter the authorization code once they
                    // complete the OAuth flow. This will display a dialog with
                    // a text field for the code and automatically exchange it
                    // for fresh tokens.  We reference the singleton instance
                    // here because this static method has no instance context.
                    OAuthTokenManager.shared.promptForAuthCode()
                }
                completion(nil, nil, nil)
                return
            }

            let access = json["access_token"] as? String
            let newRefresh = json["refresh_token"] as? String
            let expires = json["expires_in"] as? Int
            if access != nil {
                Logger.shared.log("Refreshing access token... success.")
            }
            completion(access, newRefresh, expires)
        }.resume()
    }


    /// Starts automatic refresh based on the expiration interval.
    ///
    /// This method validates the currently stored access token by making a test API call.
    /// If the token is expired or invalid (HTTP 401), a refresh is triggered automatically.
    /// Once the token is deemed valid, a refresh timer is scheduled based on the remaining
    /// lifetime of the token.
    func startAutomaticRefresh() {
        validateAccessToken()
    }

    /// Returns a valid access token, refreshing it beforehand.
    func getAccessToken(completion: @escaping (String?) -> Void) {
        refreshAccessToken { success in
            completion(success ? self.accessToken : nil)
        }
    }

    private func refreshAccessToken(completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "https://api.smartthings.com/oauth/token") else {
            completion(false)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let credentials = "\(clientId):\(clientSecret)"
        guard let encoded = credentials.data(using: .utf8)?.base64EncodedString() else {
            completion(false)
            return
        }
        request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "grant_type=refresh_token&refresh_token=\(refreshToken)"
        request.httpBody = body.data(using: .utf8)

        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            if let httpResponse = response as? HTTPURLResponse {
                print("Code HTTP :", httpResponse.statusCode)
                Logger.shared.log("refreshAccessToken: HTTP \(httpResponse.statusCode)")
            }
            if let data = data {
                let respString = String(data: data, encoding: .utf8) ?? "aucune donnée"
                print("Réponse du refresh token :", respString)
                Logger.shared.log("refreshAccessToken response: \(respString)")
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("Erreur lors de la requête de rafraîchissement du token")
                completion(false)
                return
            }

            if let error = json["error"] as? String, error == "invalid_grant" {
                // When the refresh token is no longer valid the user must reauthorize.
                Logger.shared.log("Error refreshing token: invalid_grant")
                DispatchQueue.main.async {
                    let authURLString = OAuthConfigManager.shared.authorizationURLString
                    if let url = URL(string: authURLString) {
                        NSWorkspace.shared.open(url)
                    }
                    // Prompt the user for the authorization code and perform
                    // the token exchange.  See `promptForAuthCode()` for details.
                    self.promptForAuthCode()
                }
                completion(false)
                return
            }

            guard let newAccess = json["access_token"] as? String,
                  let newRefresh = json["refresh_token"] as? String,
                  let expires = json["expires_in"] as? Int else {
                Logger.shared.log("Error refreshing token: invalid response")
                print("Réponse invalide lors du rafraîchissement du token")
                completion(false)
                return
            }
            self.saveTokens(access: newAccess, refresh: newRefresh, expiresIn: expires)
            self.scheduleRefreshTimer(interval: TimeInterval(max(60, expires - 60)))
            Logger.shared.log("Refreshing access token... success.")
            completion(true)
        }
        task.resume()
    }
    private func scheduleRefreshTimer(interval: TimeInterval? = nil) {
        // Cancel any existing refresh timer.
        refreshTimer?.invalidate()
        // Determine the delay before the next refresh. If an explicit interval is supplied it
        // is used directly; otherwise the delay is based on the stored expiration date minus
        // one minute. A minimum delay of 60 seconds prevents rapid polling.
        let delay: TimeInterval
        if let i = interval {
            delay = i
        } else if let expiry = expirationDate {
            delay = max(60, expiry.timeIntervalSinceNow - 60)
        } else {
            delay = 3600
        }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.refreshAccessToken { _ in }
        }
        if let timer = refreshTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func validateAccessToken() {
        guard let url = URL(string: "https://api.smartthings.com/v1/devices") else { return }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let task = URLSession.shared.dataTask(with: req) { [weak self] _, response, _ in
            guard let self = self else { return }
            if let http = response as? HTTPURLResponse, http.statusCode == 401 {
                // The access token is invalid or expired; refresh immediately.
                self.refreshAccessToken { _ in }
            } else {
                // Token appears valid; schedule a refresh based on its expiry and log.
                Logger.shared.log("Access token is valid.")
                self.scheduleRefreshTimer()
            }
        }
        task.resume()
    }

    /// Convenience getter for the configured device identifier.
    func getDeviceId() -> String {
        return deviceId
    }

    // MARK: - Authorization code flow

    /// Presents a dialog to the user asking for the SmartThings authorization code.
    ///
    /// This method is invoked when the refresh token has become invalid and the
    /// user must reauthorize the application. It displays a modal alert with a
    /// text field into which the user can paste the code returned by the
    /// SmartThings authorization page (the portion following `code=`). Once the
    /// user confirms, the code is exchanged for new access and refresh tokens.
    func promptForAuthCode() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Entrez le code d’autorisation"
            alert.informativeText = "Copiez‑collez ici le code fourni par SmartThings (sans les guillemets)."
            // Assign the application icon to the alert (WebP preferred)
            if let icon = Logger.loadAppIcon() {
                alert.icon = icon
            }
            let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
            textField.placeholderString = "Ex. 97_RCp"
            alert.accessoryView = textField
            alert.addButton(withTitle: "Valider")
            alert.addButton(withTitle: "Annuler")
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                let code = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !code.isEmpty else { return }
                self.exchangeAuthorizationCode(code: code)
            }
        }
    }

    /// Exchanges an authorization code for access and refresh tokens.
    ///
    /// - Parameter code: The code returned by SmartThings after the user
    ///   completes the OAuth authorization flow. Only the code value (without
    ///   the `code=` prefix) should be provided.
    private func exchangeAuthorizationCode(code: String) {
        // Retrieve the current OAuth configuration. We favor the values stored
        // by `OAuthConfigManager` since the user may have updated them in the
        // configuration window. Falling back to Constants ensures we always have
        // a value for the redirect URI.
        let config = OAuthConfigManager.shared
        let clientId = config.clientId.isEmpty ? Constants.clientId : config.clientId
        let clientSecret = config.clientSecret.isEmpty ? Constants.clientSecret : config.clientSecret
        let redirectURI = config.redirectURI.isEmpty ? Constants.redirectURI : config.redirectURI

        guard let url = URL(string: "https://api.smartthings.com/oauth/token") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let credentials = "\(clientId):\(clientSecret)"
        guard let encoded = credentials.data(using: .utf8)?.base64EncodedString() else { return }
        request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        // Build the body for the authorization_code grant. The client_id and
        // redirect_uri parameters are included for completeness even though
        // they may be redundant when using HTTP Basic authentication.
        let body = "grant_type=authorization_code&client_id=\(clientId)&code=\(code)&redirect_uri=\(redirectURI)"
        request.httpBody = body.data(using: .utf8)

        URLSession.shared.dataTask(with: request) { data, response, _ in
            if let http = response as? HTTPURLResponse {
                print("Code HTTP (auth code) :", http.statusCode)
                Logger.shared.log("exchangeAuthorizationCode: HTTP \(http.statusCode)")
            }
            if let data = data {
                if let respString = String(data: data, encoding: .utf8) {
                    print("Réponse code → token :", respString)
                    Logger.shared.log("exchangeAuthorizationCode response: \(respString)")
                }
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("Erreur lors de l’échange du code d’autorisation")
                return
            }
            if let error = json["error"] as? String {
                print("Erreur lors de l’échange du code : \(error)")
                return
            }
            guard let newAccess = json["access_token"] as? String,
                  let newRefresh = json["refresh_token"] as? String,
                  let expires = json["expires_in"] as? Int else {
                print("Réponse invalide lors de l’échange du code")
                return
            }
            // Persist the tokens and schedule refresh. We reuse the saveTokens
            // function to update both in‑memory and UserDefaults values.
            self.saveTokens(access: newAccess, refresh: newRefresh, expiresIn: expires)
            // Also update the configuration manager’s refresh token so that it
            // reflects the latest value when displayed in the configuration UI.
            DispatchQueue.main.async {
                OAuthConfigManager.shared.refreshToken = newRefresh
                OAuthConfigManager.shared.save()
            }
            self.scheduleRefreshTimer(interval: TimeInterval(max(60, expires - 60)))
        }.resume()
    }

    // End of class declaration
}


//  OAuthTokenManager.swift
//  LunarSensorAppMenuBar
//
//  Created by Gael Dauchy on 29/07/2025.
//

