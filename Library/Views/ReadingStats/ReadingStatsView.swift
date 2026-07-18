import SwiftUI
import SwiftData
import Charts

/// Reading analytics dashboard showing stats and charts
struct ReadingStatsView: View {
    @Query private var books: [Book]

    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())

    private var yearsWithActivity: [Int] {
        let years = Set(books.compactMap { book -> Int? in
            if let date = book.dateFinishedReading {
                return Calendar.current.component(.year, from: date)
            }
            if let date = book.dateStartedReading {
                return Calendar.current.component(.year, from: date)
            }
            return nil
        })
        let currentYear = Calendar.current.component(.year, from: Date())
        return (years.union([currentYear])).sorted().reversed()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Year picker
                    if yearsWithActivity.count > 1 {
                        Picker("Year", selection: $selectedYear) {
                            ForEach(yearsWithActivity, id: \.self) { year in
                                Text(String(year)).tag(year)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    // Summary cards
                    summaryCards

                    // Monthly chart
                    monthlyChart

                    // Reading speed stats
                    readingSpeedSection

                    // All-time stats
                    allTimeSection

                    Spacer(minLength: 24)
                }
                .padding()
            }
            .background(Theme.canvas.ignoresSafeArea())
            .navigationTitle("Reading Stats")
        }
    }

    // MARK: - Summary Cards

    private var summaryCards: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 12) {
            statCard(
                title: "Read",
                value: "\(booksReadThisYear)",
                subtitle: "finished this year",
                icon: "checkmark.circle.fill",
                color: Theme.gain
            )

            statCard(
                title: "Reading",
                value: "\(currentlyReading)",
                subtitle: "in progress",
                icon: "book.fill",
                color: Theme.green
            )

            statCard(
                title: "Want to Read",
                value: "\(wantToRead)",
                subtitle: "in backlog",
                icon: "bookmark.fill",
                color: Theme.brass
            )

            statCard(
                title: "Library",
                value: "\(books.count)",
                subtitle: "volumes total",
                icon: "books.vertical.fill",
                color: Theme.inkSecondary
            )
        }
    }

    private func statCard(title: String, value: String, subtitle: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color)
                    .frame(width: 30, height: 30)
                    .background(color.opacity(0.12))
                    .clipShape(Circle())
                Spacer()
            }

            Text(value)
                .font(Theme.display(32))
                .foregroundStyle(Theme.ink)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: - Monthly Chart

    private var monthlyChart: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionEyebrow(text: "Finished by month")
                Spacer()
                if booksReadThisYear > 0 {
                    Text(String(selectedYear))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.inkTertiary)
                }
            }

            if booksReadThisYear > 0 {
                Chart {
                    let bestMonthCount = monthlyData.map(\.count).max() ?? 0
                    ForEach(monthlyData, id: \.month) { item in
                        BarMark(
                            x: .value("Month", item.label),
                            y: .value("Books", item.count)
                        )
                        .foregroundStyle(
                            bestMonthCount > 1 && item.count == bestMonthCount
                            ? Theme.brass.gradient
                            : Theme.green.gradient
                        )
                        .cornerRadius(4)
                    }
                }
                .chartYAxis {
                    AxisMarks(preset: .aligned) { _ in
                        AxisGridLine().foregroundStyle(Theme.rule)
                        AxisValueLabel()
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisValueLabel()
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
                .frame(height: 200)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "books.vertical")
                        .font(.title2)
                        .foregroundStyle(Theme.inkTertiary)
                    Text("No books finished in \(String(selectedYear)) yet")
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
            }
        }
        .cardStyle()
    }

    // MARK: - Reading Speed

    private var readingSpeedSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionEyebrow(text: "Reading pace")
                .padding(.bottom, 10)

            if let avgDays = averageReadingDays {
                readingSpeedRow(label: "Average reading time", value: formatDays(avgDays))
                rowSeparator
            }
            if let fastest = fastestRead {
                readingSpeedRow(label: "Fastest read", value: "\(fastest.title) (\(formatDays(readingDays(for: fastest) ?? 0)))")
                rowSeparator
            }
            if let longest = longestRead {
                readingSpeedRow(label: "Longest read", value: "\(longest.title) (\(formatDays(readingDays(for: longest) ?? 0)))")
            }

            if averageReadingDays == nil {
                Text("Mark books as “Reading” then “Read” to track your pace.")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .padding(.vertical, 8)
            }
        }
        .cardStyle()
    }

    private func readingSpeedRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.vertical, 10)
    }

    // MARK: - All-Time

    private var allTimeSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionEyebrow(text: "All time")
                .padding(.bottom, 10)

            allTimeRow(label: "Total books read", value: "\(totalBooksRead)")
            rowSeparator
            allTimeRow(label: "Total pages read", value: totalPagesRead > 0 ? totalPagesRead.formatted() : "—")

            if let topMonth = mostProductiveMonth {
                rowSeparator
                allTimeRow(
                    label: "Best month",
                    value: "\(topMonth.label) (\(topMonth.count) book\(topMonth.count == 1 ? "" : "s"))"
                )
            }
        }
        .cardStyle()
    }

    private func allTimeRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.ink)
        }
        .padding(.vertical, 10)
    }

    private var rowSeparator: some View {
        Rectangle()
            .fill(Theme.rule)
            .frame(height: 1)
    }

    // MARK: - Data Calculations

    private var booksReadThisYear: Int {
        books.filter { book in
            guard let date = book.dateFinishedReading else { return false }
            return Calendar.current.component(.year, from: date) == selectedYear
        }.count
    }

    private var currentlyReading: Int {
        books.filter { $0.readingStatusEnum == .reading }.count
    }

    private var wantToRead: Int {
        books.filter { $0.readingStatusEnum == .wantToRead }.count
    }

    private var totalBooksRead: Int {
        books.filter { $0.readingStatusEnum == .read }.count
    }

    private var totalPagesRead: Int {
        books.filter { $0.readingStatusEnum == .read }
            .compactMap { $0.pageCount }
            .reduce(0, +)
    }

    struct MonthData {
        let month: Int
        let label: String
        let count: Int
    }

    private var monthlyData: [MonthData] {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        let calendar = Calendar.current

        let finishedThisYear = books.filter { book in
            guard let date = book.dateFinishedReading else { return false }
            return calendar.component(.year, from: date) == selectedYear
        }

        return (1...12).map { month in
            let count = finishedThisYear.filter { book in
                guard let date = book.dateFinishedReading else { return false }
                return calendar.component(.month, from: date) == month
            }.count

            var components = DateComponents()
            components.month = month
            let date = calendar.date(from: components) ?? Date()
            let label = formatter.string(from: date)

            return MonthData(month: month, label: label, count: count)
        }
    }

    private func readingDays(for book: Book) -> Int? {
        guard let start = book.dateStartedReading, let end = book.dateFinishedReading else { return nil }
        return max(1, Calendar.current.dateComponents([.day], from: start, to: end).day ?? 1)
    }

    private var booksWithReadingTime: [Book] {
        books.filter { readingDays(for: $0) != nil }
    }

    private var averageReadingDays: Int? {
        let times = booksWithReadingTime.compactMap { readingDays(for: $0) }
        guard !times.isEmpty else { return nil }
        return times.reduce(0, +) / times.count
    }

    private var fastestRead: Book? {
        booksWithReadingTime.min(by: { (readingDays(for: $0) ?? Int.max) < (readingDays(for: $1) ?? Int.max) })
    }

    private var longestRead: Book? {
        booksWithReadingTime.max(by: { (readingDays(for: $0) ?? 0) < (readingDays(for: $1) ?? 0) })
    }

    struct MonthLabel {
        let label: String
        let count: Int
    }

    private var mostProductiveMonth: MonthLabel? {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"

        var monthly: [String: Int] = [:]
        for book in books {
            guard let date = book.dateFinishedReading else { continue }
            let key = formatter.string(from: date)
            monthly[key, default: 0] += 1
        }

        guard let top = monthly.max(by: { $0.value < $1.value }) else { return nil }
        return MonthLabel(label: top.key, count: top.value)
    }

    private func formatDays(_ days: Int) -> String {
        if days == 1 { return "1 day" }
        return "\(days) days"
    }
}
