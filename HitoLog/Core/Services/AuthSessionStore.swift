import AuthenticationServices
import CryptoKit
import Foundation
import Security

#if canImport(FirebaseAuth)
import FirebaseAuth
#endif

@MainActor
final class AuthSessionStore: NSObject, ObservableObject {
    @Published private(set) var state: AppSessionState = .signedOut
    @Published private(set) var currentUserID: String?
    @Published private(set) var appleUserID: String?
    @Published private(set) var displayName: String?
    @Published private(set) var email: String?
    @Published private(set) var isFirebaseAuthAvailable = FirebaseBootstrap.isConfigured
    @Published var errorMessage: String?

    private var currentNonce: String?
    private var lastAppleAuthorizationCode: String?

    #if canImport(FirebaseAuth)
    private var authStateHandle: AuthStateDidChangeListenerHandle?
    #endif

    func start() {
        isFirebaseAuthAvailable = FirebaseBootstrap.isConfigured

        #if canImport(FirebaseAuth)
        guard FirebaseBootstrap.isConfigured, authStateHandle == nil else { return }
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                guard let self else { return }
                if let user {
                    self.currentUserID = user.uid
                    self.displayName = user.displayName
                    self.email = user.email
                    self.state = .ready
                } else {
                    self.currentUserID = nil
                    self.appleUserID = nil
                    self.displayName = nil
                    self.email = nil
                    self.lastAppleAuthorizationCode = nil
                    self.state = .signedOut
                }
            }
        }
        #endif
    }

    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = randomNonceString()
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)
    }

    @discardableResult
    func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) async -> Bool {
        switch result {
        case .success(let authorization):
            return await signInToFirebase(with: authorization)
        case .failure(let error):
            errorMessage = error.localizedDescription
            return false
        }
    }

    func continueWithLocalPreview() {
        currentUserID = "user-yuuki"
        appleUserID = nil
        displayName = "Yuuki"
        email = nil
        state = .ready
    }

    func signOut() {
        #if canImport(FirebaseAuth)
        if FirebaseBootstrap.isConfigured {
            do {
                try Auth.auth().signOut()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        #endif

        currentUserID = nil
        appleUserID = nil
        displayName = nil
        email = nil
        lastAppleAuthorizationCode = nil
        state = .signedOut
    }

    @discardableResult
    func deleteAccount() async -> Bool {
        #if canImport(FirebaseAuth)
        if FirebaseBootstrap.isConfigured, let user = Auth.auth().currentUser {
            do {
                if let lastAppleAuthorizationCode {
                    try? await Auth.auth().revokeToken(withAuthorizationCode: lastAppleAuthorizationCode)
                }
                try await user.delete()
            } catch {
                errorMessage = error.localizedDescription
                return false
            }
        }
        #endif

        signOut()
        return true
    }

    private func signInToFirebase(with authorization: ASAuthorization) async -> Bool {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            errorMessage = "Apple IDの認証情報を取得できませんでした。"
            return false
        }

        appleUserID = appleIDCredential.user
        displayName = formattedName(from: appleIDCredential.fullName)
        email = appleIDCredential.email
        lastAppleAuthorizationCode = authorizationCode(from: appleIDCredential)

        #if canImport(FirebaseAuth)
        guard FirebaseBootstrap.isConfigured else {
            state = .ready
            currentUserID = appleIDCredential.user
            return true
        }

        guard let nonce = currentNonce else {
            errorMessage = "認証セッションを開始し直してください。"
            return false
        }

        guard let appleIDToken = appleIDCredential.identityToken,
              let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
            errorMessage = "Apple IDトークンを取得できませんでした。"
            return false
        }

        do {
            let credential = OAuthProvider.appleCredential(
                withIDToken: idTokenString,
                rawNonce: nonce,
                fullName: appleIDCredential.fullName
            )
            let authResult = try await Auth.auth().signIn(with: credential)
            currentUserID = authResult.user.uid
            state = .ready
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
        #else
        state = .ready
        currentUserID = appleIDCredential.user
        return true
        #endif
    }

    private func formattedName(from components: PersonNameComponents?) -> String? {
        guard let components else { return nil }
        let formatted = PersonNameComponentsFormatter.localizedString(from: components, style: .medium)
        let trimmed = formatted.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func authorizationCode(from credential: ASAuthorizationAppleIDCredential) -> String? {
        guard let authorizationCode = credential.authorizationCode,
              let code = String(data: authorizationCode, encoding: .utf8),
              !code.isEmpty else {
            return nil
        }

        return code
    }

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            var randomBytes = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
            guard status == errSecSuccess else {
                fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(status)")
            }

            for randomByte in randomBytes where remainingLength > 0 {
                let randomIndex = Int(randomByte)
                if randomIndex < charset.count {
                    result.append(charset[randomIndex])
                    remainingLength -= 1
                }
            }
        }

        return result
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.map { String(format: "%02x", $0) }.joined()
    }
}
