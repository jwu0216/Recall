import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Ask", systemImage: "sparkle.magnifyingglass")
                }

            LibraryView()
                .tabItem {
                    Label("Library", systemImage: "tray.full")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
    }
}
