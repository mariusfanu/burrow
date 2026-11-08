import Foundation
import Testing
@testable import BurrowCore

@Suite struct GPUStatisticsTests {
    private func snapshot(gpu: String) throws -> StatusSnapshot {
        try StatusSnapshot.decode(Data(#"{"gpu":\#(gpu)}"#.utf8))
    }

    @Test func readingTakesDeviceUtilization() {
        let reading = GPUReading(model: "M", performanceStatistics: ["Device Utilization %": 61, "Tiler Utilization %": 5])
        #expect(reading == GPUReading(model: "M", utilization: 61))
    }

    @Test(arguments: [
        [:],
        ["Device Utilization %": "61"],
        ["Device Utilization %": -1],
        ["Device Utilization %": 101],
    ] as [[String: any Sendable]])
    func readingRejectsUnusableStatistics(statistics: [String: any Sendable]) {
        #expect(GPUReading(model: "M", performanceStatistics: statistics) == nil)
    }

    /// A smoke test: `read()` only builds readings through the checked initializer above.
    @Test func readingLiveStatisticsDoesntCrash() {
        // A machine without a GPU that publishes statistics has no readings, which is also valid.
        #expect(GPUStatistics.read().allSatisfy { (0...100).contains($0.utilization) })
    }

    @Test func fillsMissingUsageFromTheMatchingModel() throws {
        let filled = try snapshot(gpu: #"[{"name":"A","usage":-1},{"name":"B","usage":-1}]"#)
            .fillingMissingGPUUsage { [GPUReading(model: "B", utilization: 40), GPUReading(model: "A", utilization: 7)] }
        #expect(filled.gpu?.map(\.usage) == [7, 40])
    }

    @Test func fillsWhenUsageIsAbsent() throws {
        let filled = try snapshot(gpu: #"[{"name":"A"}]"#)
            .fillingMissingGPUUsage { [GPUReading(model: "A", utilization: 7)] }
        #expect(filled.gpu?.first?.usage == 7)
    }

    @Test func aSingleGPUUsesASingleReadingWhoseModelIsUnknown() throws {
        let filled = try snapshot(gpu: #"[{"name":"A","usage":-1}]"#)
            .fillingMissingGPUUsage { [GPUReading(model: nil, utilization: 7)] }
        #expect(filled.gpu?.first?.usage == 7)
    }

    @Test func severalGPUsNeverGuessWhichReadingIsTheirs() throws {
        let filled = try snapshot(gpu: #"[{"name":"A","usage":-1},{"name":"B","usage":-1}]"#)
            .fillingMissingGPUUsage { [GPUReading(model: nil, utilization: 7), GPUReading(model: nil, utilization: 8)] }
        #expect(filled.gpu?.map(\.usage) == [-1, -1])
    }

    @Test func noReadingsLeavesUsageMissing() throws {
        let filled = try snapshot(gpu: #"[{"name":"A","usage":-1}]"#).fillingMissingGPUUsage { [] }
        #expect(filled.gpu?.first?.usage == -1)
    }

    @Test(arguments: [#"[{"name":"A","usage":12}]"#, #"[{"name":"A","usage":0}]"#, "[]", "null"])
    func aReportedFigureIsKeptWithoutReadingIOKit(gpu: String) throws {
        let original = try snapshot(gpu: gpu)
        var didRead = false
        let filled = original.fillingMissingGPUUsage {
            didRead = true
            return [GPUReading(model: "A", utilization: 99)]
        }
        #expect(filled == original)
        #expect(!didRead)
    }
}
