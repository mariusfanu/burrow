import SwiftUI
import Testing
@testable import Burrow

struct StatusRateAndSparkShapeTests {
    @Test func bytesPerSecondRejectsNegativeAndNonFiniteValues() {
        #expect(bytesPerSecond(0) == 0)
        #expect(bytesPerSecond(1.5) == 1_572_864)
        #expect(bytesPerSecond(-0.1) == nil)
        #expect(bytesPerSecond(-10) == nil)
        #expect(bytesPerSecond(.nan) == nil)
        #expect(bytesPerSecond(.infinity) == nil)
        #expect(bytesPerSecond(-.infinity) == nil)
        #expect(bytesPerSecond(1e20) == nil)
    }

    @Test func sparkShapeGuardsCapacityMaximumAndNonFiniteInputs() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 40)

        #expect(SparkShape(values: [1, 2], capacity: 0, maximum: 10, scroll: 0, closesArea: false).path(in: rect).isEmpty)
        #expect(SparkShape(values: [1, 2], capacity: 1, maximum: 10, scroll: 0, closesArea: false).path(in: rect).isEmpty)
        #expect(SparkShape(values: [1, 2], capacity: 4, maximum: 0, scroll: 0, closesArea: false).path(in: rect).isEmpty)
        #expect(SparkShape(values: [1, 2], capacity: 4, maximum: -5, scroll: 0, closesArea: false).path(in: rect).isEmpty)
        #expect(SparkShape(values: [1, 2], capacity: 4, maximum: .nan, scroll: 0, closesArea: false).path(in: rect).isEmpty)
        #expect(SparkShape(values: [1, 2], capacity: 4, maximum: 10, scroll: .nan, closesArea: false).path(in: rect).isEmpty)

        let nanValuePath = SparkShape(values: [2, .nan, 8], capacity: 4, maximum: 10, scroll: 0, closesArea: false).path(in: rect)
        #expect(!nanValuePath.isEmpty)
        #expect(nanValuePath.boundingRect.origin.x.isFinite)
        #expect(nanValuePath.boundingRect.origin.y.isFinite)
        #expect(nanValuePath.boundingRect.size.width.isFinite)
        #expect(nanValuePath.boundingRect.size.height.isFinite)

        let areaPath = SparkShape(values: [2, 6, 8], capacity: 4, maximum: 10, scroll: 0, closesArea: true).path(in: rect)
        #expect(!areaPath.isEmpty)
        #expect(areaPath.boundingRect.maxY == rect.maxY)
    }

    @MainActor @Test func statusDashboardColumnsStepDownAtBreakpoints() {
        #expect(StatusDashboard.columns(forWidth: 800) == 3)
        #expect(StatusDashboard.columns(forWidth: 700) == 3)
        #expect(StatusDashboard.columns(forWidth: 699) == 2)
        #expect(StatusDashboard.columns(forWidth: 460) == 2)
        #expect(StatusDashboard.columns(forWidth: 459) == 1)
        #expect(StatusDashboard.columns(forWidth: 200) == 1)
    }
}
