#if DEBUG
import Foundation
import SwiftData
import UIKit

/// Seeds a demo library when the app is launched with `-seedSampleData YES`
/// (Edit Scheme → Arguments, or `xcrun simctl launch ... -seedSampleData YES`).
/// Handy for simulator screenshots and quick manual testing — never ships:
/// the whole file is compiled out of Release builds.
@MainActor
enum SampleData {

    static func seedIfNeeded(into context: ModelContext) {
        let existing = (try? context.fetchCount(FetchDescriptor<Book>())) ?? 0
        guard existing == 0 else { return }

        let calendar = Calendar.current
        func daysAgo(_ days: Int) -> Date {
            calendar.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        }

        func history(_ prices: [(Double, Int)]) -> [PriceHistoryEntry] {
            prices.map { price, days in
                let entry = PriceHistoryEntry(price: price)
                entry.fetchedAt = daysAgo(days)
                return entry
            }
        }

        let dune = Book(
            title: "Dune", authors: "Frank Herbert",
            isbn13: "9780441172719", publisher: "Ace Books",
            publishedDate: "1965", pageCount: 412,
            categories: "Science Fiction", readingStatus: .read
        )
        dune.rating = 5
        dune.dateStartedReading = daysAgo(90)
        dune.dateFinishedReading = daysAgo(62)
        dune.ebayLowestPrice = 12.50
        dune.ebayPriceLastUpdated = daysAgo(1)
        dune.priceHistory = history([(14.00, 30), (14.00, 14), (12.50, 1)])

        let hobbit = Book(
            title: "The Hobbit", authors: "J.R.R. Tolkien",
            isbn13: "9780345339683", publisher: "Houghton Mifflin",
            publishedDate: "1937", pageCount: 310,
            categories: "Fantasy", readingStatus: .read
        )
        hobbit.rating = 4
        hobbit.dateStartedReading = daysAgo(45)
        hobbit.dateFinishedReading = daysAgo(30)
        hobbit.ebayLowestPrice = 24.99
        hobbit.ebayPriceLastUpdated = daysAgo(2)
        hobbit.priceHistory = history([(22.00, 40), (23.50, 20), (24.99, 2)])

        let orwell = Book(
            title: "1984", authors: "George Orwell",
            isbn13: "9780451524935", publisher: "Signet Classics",
            publishedDate: "1949", pageCount: 328,
            categories: "Dystopian Fiction", readingStatus: .reading
        )
        orwell.dateStartedReading = daysAgo(10)
        orwell.ebayLowestPrice = 6.75
        orwell.ebayPriceLastUpdated = daysAgo(3)
        orwell.priceHistory = history([(6.75, 3)])

        let hailMary = Book(
            title: "Project Hail Mary", authors: "Andy Weir",
            isbn13: "9780593135204", publisher: "Ballantine Books",
            publishedDate: "2021", pageCount: 476,
            categories: "Science Fiction", readingStatus: .wantToRead
        )

        let austen = Book(
            title: "Pride and Prejudice", authors: "Jane Austen",
            isbn13: "9780141439518", publisher: "Penguin Classics",
            publishedDate: "1813", pageCount: 432,
            categories: "Classics", readingStatus: .read
        )
        austen.rating = 5
        austen.coverImageData = syntheticCover()
        austen.dateStartedReading = daysAgo(200)
        austen.dateFinishedReading = daysAgo(170)

        let rothfuss = Book(
            title: "The Name of the Wind", authors: "Patrick Rothfuss",
            isbn13: "9780756404741", publisher: "DAW Books",
            publishedDate: "2007", pageCount: 662,
            categories: "Fantasy", readingStatus: .wantToRead
        )
        rothfuss.ebayLowestPrice = 24.99
        rothfuss.ebayPriceLastUpdated = daysAgo(1)
        rothfuss.priceHistory = history([(28.49, 21), (28.49, 10), (24.99, 1)])

        for book in [dune, hobbit, orwell, hailMary, austen, rothfuss] {
            context.insert(book)
        }

        let watchedRowling = WatchedBook(
            title: "Harry Potter and the Sorcerer's Stone",
            authors: "J.K. Rowling",
            isbn13: "9780590353427"
        )
        watchedRowling.ebayLowestPrice = 45.00
        watchedRowling.ebayPriceLastUpdated = daysAgo(1)
        watchedRowling.ebaySearchURL = "https://www.ebay.com/sch/i.html?_nkw=9780590353427"
        for (price, days) in [(52.00, 28), (49.50, 14), (45.00, 1)] {
            let entry = WatchedPriceEntry(price: price)
            entry.fetchedAt = daysAgo(days)
            watchedRowling.priceHistory.append(entry)
        }

        let watchedKing = WatchedBook(
            title: "The Stand", authors: "Stephen King",
            isbn13: "9780385121682"
        )
        watchedKing.ebayLowestPrice = 89.99
        watchedKing.ebayPriceLastUpdated = daysAgo(2)
        for (price, days) in [(84.00, 30), (89.99, 2)] {
            let entry = WatchedPriceEntry(price: price)
            entry.fetchedAt = daysAgo(days)
            watchedKing.priceHistory.append(entry)
        }

        context.insert(watchedRowling)
        context.insert(watchedKing)
    }

    /// A simple painted cover so demo data exercises the cover-art paths
    /// (thumbnailing, ink-matched endpapers) without bundling an image.
    private static func syntheticCover() -> Data? {
        let size = CGSize(width: 600, height: 900)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            UIColor(red: 0.13, green: 0.32, blue: 0.42, alpha: 1).setFill()   // deep teal
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.92, green: 0.86, blue: 0.72, alpha: 1).setFill()   // cream band
            ctx.fill(CGRect(x: 0, y: 330, width: 600, height: 240))
            UIColor(red: 0.76, green: 0.44, blue: 0.28, alpha: 1).setFill()   // terracotta sun
            ctx.cgContext.fillEllipse(in: CGRect(x: 210, y: 90, width: 180, height: 180))
        }
        return image.jpegData(compressionQuality: 0.85)
    }
}
#endif
