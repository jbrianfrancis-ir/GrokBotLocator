import SwiftUI

/// The app's root: a `NavigationStack` wrapping `SettingsView`, nothing else -- ping,
/// location, and network are later phases. The `NavigationStack` alone is what gives the
/// screen its system chrome (translucent nav bar); `.navigationBarTitleDisplayMode(.inline)`
/// keeps the nav bar's own title small so it doesn't duplicate SettingsView's on-screen
/// `.dsFont(.screenTitle)` heading.
struct RootView: View {
    let settingsModel: SettingsModel

    var body: some View {
        NavigationStack {
            SettingsView(model: settingsModel)
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}
