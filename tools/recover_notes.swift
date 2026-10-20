#!/usr/bin/env swift
// Recover notes orphaned by a password reset (issue #2).
//
// Notes saved before the reset are encrypted with PBKDF2(oldPassword, oldSalt). The reset replaced the
// salt in the Keychain, so the app can no longer derive that key. If you still know the old password and
// have the old salt + hash (e.g. from the sync relay's secrets.json), this re-encrypts those notes under
// the CURRENT password's key so the app can open them. Run it with TokenDepot quit, then launch a build
// containing the vault-key migration and unlock once.
//
// Usage: swift tools/recover_notes.swift --old-salt <base64> --old-hash <base64> [--notes <dir>]
//        swift tools/recover_notes.swift --selftest
// Passwords are read from the terminal (hidden) and never written anywhere.

import Foundation
import CryptoKit
import CommonCrypto
import Security

let service = "com.silversteincapital.tokendepot"

func fail(_ m: String) -> Never { FileHandle.standardError.write(Data((m + "\n").utf8)); exit(1) }

func pbkdf2(_ password: String, _ salt: Data) -> Data {
    let pw = Array(password.utf8)
    var out = [UInt8](repeating: 0, count: 32)
    let rc = salt.withUnsafeBytes { s in
        CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pw.map { Int8(bitPattern: $0) }, pw.count,
                             s.bindMemory(to: UInt8.self).baseAddress, salt.count,
                             CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), 600_000, &out, 32)
    }
    guard rc == kCCSuccess else { fail("key derivation failed") }
    return Data(out)
}

func storedHash(of key: Data) -> Data { Data(SHA256.hash(data: key)) }

func keychain(_ account: String) -> Data {
    let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                            kSecAttrService as String: service, kSecAttrAccount as String: account,
                            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
    var r: AnyObject?
    guard SecItemCopyMatching(q as CFDictionary, &r) == errSecSuccess, let d = r as? Data else {
        fail("cannot read Keychain item \(account) (click Allow/Always Allow if prompted, then re-run)")
    }
    return d
}

func prompt(_ label: String) -> String {
    guard let p = getpass(label) else { fail("no input") }
    return String(cString: p)
}

/// Re-encrypt every note in `dir` that opens with `oldKey` but not `newKey`. Returns (recovered, alreadyOK, unreadable).
func recover(dir: URL, oldKey: Data, newKey: Data) -> (Int, Int, Int) {
    let ok = SymmetricKey(data: oldKey), nk = SymmetricKey(data: newKey)
    var rec = 0, fine = 0, bad = 0
    let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
    for f in files where f.pathExtension == "tdnote" {
        guard let raw = try? Data(contentsOf: f),
              var obj = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
              let b64 = obj["encryptedPayload"] as? String, let blob = Data(base64Encoded: b64),
              let box = try? ChaChaPoly.SealedBox(combined: blob) else { bad += 1; continue }
        if (try? ChaChaPoly.open(box, using: nk)) != nil { fine += 1; continue }
        guard let plain = try? ChaChaPoly.open(box, using: ok),
              let sealed = try? ChaChaPoly.seal(plain, using: nk) else { bad += 1; continue }
        obj["encryptedPayload"] = sealed.combined.base64EncodedString()
        guard let out = try? JSONSerialization.data(withJSONObject: obj) else { bad += 1; continue }
        do {
            try out.write(to: f, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: f.path)
            rec += 1
        } catch { bad += 1 }
    }
    return (rec, fine, bad)
}

func selftest() {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("td-selftest-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let oldK = Data((0..<32).map { _ in UInt8.random(in: 0...255) }), newK = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
    func write(_ name: String, _ text: String, _ k: Data) {
        let sealed = try! ChaChaPoly.seal(Data(text.utf8), using: SymmetricKey(data: k)).combined
        let obj: [String: Any] = ["id": name, "encryptedPayload": sealed.base64EncodedString(), "updatedAt": 782000000.5, "colorRaw": "yellow"]
        try! JSONSerialization.data(withJSONObject: obj).write(to: dir.appendingPathComponent("\(name).tdnote"))
    }
    write("old", "secret-old", oldK); write("new", "secret-new", newK); write("junk", "x", Data(repeating: 9, count: 32))
    let (r, f, b) = recover(dir: dir, oldKey: oldK, newKey: newK)
    let raw = try! Data(contentsOf: dir.appendingPathComponent("old.tdnote"))
    let obj = try! JSONSerialization.jsonObject(with: raw) as! [String: Any]
    let box = try! ChaChaPoly.SealedBox(combined: Data(base64Encoded: obj["encryptedPayload"] as! String)!)
    let text = String(data: try! ChaChaPoly.open(box, using: SymmetricKey(data: newK)), encoding: .utf8)
    guard (r, f, b) == (1, 1, 1), text == "secret-old", obj["colorRaw"] as? String == "yellow" else { fail("SELFTEST FAILED \(r) \(f) \(b) \(String(describing: text))") }
    print("selftest passed")
}

let args = CommandLine.arguments
if args.contains("--selftest") { selftest(); exit(0) }
func arg(_ n: String) -> String? { args.firstIndex(of: n).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }
guard let s = arg("--old-salt").flatMap({ Data(base64Encoded: $0) }), let h = arg("--old-hash").flatMap({ Data(base64Encoded: $0) }) else {
    fail("usage: recover_notes.swift --old-salt <base64> --old-hash <base64> [--notes <dir>]")
}
let notesDir = arg("--notes").map { URL(fileURLWithPath: $0) } ??
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("TokenDepot/notes")

let oldKey = pbkdf2(prompt("OLD password (before the reset): "), s)
guard storedHash(of: oldKey) == h else { fail("That is not the old password (hash mismatch). Nothing was changed.") }
let curSalt = keychain("td.passwordSalt"), curHash = keychain("td.passwordHash")
let newKey = pbkdf2(prompt("CURRENT password: "), curSalt)
guard storedHash(of: newKey) == curHash else { fail("That is not the current password. Nothing was changed.") }

let (rec, fine, bad) = recover(dir: notesDir, oldKey: oldKey, newKey: newKey)
print("recovered \(rec), already readable \(fine), still unreadable \(bad)")
