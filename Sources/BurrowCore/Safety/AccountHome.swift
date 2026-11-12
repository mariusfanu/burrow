import Darwin

/// The account's home directory, independent of the environment supplied to Mole.
func accountHomeDirectory() -> String? {
    let suggestedSize = sysconf(_SC_GETPW_R_SIZE_MAX)
    var buffer = [CChar](repeating: 0, count: suggestedSize > 0 ? suggestedSize : 16_384)
    return buffer.withUnsafeMutableBufferPointer { storage in
        var entry = passwd()
        var result: UnsafeMutablePointer<passwd>?
        guard getpwuid_r(getuid(), &entry, storage.baseAddress, storage.count, &result) == 0,
              result != nil, let directory = entry.pw_dir else { return nil }
        return String(cString: directory)
    }
}
