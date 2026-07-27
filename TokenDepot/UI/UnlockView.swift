import SwiftUI

struct UnlockView: View {

    @StateObject private var auth = AuthManager.shared
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isUnlocking = false
    @State private var lockCountdown = 0
    @State private var showRecovery = false

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            // Dark background
            Color(red: 0.08, green: 0.08, blue: 0.10)
                .ignoresSafeArea()

            VStack(spacing: 28) {
                // Icon
                Image(systemName: "lock.doc.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.white.opacity(0.9))

                // Title
                VStack(spacing: 4) {
                    Text("TokenDepot")
                        .font(.system(size: 22, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                    Text("Enter your master password")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.5))
                }

                // Password field
                VStack(spacing: 12) {
                    SecureField("Master password", text: $password)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(8)
                        .onSubmit { attemptUnlock() }
                        .disabled(isLocked)

                    // Error message
                    if let error = errorMessage {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundColor(.red.opacity(0.9))
                            .multilineTextAlignment(.center)
                    }

                    // Unlock button
                    Button(action: attemptUnlock) {
                        HStack {
                            if isUnlocking {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .tint(.black)
                            }
                            Text(isLocked ? "Locked (\(lockCountdown)s)" : "Unlock")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(isLocked ? Color.gray.opacity(0.4) : Color.white)
                        .foregroundColor(isLocked ? .white.opacity(0.5) : .black)
                        .cornerRadius(8)
                    }
                    .disabled(isLocked || isUnlocking || password.isEmpty)
                    .buttonStyle(.plain)
                }

                // Recovery link
                Button("Forgot password? Recover access") {
                    showRecovery = true
                }
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.35))
                .buttonStyle(.plain)
            }
            .padding(40)
            .frame(width: 340)
        }
        .onReceive(timer) { _ in
            if auth.isRateLimited {
                lockCountdown = auth.rateLimitSecondsRemaining
            } else {
                lockCountdown = 0
            }
        }
        .sheet(isPresented: $showRecovery) {
            RecoveryView()
        }
    }

    private var isLocked: Bool {
        auth.isRateLimited
    }

    private func attemptUnlock() {
        guard !password.isEmpty, !isLocked else { return }
        isUnlocking = true
        errorMessage = nil

        let pw = password
        password = ""

        Task {
            do {
                try AuthManager.shared.unlock(password: pw)
                await MainActor.run {
                    isUnlocking = false
                    // AuthManager.isUnlocked triggers AppDelegate to show notes
                }
            } catch AuthError.rateLimited(let seconds) {
                await MainActor.run {
                    isUnlocking = false
                    lockCountdown = seconds
                    errorMessage = "Too many attempts. Wait \(seconds)s."
                }
            } catch AuthError.panicTriggered {
                await MainActor.run {
                    isUnlocking = false
                    errorMessage = "All notes have been permanently deleted."
                }
            } catch {
                await MainActor.run {
                    isUnlocking = false
                    let attempts = AuthManager.shared.failedAttempts
                    if attempts <= 2 {
                        errorMessage = "Wrong password. \(2 - attempts + 1) free attempt(s) remaining."
                    } else {
                        errorMessage = "Wrong password."
                    }
                }
            }
        }
    }
}
