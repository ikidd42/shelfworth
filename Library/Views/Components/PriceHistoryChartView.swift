import SwiftUI
import Charts

/// Shows a line chart of eBay price history for a book
struct PriceHistoryChartView: View {
    let entries: [PriceHistoryEntry]

    private var sortedEntries: [PriceHistoryEntry] {
        entries.sorted { $0.fetchedAt < $1.fetchedAt }
    }

    private var minPrice: Double {
        entries.map(\.price).min() ?? 0
    }

    private var maxPrice: Double {
        entries.map(\.price).max() ?? 0
    }

    private var avgPrice: Double {
        guard !entries.isEmpty else { return 0 }
        return entries.map(\.price).reduce(0, +) / Double(entries.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if sortedEntries.count >= 2 {
                chart
            } else if sortedEntries.count == 1 {
                singleDataPoint
            } else {
                Text("No price history yet")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
            }

            if sortedEntries.count >= 2 {
                statsRow
            }
        }
    }

    private var chart: some View {
        Chart {
            ForEach(sortedEntries, id: \.fetchedAt) { entry in
                LineMark(
                    x: .value("Date", entry.fetchedAt),
                    y: .value("Price", entry.price)
                )
                .foregroundStyle(Theme.gain)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.catmullRom)

                AreaMark(
                    x: .value("Date", entry.fetchedAt),
                    y: .value("Price", entry.price)
                )
                .foregroundStyle(Theme.gain.opacity(0.12))
                .interpolationMethod(.catmullRom)

                PointMark(
                    x: .value("Date", entry.fetchedAt),
                    y: .value("Price", entry.price)
                )
                .foregroundStyle(Theme.gain)
                .symbolSize(24)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(Theme.rule)
                AxisValueLabel {
                    if let price = value.as(Double.self) {
                        Text(formatPrice(price))
                            .font(.caption2)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .frame(height: 160)
    }

    private var singleDataPoint: some View {
        HStack {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .foregroundStyle(Theme.inkSecondary)
            Text("First price recorded: \(formatPrice(sortedEntries[0].price))")
                .font(.caption)
                .foregroundStyle(Theme.inkSecondary)
            Text("on \(sortedEntries[0].fetchedAt.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption)
                .foregroundStyle(Theme.inkTertiary)
        }
    }

    private var statsRow: some View {
        HStack(spacing: 8) {
            statPill(label: "Low", value: formatPrice(minPrice), color: Theme.gain)
            statPill(label: "Avg", value: formatPrice(avgPrice), color: Theme.brass)
            statPill(label: "High", value: formatPrice(maxPrice), color: Theme.loss)
            Spacer()
            Text("\(sortedEntries.count) checks")
                .font(.caption2)
                .foregroundStyle(Theme.inkTertiary)
        }
    }

    private func statPill(label: String, value: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .foregroundStyle(color)
            Text(value)
                .foregroundStyle(Theme.ink)
        }
        .font(.caption2.weight(.medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .clipShape(Capsule())
    }

    private func formatPrice(_ price: Double) -> String {
        price.formattedAsPrice()
    }
}
