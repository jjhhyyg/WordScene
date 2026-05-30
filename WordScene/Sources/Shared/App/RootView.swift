import SwiftUI

#if os(iOS)
import UIKit
#endif

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
            .keyboardDismissControls()
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
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .listRowBackground(selectedSection == section ? Color.accentColor.opacity(0.14) : Color.clear)
                    .accessibilityLabel(section.title)
                    .accessibilityIdentifier("navigation.\(section.rawValue)")
                }
            }
            .navigationTitle(String(localized: "译笺", comment: "Root sidebar navigation title."))
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
        case .history:
            HistoryView()
        case .settings:
            SettingsView()
        }
    }
}

#if os(iOS)
extension View {
    func keyboardDismissControls() -> some View {
        background(KeyboardOutsideTapDismissalInstaller().allowsHitTesting(false))
    }
}

private struct KeyboardOutsideTapDismissalInstaller: UIViewRepresentable {
    func makeUIView(context: Context) -> KeyboardOutsideTapDismissalView {
        KeyboardOutsideTapDismissalView()
    }

    func updateUIView(_ uiView: KeyboardOutsideTapDismissalView, context: Context) {}
}

private final class KeyboardOutsideTapDismissalView: UIView, UIGestureRecognizerDelegate {
    private weak var installedWindow: UIWindow?
    private lazy var tapRecognizer: UITapGestureRecognizer = {
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = self
        return recognizer
    }()

    override func didMoveToWindow() {
        super.didMoveToWindow()

        if installedWindow !== window {
            installedWindow?.removeGestureRecognizer(tapRecognizer)
            installedWindow = window
            window?.addGestureRecognizer(tapRecognizer)
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard var touchedView = touch.view else {
            return true
        }

        while true {
            if touchedView is UITextField || touchedView is UITextView {
                return false
            }

            let className = NSStringFromClass(type(of: touchedView))
            if className.contains("UIKeyboard") {
                return false
            }

            guard let superview = touchedView.superview else {
                return true
            }
            touchedView = superview
        }
    }

    @objc private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}
#else
extension View {
    func keyboardDismissControls() -> some View {
        self
    }
}
#endif

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
