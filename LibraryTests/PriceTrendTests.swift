import Testing
@testable import Library

struct PriceTrendTests {

    @Test func detectsPriceDrop() {
        #expect(PriceTrend.recentChange(in: [28.49, 24.99]) == -3.5)
    }

    @Test func detectsPriceRise() {
        #expect(PriceTrend.recentChange(in: [11.25, 12.50]) == 1.25)
    }

    @Test func skipsRepeatedChecksAtSamePrice() {
        // Refreshes append entries even when the price didn't move;
        // the delta should reach back to the last different price.
        #expect(PriceTrend.recentChange(in: [28.49, 24.99, 24.99, 24.99]) == -3.5)
    }

    @Test func returnsNilWhenPriceNeverChanged() {
        #expect(PriceTrend.recentChange(in: [24.99, 24.99, 24.99]) == nil)
    }

    @Test func returnsNilForSingleCheck() {
        #expect(PriceTrend.recentChange(in: [24.99]) == nil)
    }

    @Test func returnsNilForEmptyHistory() {
        #expect(PriceTrend.recentChange(in: []) == nil)
    }
}
