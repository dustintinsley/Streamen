//
//  MacSettingsView.swift
//  Streamen
//
//  The macOS Settings window (Streamen › Settings…, ⌘,): toolbar tabs, the
//  way Mac apps lay out their settings, in place of the iOS-style list sheet.
//  The tabs are the iPhone root list's groups, so both read the same; a tab
//  holding more than one category switches between them with a segmented
//  control. Every page is the same SwiftUI page iOS shows
//  (`SettingsCategoryDestination`), in its own navigation stack so drill-ins
//  keep working.
//

#if os(macOS)

    import SwiftData
    import SwiftUI

    /// The tabs follow the iPhone's root-list groups, so the two read the
    /// same: each tab is a group, its pages are the group's rows.
    enum MacSettingsTab: String, CaseIterable, Identifiable {
        case content, experience, playback, accountsSync, system, feedback, profiles, premium, about

        var id: String {
            rawValue
        }

        var title: LocalizedStringKey {
            switch self {
            case .content: "Content"
            case .experience: "Experience"
            case .playback: "Playback"
            case .accountsSync: "Accounts & Sync"
            case .system: "System"
            case .feedback: "Feedback"
            case .profiles: "Profiles"
            case .premium: "Streamen Pro"
            case .about: "About"
            }
        }

        var systemImage: String {
            switch self {
            case .content: "tv"
            case .experience: "sparkles.tv"
            case .playback: "play.circle"
            case .accountsSync: "arrow.trianglehead.2.clockwise.rotate.90.icloud"
            case .system: "gearshape"
            case .feedback: "questionmark.bubble"
            case .profiles: "person.crop.circle"
            case .premium: "crown"
            case .about: "info.circle"
            }
        }

        /// The categories this tab holds, in `SettingsCategory` order.
        /// Feedback and About hold none: they show the Help & Feedback and
        /// About sections.
        var categories: [SettingsCategory] {
            switch self {
            case .content: [.playlists, .epg, .library]
            case .experience: [.home, .liveTV, .sports, .appearance]
            case .playback: [.player, .downloads]
            case .accountsSync: [.iCloud, .connectedServices]
            case .system: [.storage, .developer]
            case .feedback, .about: []
            case .profiles: [.profiles]
            case .premium: [.premium]
            }
        }
    }

    /// The page the Settings window should open on, set by a surface outside
    /// it (the playlist switcher's Combined entry) just before it opens the
    /// window. The window is its own scene, so this hands the route across.
    @MainActor @Observable
    final class MacSettingsRouter {
        static let shared = MacSettingsRouter()
        var pendingRoute: SettingsRoute?
        private init() {}
    }

    struct MacSettingsView: View {
        @AppStorage("macSettings.selectedTab") private var selectedTab = MacSettingsTab.content
        @State private var router = MacSettingsRouter.shared
        @AppStorage(PlaylistSelectionStore.key) private var selectedPlaylistID: String = ""
        @Query private var playlists: [Playlist]
        @State private var premium = PremiumManager.shared

        var body: some View {
            TabView(selection: $selectedTab) {
                ForEach(MacSettingsTab.allCases) { tab in
                    MacSettingsTabContent(tab: tab)
                        .tabItem { Label(tab.title, systemImage: tab.systemImage) }
                        .tag(tab)
                }
            }
            .scenePadding(.minimum)
            .frame(width: 720, height: 600)
            // Its own scene, so it resolves the main window's scope itself:
            // the Library tab switches and other per-playlist pages read it.
            .catalogScope(playlists.scope(for: selectedPlaylistID, isPremium: premium.isPremium), playlists: playlists)
            .toggleStyle(TrailingSwitchToggleStyle())
            // Every route lives under Content › Playlists; that tab's content
            // drills in and clears the route.
            .onChange(of: router.pendingRoute, initial: true) { _, route in
                if route != nil { selectedTab = .content }
            }
        }
    }

    /// A switch at the row's trailing edge, as the iPhone's settings show it,
    /// in place of the Mac list's leading checkbox.
    struct TrailingSwitchToggleStyle: ToggleStyle {
        func makeBody(configuration: Configuration) -> some View {
            HStack {
                configuration.label
                    .accessibilityHidden(true)
                Spacer(minLength: 12)
                Toggle(isOn: configuration.$isOn) {
                    configuration.label
                }
                .toggleStyle(.switch)
                .labelsHidden()
            }
        }
    }

    /// One tab: its single page, or a segmented switcher over its pages.
    private struct MacSettingsTabContent: View {
        let tab: MacSettingsTab
        @State private var page: SettingsCategory?
        /// Pages a route pushed above the tab's page.
        @State private var path: [SettingsRoute] = []
        @State private var router = MacSettingsRouter.shared

        private var pages: [SettingsCategory] {
            let hasConnectedServices = TraktService.shared.isConfigured || SimklService.shared.isConfigured
                || MDBListService.shared.isConfigured
            let visible = Set(SettingsCategory.visible(hasConnectedServices: hasConnectedServices))
            return tab.categories.filter { visible.contains($0) }
        }

        var body: some View {
            if tab == .feedback {
                SettingsList {
                    HelpFeedbackSection()
                }
            } else if tab == .about {
                SettingsList {
                    AboutSection(showsLegalLink: false)
                    LegalLicensesSections()
                }
            } else {
                VStack(spacing: 0) {
                    if pages.count > 1 {
                        Picker("Section", selection: Binding(get: { page ?? pages.first }, set: { page = $0; path = [] })) {
                            ForEach(pages) { category in
                                Text(category.title).tag(Optional(category))
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                        .padding(.bottom, 12)
                    }
                    if let current = page ?? pages.first {
                        NavigationStack(path: $path) {
                            SettingsCategoryDestination(category: current)
                                .environment(\.isSettingsRootPage, true)
                                .navigationDestination(for: SettingsRoute.self) { SettingsRouteDestination(route: $0) }
                        }
                        // A fresh stack per page, so switching pages never
                        // lands inside another page's drill-in.
                        .id(current)
                    }
                }
                .onChange(of: router.pendingRoute, initial: true) { _, route in
                    guard tab == .content, let route else { return }
                    router.pendingRoute = nil
                    page = .playlists
                    // Playlists is the tab's page itself, so only what lies
                    // above it is pushed: Back from Combined View lands on it.
                    path = Array(route.stack.drop { $0 == .playlists })
                }
            }
        }
    }

#endif
