import Foundation
import Testing
@testable import Burrow

@MainActor
struct PerformanceBoundsTests {
    @Test func lineOutputBufferCapsLinesAtMaximumLines() {
        let buffer = LineOutputBuffer()
        let count = LineOutputBuffer.maximumLines + 50
        let chunk = Data((0..<count).map { "line-\($0)\n" }.joined().utf8)
        buffer.append(chunk)
        let lines = buffer.finish()
        #expect(lines.count == LineOutputBuffer.maximumLines)
        #expect(lines.first == "line-50")
        #expect(lines.last == "line-\(count - 1)")
    }

    @Test func sparklineTraceStartIsBoundedWhenValuesAreEmpty() {
        let empty = Sparkline.traceStart(sampleCount: 0)
        #expect(empty == 1)
        #expect(empty >= 0 && empty <= 1)

        let one = Sparkline.traceStart(sampleCount: 1)
        #expect(one == 1)

        let full = Sparkline.traceStart(sampleCount: 45)
        #expect(full == 0)
    }

    @Test func countingBytesClampsNonFiniteAndNegativeInputs() {
        #expect(CountingBytes.clampedCount(.nan) == 0)
        #expect(CountingBytes.clampedCount(.infinity) == 0)
        #expect(CountingBytes.clampedCount(-.infinity) == 0)
        #expect(CountingBytes.clampedCount(-500) == 0)
        #expect(CountingBytes.clampedCount(42) == 42)
        #expect(CountingBytes.clampedCount(Double(Int64.max)) == Int64.max)
    }

    @Test func strataSceneMeaningfulStepClampsNonFiniteAndOutOfRangeInputs() {
        #expect(StrataScene.meaningfulStep(for: .nan) == 0)
        #expect(StrataScene.meaningfulStep(for: .infinity) == 0)
        #expect(StrataScene.meaningfulStep(for: -.infinity) == 0)
        #expect(StrataScene.meaningfulStep(for: -0.5) == 0)
        #expect(StrataScene.meaningfulStep(for: 1.5) == 500)
        #expect(StrataScene.meaningfulStep(for: 0.5) == 250)
    }

    @Test func externalVolumesFailClosedOnNilMetadataAndRejectRoot() {
        #expect(ExternalVolumes.isWritableExternalVolume(
            path: "/Volumes/USB", resolvedPath: "/Volumes/USB",
            isInternal: false, isReadOnly: false, isLocal: true
        ))
        #expect(!ExternalVolumes.isWritableExternalVolume(
            path: "/Volumes/USB", resolvedPath: "/Volumes/USB",
            isInternal: nil, isReadOnly: false, isLocal: true
        ))
        #expect(!ExternalVolumes.isWritableExternalVolume(
            path: "/Volumes/USB", resolvedPath: "/Volumes/USB",
            isInternal: false, isReadOnly: nil, isLocal: true
        ))
        #expect(!ExternalVolumes.isWritableExternalVolume(
            path: "/Volumes/USB", resolvedPath: "/Volumes/USB",
            isInternal: false, isReadOnly: false, isLocal: nil
        ))
        #expect(!ExternalVolumes.isWritableExternalVolume(
            path: "/Volumes/Macintosh HD", resolvedPath: "/",
            isInternal: false, isReadOnly: false, isLocal: true
        ))
        #expect(!ExternalVolumes.isWritableExternalVolume(
            path: "/Volumes/Share", resolvedPath: "/Volumes/Share",
            isInternal: false, isReadOnly: false, isLocal: false
        ))
        #expect(!ExternalVolumes.isWritableExternalVolume(
            path: "/Volumes/ReadOnly", resolvedPath: "/Volumes/ReadOnly",
            isInternal: false, isReadOnly: true, isLocal: true
        ))
        #expect(!ExternalVolumes.isWritableExternalVolume(
            path: "/Volumes/Internal", resolvedPath: "/Volumes/Internal",
            isInternal: true, isReadOnly: false, isLocal: true
        ))
    }
}
