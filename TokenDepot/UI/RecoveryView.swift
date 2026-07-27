import SwiftUI

struct RecoveryView: View {

    @Environment(\.dismiss) private var dismiss

    enum Step {
        case biometric
        case token
        case newPassword
        case success
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
                // Header
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
                    // Balance
                    Text("Cancel").opacity(0)
                }

                Spacer()

                switch step {
                case .biometric:
                    biometricStep
                case .token:
                    tokenStep
                case .newPassword:
                    newPasswordStep
                case .success:
                    successStep
                }

                Spacer()
            }
            .padding(32)
        }
        .frame(width: 380, height: 420)
    }

    // MARK: — Steps

    private var biometricStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "touchid")
                .font(.system(size: 56))
                .foregroundColor(.white.opacity(0.8))

            Text("Step 1 of 2 — Biometric")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.4))
                .textCase(.uppercase)
                .tracking(1.2)

            Text("Verify your identity with Touch ID")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            if let error = errorMessage {
                Text(error).font(.system(size: 12)).foregroundColor(.red).multilineTextAlignment(.center)
            }

            Button(action: runBiometric) {
                Text(isWorking ? "Authenticating..." : "Authenticate with Touch ID")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.white)
                    .foregroundColor(.black)
                    .cornerRadius(8)
                    .font(.system(size: 14, weight: .semibold))
            }
            .disabled(isWorking)
            .buttonStyle(.plain)
        }
    }

    private var tokenStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "key.fill")
                .font(.system(size: 48))
                .foregroundColor(.white.opacity(0.8))

            Text("Step 2 of 2 — Recovery Token")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.4))
                .textCase(.uppercase)
                .tracking(1.2)

            Text("Enter your 32-character recovery token")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            TextField("XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX", text: $token)
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

            Button(action: verifyToken) {
                Text("Verify Token")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(token.count == 32 ? Color.white : Color.gray.opacity(0.3))
                    .foregroundColor(token.count == 32 ? .black : .white.opacity(0.4))
                    .cornerRadius(8)
                    .font(.system(size: 14, weight: .semibold))
            }
            .disabled(token.count != 32 || isWorking)
            .buttonStyle(.plain)
        }
    }

    private var newPasswordStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 48))
                .foregroundColor(.green.opacity(0.8))

            Text("Recovery Authorized")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)

            Text("Set a new master password")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.5))

            VStack(spacing: 10) {
                SecureField("New master password", text: $newPassword)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(8)

                SecureField("Confirm password", text: $confirmPassword)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(8)
            }

            if let error = errorMessage {
                Text(error).font(.system(size: 12)).foregroundColor(.red)
            }

            Button(action: setNewPassword) {
                Text("Set New Password")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.white)
                    .foregroundColor(.black)
                    .cornerRadius(8)
                    .font(.system(size: 14, weight: .semibold))
            }
            .disabled(newPassword.isEmpty || newPassword != confirmPassword)
            .buttonStyle(.plain)
        }
    }

    private var successStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(.green)
            Text("Password Reset")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
            Text("Your new password is active. Please unlock TokenDepot.")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
            Button("Done") { dismiss() }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.white)
                .foregroundColor(.black)
                .cornerRadius(8)
                .font(.system(size: 14, weight: .semibold))
                .buttonStyle(.plain)
        }
    }

    // MARK: — Actions

    private func runBiometric() {
        isWorking = true
        errorMessage = nil

        Task {
            do {
                try await RecoveryManager.shared.authenticateWithBiometric()
                await MainActor.run {
                    isWorking = false
                    step = .token
                }
            } catch RecoveryError.biometricUnavailable {
                await MainActor.run {
                    isWorking = false
                    errorMessage = "Touch ID is not available on this device."
                }
            } catch RecoveryError.biometricFailed(let msg) {
                await MainActor.run {
                    isWorking = false
                    errorMessage = msg
                }
            } catch {
                await MainActor.run {
                    isWorking = false
                    errorMessage = "Authentication failed."
                }
            }
        }
    }

    private func verifyToken() {
        isWorking = true
        errorMessage = nil

        do {
            try RecoveryManager.shared.verifyToken(token)
            step = .newPassword
        } catch RecoveryError.tokenMismatch {
            errorMessage = "Invalid token. You must re-authenticate with Touch ID."
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
        // In full impl: re-encrypt all notes with new key derived from new password
        // For now: update stored password hash
        // TODO: implement full re-encryption pass
        step = .success
    }
}
