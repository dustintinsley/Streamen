import SwiftData
import SwiftUI

struct LibraryToolbarModifier: ViewModifier {
    let playlists: [Playlist]
    @Binding var selectedPlaylistID: String
    @Binding var categorySortRaw: String
    @Binding var contentSortRaw: String
    @Binding var showingSync: Bool
    @Binding var showingSettings: Bool
    @Environment(\.catalogScope) private var catalogScope
    /// The page Settings opens on, set by the switcher's Combined entry and
    /// cleared when Settings closes so the toolbar's own gear opens the root.
    @State private var settingsRoute: SettingsRoute?
    @State private var showPaywall = false
    @State private var paywallHighlight: PremiumFeature?

    @Environment(DeepLinkRouter.self) private var router: DeepLinkRouter?
    #if os(macOS)
        @Environment(\.openSettings) private var openSettings
    #endif
    /// A new identity for each opening, so Settings always starts on its
    /// first page, scrolled to the top, however it was left last time.
    @State private var settingsOpening = UUID()
    /// What the sync sheet about to open refreshes: the Sync menu's
    /// "Playlist Only" clears it; every other way in leaves it on.
    @State private var syncRefreshesGuide = true

    func body(content: Content) -> some View {
        content
            .toolbar {
                if playlists.offersPlaylistSwitch {
                    ToolbarItem(placement: .automatic) { playlistSwitcher }
                }

                StartupSyncToolbarItem(activePlaylistID: playlists.primaryMember(of: catalogScope)?.id, showingSync: $showingSync)

                ToolbarItem(placement: .automatic) {
                    SortMenu(categorySortRaw: $categorySortRaw, contentSortRaw: $contentSortRaw)
                }

                // One ToolbarItem each, deliberately not an HStack in a single
                // item: when the bar runs out of room it moves surplus items
                // into a "..." overflow menu, and an item whose content is a
                // stack of buttons has no menu representation — it was dropped
                // outright, leaving no way to reach Settings at all. Separate
                // items degrade into menu rows instead. The titles also give the
                // menu rows (and VoiceOver) real names rather than the symbols'
                // defaults.
                ToolbarItem(placement: .automatic) {
                    if catalogScope.isCombined {
                        LibrarySyncButton(playlists: playlists, scope: catalogScope, showingSync: $showingSync)
                    } else {
                        syncMenu
                    }
                }

                ToolbarItem(placement: .automatic) {
                    settingsButton
                }
            }
            // macOS has only the Settings window (`MacSettingsView`); the
            // list sheet is iOS's.
            #if !os(macOS)
            .sheet(
                isPresented: $showingSettings,
                // Settings is a sheet on this toolbar, invisible to the browse
                // root that raises the rating prompt and the root notices — so
                // it reports itself, the way the paywall and the players do.
                onDismiss: {
                    settingsRoute = nil
                    ScreenOccupancy.shared.noteBlockingSheetDismissed()
                },
                content: {
                    SettingsView(opening: settingsRoute)
                        .id(settingsOpening)
                        .onAppear { ScreenOccupancy.shared.noteBlockingSheetAppeared() }
                }
            )
            .onChange(of: showingSettings) { _, isShowing in
                if isShowing { settingsOpening = UUID() }
            }
            #endif
            .paywall(isPresented: $showPaywall, highlight: paywallHighlight)
            // The Sync sheet syncs one playlist; Combined queues every member
            // through `AutoSyncQueue` instead.
            .sheet(isPresented: $showingSync) {
                if let playlist = playlists.primaryMember(of: catalogScope) {
                    SyncProgressView(playlist: playlist, refreshesGuide: syncRefreshesGuide)
                }
            }
            // A pairing link's add-device sheet is presented from the browse
            // root, which can't present over these.
            .onChange(of: router?.cloudPairingRequest?.id) { _, request in
                guard request != nil else { return }
                showingSettings = false
                showingSync = false
            }
    }

    private var playlistSwitcher: some View {
        PlaylistSwitcher(
            playlists: playlists,
            selectedPlaylistID: $selectedPlaylistID,
            presentPaywall: { feature in
                paywallHighlight = feature
                showPaywall = true
            },
            openCombinedSettings: {
                #if os(macOS)
                    MacSettingsRouter.shared.pendingRoute = .combinedView
                    openSettings()
                #else
                    settingsRoute = .combinedView
                    showingSettings = true
                #endif
            }
        )
    }
}

/// Sync for the playlist on screen, or — while Combined is on screen — every
/// due member, queued one after another by `AutoSyncQueue` rather than in a
/// sheet here. Its own view so the queue's busy flag re-renders this button only.
private struct LibrarySyncButton: View {
    let playlists: [Playlist]
    let scope: CatalogScope
    @Binding var showingSync: Bool
    @Environment(AutoSyncQueue.self) private var autoSyncQueue: AutoSyncQueue?
    @Environment(\.modelContext) private var modelContext
    @AppStorage(SyncFrequency.storageKey) private var syncFrequencyRaw: String = SyncFrequency.defaultValue.rawValue

    private var syncsMembers: Bool {
        autoSyncQueue != nil && scope.isCombined
    }

    var body: some View {
        Button {
            if syncsMembers, let autoSyncQueue {
                autoSyncQueue.enqueueManualMembers(
                    scope: scope,
                    playlists: playlists,
                    frequency: SyncFrequency.resolve(syncFrequencyRaw),
                    context: modelContext
                )
            } else {
                showingSync = true
            }
        } label: {
            Label("Sync", systemImage: "arrow.triangle.2.circlepath")
        }
        .disabled(syncsMembers && autoSyncQueue?.isBusy == true)
    }
}

extension LibraryToolbarModifier {
    /// Sync: a click (or tap) syncs the playlist and then the guide, as it
    /// always has; a long press (on macOS, the menu arrow or a click-and-hold)
    /// offers each on its own.
    var syncMenu: some View {
        Menu {
            Button {
                startSync(refreshingGuide: true)
            } label: {
                Label("Playlist and TV Guide", systemImage: "arrow.triangle.2.circlepath")
            }
            Button {
                startSync(refreshingGuide: false)
            } label: {
                Label("Playlist Only", systemImage: "list.bullet")
            }
            Button {
                EPGSyncService.shared.syncNow()
            } label: {
                Label("TV Guide Only", systemImage: "calendar")
            }
            .disabled(EPGSyncService.shared.isSyncing)
        } label: {
            Label("Sync", systemImage: "arrow.triangle.2.circlepath")
        } primaryAction: {
            startSync(refreshingGuide: true)
        }
    }

    func startSync(refreshingGuide: Bool) {
        syncRefreshesGuide = refreshingGuide
        showingSync = true
    }

    /// The gear: the Settings window on macOS (`MacSettingsView`, as ⌘,
    /// opens it), the Settings sheet elsewhere.
    @ViewBuilder
    var settingsButton: some View {
        #if os(macOS)
            SettingsLink {
                Label("Settings", systemImage: "gear")
            }
        #else
            Button {
                showingSettings = true
            } label: {
                Label("Settings", systemImage: "gear")
            }
        #endif
    }
}

struct LibraryToolbarConfiguration {
    let playlists: [Playlist]
    @Binding var selectedPlaylistID: String
    @Binding var categorySortRaw: String
    @Binding var contentSortRaw: String
    @Binding var showingSync: Bool
    @Binding var showingSettings: Bool
}

extension View {
    func libraryToolbar(config: LibraryToolbarConfiguration) -> some View {
        #if os(tvOS)
            // tvOS surfaces sync/settings/sorting through the tab bar instead.
            return self
        #else
            return modifier(LibraryToolbarModifier(
                playlists: config.playlists,
                selectedPlaylistID: config.$selectedPlaylistID,
                categorySortRaw: config.$categorySortRaw,
                contentSortRaw: config.$contentSortRaw,
                showingSync: config.$showingSync,
                showingSettings: config.$showingSettings
            ))
        #endif
    }
}
