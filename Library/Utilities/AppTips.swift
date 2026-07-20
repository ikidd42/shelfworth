import SwiftUI
import TipKit

/// Points out the share-extension flow, which nothing else in the UI surfaces.
struct ShareToWatchlistTip: Tip {
    var title: Text {
        Text("Track books straight from eBay")
    }

    var message: Text? {
        Text("Share any eBay listing to Shelfworth from Safari or the eBay app and it appears here with price tracking.")
    }

    var image: Image? {
        Image(systemName: "square.and.arrow.up")
    }
}
