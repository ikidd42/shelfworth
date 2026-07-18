import SwiftUI
import SwiftData
import TipKit

@main
struct LibraryApp: App {
    let container: ModelContainer

    init() {
        try? Tips.configure()
        Theme.applyAppearances()

        do {
            container = try ModelContainer(
                for: Book.self, PriceHistoryEntry.self, WatchedBook.self, WatchedPriceEntry.self
            )
        } catch {
            fatalError("Failed to create SwiftData container: \(error)")
        }

        #if DEBUG
        if UserDefaults.standard.bool(forKey: "seedSampleData") {
            SampleData.seedIfNeeded(into: container.mainContext)
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(Theme.green)
        }
        .modelContainer(container)
    }
}
