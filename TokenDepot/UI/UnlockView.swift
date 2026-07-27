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
            Color(red: 0.08, green: 0.08, blue: 0.10).ignoresSafeArea()

            VStack(spacing: 28) {
                Image(systemName: "lock.doc.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.white.opacity(0.9))

                VStack(spacing: 4) {
                    Text("TokenDepot")
                        .font(.system(size: 22, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                    Text("Enter your master password")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.5))
                }

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
                        .disabled(isLocked || isUnlocking)

                    if let error = errorMessage {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundColor(.red.opacity(0.9))
                            .multilineTextAlignment(.center)
                    }

                    Button(action: attemptUnlock) {
                        HStack {
                            if isUnlocking {
                                ProgressView().scaleEffect(0.7).tint(.black)
                            }
                            Text(isLocked ? "Locked (\(lockCountdown)s)" : isUnlocking ? "Unlocking..." : "Unlock")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(isLocked || isUnlocking ? Color.gray.opacity(0.4) : Color.white)
                        .foregroundColor(isLocked || isUnlocking ? .white.opacity(0.5) : .black)
                        .cornerRadius(8)
                    }
                    .disabled(isLocked || isUnlocking || password.isEmpty)
                    .buttonStyle(.plain)
                }

                Button("Forgot password? Recover access") { showRecovery = true }
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.35))
                    .buttonStyle(.plain)
            }
            .padding(40)
            .frame(width: 340)
        }
        .onReceive(timer) { _ in
            lockCountdown = auth.isRateLimited ? auth.rateLimitSecondsRemaining : 0
        }
        .sheet(isPresented: $showRecovery) { RecoveryView() }
    }

    private var isLocked: Bool { auth.isRateLimited }

    private func attemptUnlock() {
        guard !password.isEmpty, !isLocked, !isUnlocking else { return }
        isUnlocking = true
        errorMessage = nil

        let pw = password
        password = ""

        Task {
            do {
                // unlock() is now async — KDF runs off main thread, UI stays responsive
                try await AuthManager.shared.unlock(password: pw)
                await MainActor.run { isUnlocking = false }
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
                    errorMessage = attempts <= 2
                        ? "Wrong password. \(max(0, 2 - attempts + 1)) free attempt(s) remaining."
                        : "Wrong password."
                }
            }
        }
    }
}
