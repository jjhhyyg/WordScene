import SwiftUI

struct RootView: View {
    @State private var selectedSection: AppSection = .translate

    var body: some View {
        #if os(macOS)
        splitRoot(layout: .expanded)
            .environment(\.adaptiveLayout, .expanded)
            .frame(minWidth: 920, minHeight: 620)
        #else
        GeometryReader { proxy in
            let layout = AdaptiveLayout(availableWidth: proxy.size.width)

            Group {
                if layout.usesTabNavigation {
                    tabRoot
                } else {
                    splitRoot(layout: layout)
                }
            }
            .environment(\.adaptiveLayout, layout)
        }
        #endif
    }

    private func splitRoot(layout: AdaptiveLayout) -> some View {
        NavigationSplitView {
            List {
                ForEach(AppSection.navigationSections) { section in
                    Button {
                        selectedSection = section
                    } label: {
                        Label(section.title, systemImage: section.systemImage)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(selectedSection == section ? Color.accentColor.opacity(0.14) : Color.clear)
                    .accessibilityLabel(section.title)
                    .accessibilityIdentifier("navigation.\(section.rawValue)")
                }
            }
            .navigationTitle("词境")
            #if os(macOS)
            .frame(minWidth: 176)
            #else
            .navigationSplitViewColumnWidth(
                min: layout.sidebarMinWidth,
                ideal: layout.sidebarIdealWidth,
                max: layout.sidebarMaxWidth
            )
            #endif
        } detail: {
            NavigationStack {
                sectionView(selectedSection)
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    #if os(iOS)
    private var tabRoot: some View {
        TabView(selection: $selectedSection) {
            ForEach(AppSection.navigationSections) { section in
                NavigationStack {
                    sectionView(section)
                }
                .tabItem {
                    Label(section.title, systemImage: section.systemImage)
                }
                .tag(section)
                .accessibilityIdentifier("tab.\(section.rawValue)")
            }
        }
        .toolbarBackground(.visible, for: .tabBar)
    }
    #endif

    @ViewBuilder
    private func sectionView(_ section: AppSection) -> some View {
        switch section {
        case .translate:
            TranslationView()
        case .library:
            LibraryView()
        case .search:
            SearchView()
        case .settings:
            SettingsView()
        }
    }
}

#Preview("Root") {
    RootView()
}

#Preview("Root Compact") {
    RootView()
        .frame(width: 390, height: 844)
}

#Preview("Root Wide") {
    RootView()
        .frame(width: 1200, height: 800)
}
