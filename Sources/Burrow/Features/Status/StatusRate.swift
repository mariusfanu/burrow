func bytesPerSecond(_ megabytesPerSecond: Double) -> Int64? {
    Int64(exactly: (megabytesPerSecond * 1_048_576).rounded(.towardZero))
}
