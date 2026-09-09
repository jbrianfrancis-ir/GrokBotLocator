import SwiftUI

/// The app's root: a `NavigationStack` wrapping `SettingsView`, nothing else -- ping,
/// location, and network are later phases. The `NavigationStack` alone is what gives the
/// screen its system chrome (translucent nav bar). It carries NO title: SettingsView's
/// on-screen `.dsFont(.screenTitle)` heading is the screen's only title, and giving the
/// nav bar the same string just renders "Settings" twice, one above the other.
struct RootView: View {
    let settingsModel: SettingsModel

    var body: some View {
        NavigationStack {
            SettingsView(model: settingsModel)
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}
