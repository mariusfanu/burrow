import Foundation

/// The result of `mo analyze --json [path]`.
public struct AnalyzeResult: Decodable, Sendable, Equatable {
    public struct Entry: Decodable, Sendable, Equatable, Identifiable, Hashable {
        public var name: String
        public var path: String
        public var size: Int64
        public var isDir: Bool
        public var cleanable: Bool?
        public var id: String { path }
    }

    public var scanStatus: String?
    public var path: String
    public var overview: Bool?
    public var entries: [Entry]?
    public var totalSize: Int64?

    public var isPartial: Bool { scanStatus == "partial" }

    public static func decode(_ data: Data) throws -> AnalyzeResult {
        try JSONDecoder.forCLI().decode(AnalyzeResult.self, from: data)
    }
}
