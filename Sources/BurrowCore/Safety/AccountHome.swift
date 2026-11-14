import Darwin

/// The account's home directory, independent of the environment supplied to Mole.
func accountHomeDirectory() -> String? {
    let suggestedSize = sysconf(_SC_GETPW_R_SIZE_MAX)
    var size = suggestedSize > 0 ? suggestedSize : 16_384
    let maxSize = 1_048_576
    while size <= maxSize {
        var buffer = [CChar](repeating: 0, count: size)
        var entry = passwd()
        var result: UnsafeMutablePointer<passwd>?
        let status = buffer.withUnsafeMutableBufferPointer { storage in
            getpwuid_r(getuid(), &entry, storage.baseAddress, storage.count, &result)
        }
        if status == ERANGE {
            size *= 2
            continue
        }
        guard status == 0, result != nil, let directory = entry.pw_dir else { return nil }
        return String(cString: directory)
    }
    return nil
}
