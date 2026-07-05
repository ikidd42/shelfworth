import SwiftUI

/// Availability-gated wrappers for the iOS 18 zoom navigation transition,
/// so call sites stay clean while the app still deploys to iOS 17.
extension View {

    /// Marks this view as the source a zoom transition grows out of.
    @ViewBuilder
    func zoomTransitionSource(id: some Hashable, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            self.matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    /// Applies the zoom transition to a navigation destination.
    @ViewBuilder
    func zoomTransitionDestination(id: some Hashable, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            self.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            self
        }
    }
}
