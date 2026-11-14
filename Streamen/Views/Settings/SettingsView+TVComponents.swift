//
//  SettingsView+TVComponents.swift
//  Streamen
//
//  The tvOS About and Help & Feedback detail panes, the Sports pane, the
//  panes' drill-in and focus hand-off targets, and the SwiftUI previews,
//  split out of SettingsView to keep that file within the project's size
//  limit. The categories themselves are `SettingsCategory`.
//

import SwiftData
import SwiftUI

#if os(tvOS)

    extension SettingsView {
        /// The drilled-in options pane for a single engine.
        func tvEngineOptionsDetail(for engine: PlayerEngineKind) -> some View {
            VStack(alignment: .leading, spacing: 28) {
                Text("\(engine.displayName) Options")
                    .font(.system(size: 34, weight: .bold))
                    .padding(.horizontal, TVSettingsMetrics.rowHPadding)

                switch engine {
                case .vlcKit:
                    VLCEngineSettingsTVDetail()
                case .ksPlayer:
                    KSEngineSettingsTVDetail()
                case .streamenEngine:
                    StreamenEngineSettingsTVDetail()
                case .avPlayer:
                    Text("AVPlayer has no configurable options.")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, TVSettingsMetrics.rowHPadding)
                case .aetherEngine:
                    AetherEngineSettingsTVDetail()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        /// Advances Off → Infuse → VLC → Off; the cycle-row pattern used for
        /// every multi-choice option on tvOS.
        func nextExternalPlayerRaw(after raw: String) -> String {
            let cycle = [""] + ExternalPlayer.allCases.map(\.rawValue)
            guard let index = cycle.firstIndex(of: raw) else { return "" }
            return cycle[(index + 1) % cycle.count]
        }

        /// Advances the hand-off scope through both → VOD → live TV → both.
        func nextExternalPlayerScopeRaw(after raw: String) -> String {
            let cycle = ExternalPlayerScope.allCases.map(\.rawValue)
            guard let index = cycle.firstIndex(of: raw) else { return ExternalPlayerScope.default.rawValue }
            return cycle[(index + 1) % cycle.count]
        }

        /// Advances the surf mapping between the two `LiveSurfMode` cases.
        func nextLiveSurfModeRaw(after raw: String) -> String {
            let cycle = LiveSurfMode.allCases.map(\.rawValue)
            guard let index = cycle.firstIndex(of: raw) else { return LiveSurfMode.default.rawValue }
            return cycle[(index + 1) % cycle.count]
        }

        var tvAboutDetail: some View {
            VStack(alignment: .leading, spacing: 36) {
                VStack(alignment: .leading, spacing: 8) {
                    TVSettingsSectionLabel("About")

                    HStack(spacing: 18) {
                        Image(systemName: "play.tv.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.tint)
                            .frame(width: 60, height: 60)
                            .background(.tint.opacity(0.12), in: .rect(cornerRadius: 14, style: .continuous))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Streamen")
                                .font(.system(size: 26, weight: .semibold))
                            Text("Version \(SupportInfo.appVersion)")
                                .font(.system(size: 20))
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, TVSettingsMetrics.rowHPadding)
                    .padding(.vertical, 8)
                }

                // Apple TV can't open a link, so TMDB's credit is text only.
                VStack(alignment: .leading, spacing: 12) {
                    TVSettingsSectionLabel("Metadata")
                    TVSettingsValueRow("The Movie Database (TMDB)", value: SupportInfo.tmdbDisplay)
                    TMDBAttribution.logo(height: 22)
                        .padding(.horizontal, TVSettingsMetrics.rowHPadding)
                    Text(TMDBAttribution.notice)
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, TVSettingsMetrics.rowHPadding)
                }
            }
        }

        var tvHelpDetail: some View {
            VStack(alignment: .leading, spacing: 36) {
                tvSupportSection

                TVDiagnosticsSection()
            }
        }
    }

    // MARK: - Sports pane

    /// The Sports settings pane: a Manage Teams shortcut, Hide Scores, a manual
    /// refresh bound to `SportsSyncService`, and the last-refresh stamp. The tab
    /// switch lives in Library. Standalone
    /// so it owns its own presentation and refresh state.
    struct TVSportsSettingsPane: View {
        @AppStorage(SportsSyncService.hideScoresKey) private var hideScores = false
        @State private var sync = SportsSyncService.shared
        @State private var showManageTeams = false
        #if DEBUG
            @Query private var playlists: [Playlist]
            @State private var demoOn = SportsScreenshotDemo.isEnabled
            @State private var demoMessage: String?
        #endif

        var body: some View {
            VStack(alignment: .leading, spacing: 36) {
                VStack(alignment: .leading, spacing: 8) {
                    TVSettingsSectionLabel("Sports")

                    Button {
                        showManageTeams = true
                    } label: {
                        HStack(spacing: 16) {
                            Label("Manage Teams", systemImage: "person.2.badge.plus")
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.forward")
                                .font(.system(size: 22, weight: .semibold))
                        }
                    }
                    .buttonStyle(TVSettingsRowButtonStyle())

                    TVOptionToggleRow(title: "Hide Scores", isOn: $hideScores)
                }

                VStack(alignment: .leading, spacing: 8) {
                    TVSettingsSectionLabel("Sports Data")

                    Button {
                        sync.syncNow()
                    } label: {
                        HStack(spacing: 16) {
                            Text(sync.isSyncing ? "Refreshing…" : "Refresh Now")
                            Spacer(minLength: 0)
                            if sync.isSyncing {
                                ProgressView()
                            }
                        }
                    }
                    .buttonStyle(TVSettingsRowButtonStyle())
                    .disabled(sync.isSyncing)

                    TVSettingsValueRow("Last Refreshed", value: lastRefreshText)
                }

                Text("Follow leagues and teams to build your Sports Hub. Fixtures, live scores and standings come from ESPN, and each game links to a channel in your playlists.")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, TVSettingsMetrics.rowHPadding)

                #if DEBUG
                    screenshotDemoRow
                #endif
            }
            .fullScreenCover(isPresented: $showManageTeams) {
                TVManageTeamsPane()
            }
        }

        #if DEBUG
            /// Debug builds only, so its text stays out of the string catalog.
            private var screenshotDemoRow: some View {
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        let on = !demoOn
                        Task {
                            demoMessage = await SportsScreenshotDemo.setEnabled(on, playlists: playlists)
                            demoOn = SportsScreenshotDemo.isEnabled
                        }
                    } label: {
                        HStack(spacing: 16) {
                            Text(verbatim: "Screenshot Demo")
                            Spacer(minLength: 0)
                            Text(verbatim: demoOn ? "On" : "Off")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(TVSettingsRowButtonStyle())

                    Text(verbatim: demoMessage
                        ?? "Debug: shows made-up leagues and teams from the Screenshot Demo server instead of ESPN.")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, TVSettingsMetrics.rowHPadding)
                }
            }
        #endif

        /// A relative "last refreshed" line, or "Never" before the first refresh.
        private var lastRefreshText: String {
            if let last = sync.lastRefresh {
                return last.formatted(.relative(presentation: .named))
            }
            return String(localized: "Never")
        }
    }
#endif

#Preview("Empty") {
    SettingsView()
}

#Preview("With Playlists") {
    SettingsView()
        .modelContainer(for: Playlist.self, inMemory: true) { result in
            if case let .success(container) = result {
                let playlist = Playlist(name: "My IPTV", serverURL: "http://example.com:8080", username: "user", password: "pass")
                let backup = Playlist(name: "Backup", serverURL: "http://backup.com:8080", username: "user2", password: "pass2")
                container.mainContext.insert(playlist)
                container.mainContext.insert(backup)
            }
        }
}
