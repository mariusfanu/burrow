import Foundation

extension JSONDecoder {
    /// A decoder for the CLI's snake_case JSON.
    static func forCLI() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}
