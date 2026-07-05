import SwiftUI

/// Small capsule showing recent price movement, e.g. "↓ $3.50".
/// This is a buyer's view, so a falling price is good news (green)
/// and a rising price is bad news (red).
struct PriceDeltaBadge: View {
    let change: Double

    private var isDrop: Bool { change < 0 }

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: isDrop ? "arrow.down" : "arrow.up")
                .font(.system(size: 8, weight: .bold))
            Text(abs(change).formattedAsPrice())
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(isDrop ? .green : .red)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background((isDrop ? Color.green : Color.red).opacity(0.12))
        .clipShape(Capsule())
        .accessibilityLabel("Price \(isDrop ? "dropped" : "rose") \(abs(change).formattedAsPrice())")
    }
}
