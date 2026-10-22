@testable import AppBundle
import XCTest

/// Unit tests for the Hyprland dwindle split-parity helper. The helper is deliberately free of
/// AppKit and actor state, so the rules are asserted without a window server or a fake AX tree.
final class DwindleFractionTest: XCTestCase {
    private func fraction(_ first: CGFloat, _ second: CGFloat) -> CGFloat {
        TilingContainer.dwindleFraction(firstWeight: first, secondWeight: second)
    }

    func testEqualWeightsSplitEvenly() {
        XCTAssertEqual(fraction(1, 1), 0.5, accuracy: 0.000_001)
    }

    func testUnequalWeightsSplitProportionally() {
        XCTAssertEqual(fraction(1, 3), 0.25, accuracy: 0.000_001)
        XCTAssertEqual(fraction(3, 1), 0.75, accuracy: 0.000_001)
    }

    func testRatioIsClampedSoNeitherSideCollapses() {
        XCTAssertEqual(fraction(1, 1000), 0.05, accuracy: 0.000_001)
        XCTAssertEqual(fraction(1000, 1), 0.95, accuracy: 0.000_001)
    }

    func testDegenerateWeightsFallBackToEvenSplit() {
        XCTAssertEqual(fraction(0, 0), 0.5, accuracy: 0.000_001)
        XCTAssertEqual(fraction(.nan, 1), 0.5, accuracy: 0.000_001)
        XCTAssertEqual(fraction(1, .infinity), 0.5, accuracy: 0.000_001)
    }

    /// `resize` moves weights in absolute units, so a two-child container overshoots through zero:
    /// `resize smart +10` turns the weights `1, 1` into `11, -9`. The negative sibling is floored at
    /// zero instead of resetting the split to 50/50, otherwise the resize would have no visible effect.
    func testNegativeWeightIsFlooredInsteadOfRevertingToEvenSplit() {
        XCTAssertEqual(fraction(-1, 2), 0.05, accuracy: 0.000_001)
        XCTAssertEqual(fraction(11, -9), 0.95, accuracy: 0.000_001)
    }
}
