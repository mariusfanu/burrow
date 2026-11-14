func bytesPerSecond(_ megabytesPerSecond: Double) -> Int64? {
    guard megabytesPerSecond.isFinite, megabytesPerSecond >= 0 else { return nil }
    return Int64(exactly: (megabytesPerSecond * 1_048_576).rounded(.towardZero))
}
