import SwiftUI

/// Root tab view for the app.
/// Settings lives behind the gear in the Library toolbar, and quick
/// price checks behind the barcode button on the Prices tab, keeping
/// the tab bar to four items.
struct ContentView: View {
    enum AppTab: String {
        case library, prices, watchlist, stats
    }

    @State private var selection: AppTab = ContentView.initialTab

    var body: some View {
        TabView(selection: $selection) {
            LibraryView()
                .tabItem {
                    Label("Library", systemImage: "books.vertical")
                }
                .tag(AppTab.library)

            PriceSummaryView()
                .tabItem {
                    Label("Prices", systemImage: "tag")
                }
                .tag(AppTab.prices)

            WatchlistView()
                .tabItem {
                    Label("Watchlist", systemImage: "eye")
                }
                .tag(AppTab.watchlist)

            ReadingStatsView()
                .tabItem {
                    Label("Stats", systemImage: "chart.bar")
                }
                .tag(AppTab.stats)
        }
    }

    /// Launch with `-startTab prices|watchlist|stats` in DEBUG builds to open
    /// on a specific tab (used for simulator screenshots).
    private static var initialTab: AppTab {
        #if DEBUG
        if let raw = UserDefaults.standard.string(forKey: "startTab"),
           let tab = AppTab(rawValue: raw) {
            return tab
        }
        #endif
        return .library
    }
}
