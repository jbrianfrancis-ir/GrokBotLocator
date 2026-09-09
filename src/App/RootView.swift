import SwiftUI

/// Placeholder root screen. 01-12 replaces this with SettingsView.
struct RootView: View {
    var body: some View {
        NavigationStack {
            Text("GrokBotLocator")
                .dsFont(.body)
                .padding(DSMetrics.screenMargin)
                .navigationTitle("GrokBotLocator")
        }
    }
}
