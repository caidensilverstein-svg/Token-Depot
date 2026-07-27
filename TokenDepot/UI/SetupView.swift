import SwiftUI

struct SetupView: View {

    enum SetupStep {
        case passwords
        case recoveryToken(token: String)
        case done
    }

    @State private var step: SetupStep = .passwords
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var panicPassword = ""
    @State private var errorMessage: String?
    @State private var tokenCopied = false

    var body: some View {
        ZStack {
            Color(red: 0.08, green: 0.08, blue: 0.10).ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                VStack(spacing: 6) {
                    Image(systemName: "lock.doc.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.white.opacity(0.9))
                    Text("TokenDepot")
                        .font(.system(size: 20, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                    Text("Secure setup")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.4))
                }
                .padding(.top, 36)
                .padding(.bottom, 28)

                switch step {
                case .passwords:
                    passwordsStep
                case .recoveryToken(let token):
                    recoveryTokenStep(token: token)
                case .done:
                    doneStep
                }
            }
            .padding(.horizontal, 36)
        }
    }

    // MARK: — Step 1: Passwords

    private var passwordsStep: some View {
        VStack(spacing: 16) {
            sectionLabel("Master Password")
            SecureField("Choose a strong password", text: $password)
                .styledField()

            SecureField("Confirm password", text: $confirmPassword)
                .styledField()

            Spacer().frame(height: 8)

            sectionLabel("Panic Password")
            Text("If entered, instantly wipes all notes. Cannot be the same as your master password.")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.4))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            SecureField("Choose a panic password", text: $panicPassword)
                .styledField()

            if let error = errorMessage {
                Text(error).font(.system(size: 12)).foregroundColor(.red).multilineTextAlignment(.center)
            }

            Spacer().frame(height: 8)

            Button(action: setupPasswords) {
                Text("Continue")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(canContinue ? Color.white : Color.gray.opacity(0.3))
                    .foregroundColor(canContinue ? .black : .white.opacity(0.4))
                    .cornerRadius(8)
                    .font(.system(size: 14, weight: .semibold))
            }
            .disabled(!canContinue)
            .buttonStyle(.plain)

            Spacer()
        }
    }

    private var canContinue: Bool {
        !password.isEmpty &&
        password == confirmPassword &&
        !panicPassword.isEmpty &&
        panicPassword != password
    }

    // MARK: — Step 2: Recovery Token

    private func recoveryTokenStep(token: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "key.fill")
                .font(.system(size: 32))
                .foregroundColor(.yellow.opacity(0.9))

            Text("Save Your Recovery Token")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)

            Text("This token is shown exactly once. Store it somewhere safe — a password manager, printed paper, or offline backup. Without it, recovery is impossible.")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.55))
                .multilineTextAlignment(.center)

            // Token display
            Text(token)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.white)
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(Color.white.opacity(0.06))
                .cornerRadius(8)
                .textSelection(.enabled)

            Button(action: { copyToken(token) }) {
                Label(tokenCopied ? "Copied!" : "Copy Token", systemImage: tokenCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 13, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.1))
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)

            Spacer().frame(height: 8)

            Button(action: { step = .done }) {
                Text("I've Saved My Token — Continue")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.white)
                    .foregroundColor(.black)
                    .cornerRadius(8)
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }

    // MARK: — Step 3: Done

    private var doneStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundColor(.green)

            Text("TokenDepot is ready")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)

            Text("Your notes are now encrypted and secured. Unlock from the menubar anytime.")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.55))
                .multilineTextAlignment(.center)

            Button(action: finish) {
                Text("Open TokenDepot")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.white)
                    .foregroundColor(.black)
                    .cornerRadius(8)
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }

    // MARK: — Actions

    private func setupPasswords() {
        errorMessage = nil
        do {
            try AuthManager.shared.setup(password: password, panicPassword: panicPassword)
            let token = try RecoveryManager.shared.generateAndStoreToken()
            step = .recoveryToken(token: token)
        } catch {
            errorMessage = "Setup failed. Please try again."
        }
    }

    private func copyToken(_ token: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(token, forType: .string)
        tokenCopied = true
    }

    private func finish() {
        NotificationCenter.default.post(name: .showUnlockScreen, object: nil)
    }

    // MARK: — Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.white.opacity(0.4))
            .textCase(.uppercase)
            .tracking(1.0)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: — View modifiers

extension View {
    func styledField() -> some View {
        self
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .foregroundColor(.white)
            .padding(12)
            .background(Color.white.opacity(0.08))
            .cornerRadius(8)
    }
}
