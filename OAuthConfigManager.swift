import Foundation
import Combine

class OAuthConfigManager: ObservableObject {
    static let shared = OAuthConfigManager()

    @Published var clientId: String
    @Published var clientSecret: String
    @Published var redirectURI: String
    @Published var tvName: String
    @Published var refreshToken: String
    @Published var deviceId: String
    private init() {
        clientId = ""
        clientSecret = ""
        redirectURI = ""
        tvName = ""
        refreshToken = ""
        deviceId = ""
        reload()
    }

    /// Reload persisted OAuth configuration into the published properties.
    func reload() {
        let defaults = UserDefaults.standard
        let savedClientId = defaults.string(forKey: "OAuthClientId")
        let savedRedirect = defaults.string(forKey: "OAuthRedirectURI")
                let savedTVName = defaults.string(forKey: "TVName")
                let savedDeviceId = defaults.string(forKey: "DeviceId")

                clientId = savedClientId?.isEmpty == false ? savedClientId! : Constants.clientId
        redirectURI = savedRedirect ?? Constants.redirectURI
                tvName = savedTVName ?? Constants.tvName
                deviceId = savedDeviceId ?? Constants.deviceId
        let savedSecret = defaults.string(forKey: "OAuthClientSecret")
                clientSecret = savedSecret?.isEmpty == false ? savedSecret! : Constants.clientSecret

                let savedRefresh = defaults.string(forKey: "smartthingsRefreshToken")
                    refreshToken = savedRefresh?.isEmpty == false ? savedRefresh! : Constants.refreshToken
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(clientId, forKey: "OAuthClientId")
        defaults.set(redirectURI, forKey: "OAuthRedirectURI")
        defaults.set(tvName, forKey: "TVName")
        defaults.set(deviceId, forKey: "DeviceId")
                defaults.set(clientSecret, forKey: "OAuthClientSecret")
                defaults.set(refreshToken, forKey: "smartthingsRefreshToken")
    }

    /// Builds the SmartThings authorization URL from the current configuration.
    ///
    /// The URL is composed using the client identifier, redirect URI and requested scopes.
    /// Values are percent‑encoded to ensure a valid query string.
    var authorizationURLString: String {
        let encodedRedirect = redirectURI.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encodedScopes = Constants.scopes.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return "https://api.smartthings.com/oauth/authorize?response_type=code&client_id=\(clientId)&redirect_uri=\(encodedRedirect)&scope=\(encodedScopes)"
    }
}
