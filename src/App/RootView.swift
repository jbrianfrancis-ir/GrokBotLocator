import SwiftUI

/// Placeholder root screen. Plain, unstyled `Text` — `dsFont` does not exist
/// until 01-03 adds DSTypography; 01-12 replaces this with SettingsView.
struct RootView: View {
    var body: some View {
        NavigationStack {
            Text("GrokBotLocator")
                .padding(DSMetrics.screenMargin)
                .navigationTitle("GrokBotLocator")
        }
    }
}
