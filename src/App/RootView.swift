import SwiftUI

/// The app's root: a `NavigationStack` opening on `PingHomeView`, with `SettingsView` one tap
/// away behind `SettingsRoute` and the system Back button returning from it.
///
/// It carries NO `navigationTitle`, and neither screen puts a title in a bar. Each screen's
/// on-screen `.dsFont(.screenTitle)` heading -- "Send a ping" in PingHomeView's scrolling
/// content, "Settings" in SettingsView's -- is that screen's only title; giving a bar the same
/// string renders it twice, one above the other. PingHomeView's own chrome bar is text-free for
/// a second reason it documents itself: text over a translucent surface with content scrolling
/// beneath it has no fixed background to measure DESIGN.md's 7:1 contrast floor against, and a
/// screen title at AX5 is wider than the bar in portrait.
///
/// `.navigationBarTitleDisplayMode(.inline)` now sits on the pushed `SettingsView` rather than
/// on the stack's root: PingHomeView hides its navigation bar outright, so on the root the
/// modifier would have nothing to act on, while SettingsView still shows a system bar to carry
/// its Back button and `.inline` is what keeps that bar compact above its own heading.
struct RootView: View {
    let pingModel: PingModel
    let settingsModel: SettingsModel

    var body: some View {
        NavigationStack {
            PingHomeView(model: pingModel)
                .navigationDestination(for: SettingsRoute.self) { _ in
                    SettingsView(model: settingsModel)
                        .navigationBarTitleDisplayMode(.inline)
                }
        }
    }
}
