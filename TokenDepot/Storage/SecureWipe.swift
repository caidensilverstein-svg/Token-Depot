import Foundation

enum WipeError: Error {
    case fileNotFound
    case wipeFailed
}

/// Multi-pass secure file wipe.
/// Overwrites file content before unlinking so data is not recoverable.
/// Pass order: 0x00, 0xFF, 0x00, random — then unlink.
struct SecureWipe {

    static let passes: [WipePattern] = [
        .fixed(0x00),
        .fixed(0xFF),
        .fixed(0x00),
        .random
    ]

    enum WipePattern {
        case fixed(UInt8)
        case random
    }

    /// Securely wipe a single file.
    static func wipeFile(at url: URL) throws {
        let fm = FileManager.default

        guard fm.fileExists(atPath: url.path) else {
            throw WipeError.fileNotFound
        }

        // Get file size
        let attributes = try fm.attributesOfItem(atPath: url.path)
        guard let size = attributes[.size] as? Int, size > 0 else {
            try fm.removeItem(at: url)
            return
        }

        // Open file handle for writing
        guard let handle = FileHandle(forWritingAtPath: url.path) else {
            throw WipeError.wipeFailed
        }

        defer {
            handle.closeFile()
        }

        // Execute each pass
        for pattern in passes {
            handle.seek(toFileOffset: 0)
            let chunk = makeChunk(size: size, pattern: pattern)
            handle.write(chunk)
            handle.synchronizeFile()  // Force flush to disk each pass
        }

        handle.closeFile()

        // Now unlink the file
        try fm.removeItem(at: url)
    }

    /// Wipe all files in a directory, then remove the directory.
    static func wipeDirectory(at url: URL) throws {
        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )

        for fileURL in contents {
            try wipeFile(at: fileURL)
        }

        try fm.removeItem(at: url)
    }

    // MARK: — Private

    private static func makeChunk(size: Int, pattern: WipePattern) -> Data {
        switch pattern {
        case .fixed(let byte):
            return Data(repeating: byte, count: size)
        case .random:
            var data = Data(count: size)
            data.withUnsafeMutableBytes { ptr in
                guard let base = ptr.baseAddress else { return }
                SecRandomCopyBytes(kSecRandomDefault, size, base)
            }
            return data
        }
    }
}
