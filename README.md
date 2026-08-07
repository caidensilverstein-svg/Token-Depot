# TokenDepot

Encrypted floating sticky notes app for macOS. Built for storing secrets, tokens, and credentials securely.

## Security Architecture

- **Encryption**: ChaCha20-Poly1305 (AEAD) — authenticated encryption, tamper detection built in
- **Key Derivation**: PBKDF2-SHA256 (600k iterations) — upgrade path to Argon2id via libargon2
- **Nonces**: 96-bit random via `SecRandomCopyBytes`, fresh every save — never reused
- **Storage**: `~/Library/Application Support/TokenDepot/notes/` — file perms `600`
- **Memory**: Session key zeroed on lock via `memset_s`, never written to disk
- **Keychain**: Password hashes, salts stored in macOS Keychain (`WhenUnlockedThisDeviceOnly`)
- **Privacy**: `.privacySensitive()` blocks screenshots of note content

## Auth

- **Master password** → unlock + derive session key
- **Panic password** → instant multi-pass wipe (0x00 → 0xFF → 0x00 → random) before unlink
- **Rate limiting**: 2 free attempts, then 30s → 2min → 8min → 30min (capped)
- **Recovery**: TouchID/Password + 32-char CSPRNG token (hash stored, never raw token)

## Setup (Xcode)

1. Open `TokenDepot.xcodeproj`
2. Set your Team in Signing & Capabilities
3. Enable: **App Sandbox** off (or configure entitlements for file access)
4. Add entitlements:
   - `com.apple.security.personal-information.location` — NO
   - `NSFaceIDUsageDescription` — "Verify identity for account recovery"
5. Link `LocalAuthentication.framework`
6. Build & Run — app lives in menubar only

## Upgrade Path: Argon2id

The current KDF is PBKDF2-SHA256 (600k iterations). To upgrade to true Argon2id:

1. Add `libargon2` via Swift Package Manager or brew
2. Replace `CCKeyDerivationPBKDF` in `KeyDerivation.swift` with `argon2id_hash_raw()`
3. Parameters: `t_cost=3`, `m_cost=65536`, `parallelism=4`
