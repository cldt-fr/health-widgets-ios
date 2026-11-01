import SwiftUI

extension View {
    /// DEBUG: `-scrollTo <id>` scrolls to the view tagged with that id on launch, to
    /// capture any part of a screen from the command line (and for App Store shots).
    func debugScrollTarget(_ proxy: ScrollViewProxy) -> some View {
        #if DEBUG
        onAppear {
            guard let target = UserDefaults.standard.string(forKey: "scrollTo") else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                proxy.scrollTo(target, anchor: .top)
            }
        }
        #else
        self
        #endif
    }
}
