import SwiftUI

struct OAuthConfigView: View {
    @ObservedObject var manager = OAuthConfigManager.shared
    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Configuration OAuth2")
                .font(.headline)
                .padding(.bottom, 4)
            Form {
                TextField("TV Name", text: $manager.tvName)
                TextField("Client ID", text: $manager.clientId)
                SecureField("Client Secret", text: $manager.clientSecret)
                SecureField("Refresh Token", text: $manager.refreshToken)
                TextField("Device ID", text: $manager.deviceId)
                TextField("Redirect URI", text: $manager.redirectURI)
            }
            HStack {
                Spacer()
                Button("Annuler") {
                    presentationMode.wrappedValue.dismiss()
                }
                Button("Enregistrer") {
                    manager.save()
                    OAuthConfigManager.shared.reload()
                    OAuthManager.shared.initializeTokens()
                    presentationMode.wrappedValue.dismiss()
                }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
