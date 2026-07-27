import Foundation

/// A byte buffer that zeroes its memory when deallocated.
/// Use this for keys, passwords, and any other sensitive data.
final class SecureBytes {
    private(set) var bytes: [UInt8]

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    init(count: Int) {
        self.bytes = [UInt8](repeating: 0, count: count)
    }

    deinit {
        wipe()
    }

    func wipe() {
        // Explicit memset — compiler cannot optimize this away via memset_s semantics
        bytes.withUnsafeMutableBytes { ptr in
            guard let base = ptr.baseAddress else { return }
            memset_s(base, ptr.count, 0, ptr.count)
        }
    }

    var count: Int { bytes.count }
}

/// Wipe a raw byte array in place.
func wipeBytes(_ bytes: inout [UInt8]) {
    bytes.withUnsafeMutableBytes { ptr in
        guard let base = ptr.baseAddress else { return }
        memset_s(base, ptr.count, 0, ptr.count)
    }
    bytes = []
}

/// Wipe a Data buffer in place.
func wipeData(_ data: inout Data) {
    data.withUnsafeMutableBytes { ptr in
        guard let base = ptr.baseAddress else { return }
        memset_s(base, ptr.count, 0, ptr.count)
    }
    data = Data()
}
