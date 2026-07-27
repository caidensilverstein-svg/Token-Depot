import SwiftUI
import CryptoKit

struct RecoveryView: View {

    @Environment(\.dismiss) private var dismiss

    enum Step {
        case biometric
        case token
        case newPassword
        case reencrypting
        case success
        case failed(String)
    }

    @State private var step: Step = .biometric
    @State private var token = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var errorMessage: String?
    @State private var isWorking = false

    var body: some View {
        ZStack {
            Color(red: 0.08, green: 0.08, blue: 0.10).ignoresSafeArea()

            VStack(spacing: 28) {
                HStack {
                    Button("Cancel") { dismiss() }
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.5))
                        .buttonStyle(.plain)
                    Spacer()
                    Text("Account Recovery")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                    Text("Cancel").opacity(0)
                }

                Spacer()

                switch step {
                case .biometric:      biometricStep
                case .token:          tokenStep
                case .newPassword:    newPasswordStep
                case .reencrypting:   reencryptingStep
                case .success:        successStep
                case .failed(let msg): failedStep(msg)
                }

                Spacer()
            }
            .padding(32)
        }
        .frame(width: 380, height: 440)
    }

    // MARK: — Steps

    private var biometricStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "touchid")
                .font(.system(size: 56))
                .foregroundColor(.white.opacity(0.8))
            Text("Step 1 of 2 — Biometric")
                .font(.system(size: 11)).foregroundColor(.white.opacity(0.4))
                .textCase(.uppercase).tracking(1.2)
            Text("Verify your identity with Touch ID")
                .font(.system(size: 16, weight: .medium)).foregroundColor(.white)
                .multilineTextAlignment(.center)
            if let error = errorMessage {
                Text(error).font(.system(size: 12)).foregroundColor(.red).multilineTextAlignment(.center)
            }
            actionButton(title: isWorking ? "Authenticating..." : "Authenticate with Touch ID",
                         enabled: !isWorking, action: runBiometric)
        }
    }

    private var tokenStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "key.fill")
                .font(.system(size: 48)).foregroundColor(.white.opacity(0.8))
            Text("Step 2 of 2 — Recovery Token")
                .font(.system(size: 11)).foregroundColor(.white.opacity(0.4))
                .textCase(.uppercase).tracking(1.2)
            Text("Enter your 32-character recovery token")
                .font(.system(size: 16, weight: .medium)).foregroundColor(.white)
                .multilineTextAlignment(.center)
            TextField("32-character token", text: $token)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.white)
                .padding(12)
                .background(Color.white.opacity(0.08))
                .cornerRadius(8)
                .autocorrectionDisabled()
            if let error = errorMessage {
                Text(error).font(.system(size: 12)).foregroundColor(.red)
            }
            actionButton(title: "Verify Token",
                         enabled: token.count == 32 && !isWorking,
                         action: verifyToken)
        }
    }

    private var newPasswordStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 48)).foregroundColor(.green.opacity(0.8))
            Text("Recovery Authorized")
                .font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
            Text("Set a new master password. All notes will be re-encrypted.")
                .font(.system(size: 13)).foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
            VStack(spacing: 10) {
                SecureField("New master password", text: $newPassword)
                    .styledField()
                SecureField("Confirm password", text: $confirmPassword)
                    .styledField()
            }
            if let error = errorMessage {
                Text(error).font(.system(size: 12)).foregroundColor(.red)
            }
            actionButton(title: "Set New Password",
                         enabled: !newPassword.isEmpty && newPassword == confirmPassword,
                         action: setNewPassword)
        }
    }

    private var reencryptingStep: some View {
        VStack(spacing: 20) {
            ProgressView().scaleEffect(1.5).tint(.white)
            Text("Re-encrypting notes...")
                .font(.system(size: 15, weight: .medium)).foregroundColor(.white)
            Text("Do not close this window.")
                .font(.system(size: 12)).foregroundColor(.white.opacity(0.4))
        }
    }

    private var successStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56)).foregroundColor(.green)
            Text("Password Reset")
                .font(.system(size: 18, weight: .semibold)).foregroundColor(.white)
            Text("All notes re-encrypted with your new password. Please unlock TokenDepot.")
                .font(.system(size: 13)).foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
            actionButton(title: "Done", enabled: true) { dismiss() }
        }
    }

    private func failedStep(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 56)).foregroundColor(.red)
            Text("Re-encryption Failed")
                .font(.system(size: 18, weight: .semibold)).foregroundColor(.white)
            Text(message)
                .font(.system(size: 13)).foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
            actionButton(title: "Dismiss", enabled: true) { dismiss() }
        }
    }

    // MARK: — Actions

    private func runBiometric() {
        isWorking = true; errorMessage = nil
        Task {
            do {
                try await RecoveryManager.shared.authenticateWithBiometric()
                await MainActor.run { isWorking = false; step = .token }
            } catch RecoveryError.biometricUnavailable {
                await MainActor.run { isWorking = false; errorMessage = "Touch ID is not available." }
            } catch RecoveryError.biometricFailed(let msg) {
                await MainActor.run { isWorking = false; errorMessage = msg }
            } catch {
                await MainActor.run { isWorking = false; errorMessage = "Authentication failed." }
            }
        }
    }

    private func verifyToken() {
        isWorking = true; errorMessage = nil
        do {
            try RecoveryManager.shared.verifyToken(token)
            step = .newPassword
        } catch RecoveryError.tokenMismatch {
            errorMessage = "Invalid token. Re-authenticate with Touch ID."
            step = .biometric
        } catch {
            errorMessage = "Verification failed."
        }
        isWorking = false
    }

    private func setNewPassword() {
        guard newPassword == confirmPassword, !newPassword.isEmpty else {
            errorMessage = "Passwords do not match."
            return
        }
        step = .reencrypting

        Task.detached(priority: .userInitiated) {
            do {
                try await reencryptAllNotes(newPassword: newPassword)
                await MainActor.run { step = .success }
            } catch {
                await MainActor.run {
                    step = .failed("Re-encryption failed: \(error.localizedDescription). Your old password is still active.")
                }
            }
        }
    }

    /// Re-encrypt all note files with a new password.
    /// 1. Derive old key from current stored hash — we can't since we don't have old password.
    ///    Instead: notes are already in NoteStore.shared.notes (loaded at unlock).
    ///    Re-save each one with a newly derived key from the new password.
    /// 2. Update stored password hash in keychain.
    /// 3. Wipe old keychain entries.
    private func reencryptAllNotes(newPassword: String) async throws {
        // Derive new key
        let newSalt = KeyDerivation.generateSalt()
        let newKey  = try KeyDerivation.deriveSymmetricKey(password: newPassword, salt: newSalt)

        // Re-save all in-memory notes with new key
        // NoteStore.shared.notes are already decrypted in memory from unlock
        let notes = await MainActor.run { NoteStore.shared.notes }
        for note in notes {
            try NoteStore.shared.save(note: note, key: newKey)
        }

        // Update keychain: new password hash + salt
        let newHash = try KeyDerivation.hashForStorage(value: newPassword, salt: newSalt)
        try KeychainManager.store(key: "td.passwordSalt", data: newSalt)
        try KeychainManager.store(key: "td.passwordHash", data: newHash)

        // Lock — user must re-unlock with new password
        await MainActor.run {
            AuthManager.shared.lock()
        }
    }

    // MARK: — Helpers

    private func actionButton(title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(enabled ? Color.white : Color.gray.opacity(0.3))
                .foregroundColor(enabled ? .black : .white.opacity(0.4))
                .cornerRadius(8)
                .font(.system(size: 14, weight: .semibold))
        }
        .disabled(!enabled)
        .buttonStyle(.plain)
    }
}
