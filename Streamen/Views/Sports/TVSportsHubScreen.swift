//
//  TVSportsHubScreen.swift
//  Streamen
//
//  The tvOS Sports Hub. The phone hub's segmented control and toolbar do not
//  read on a remote, so this is a purpose-built 10-foot screen: one scrolling
//  page whose header is a row of league chips, a compact
//  Yesterday / Today / Upcoming switch and an icon-only Manage Teams button,
//  then each group's `TVFixtureScoreboardCard`s in one column as on the Mac,
//  one focus section per group, over the sport's field (`SportsBackdrop`). The header scrolls with the page — a pinned bar over an unclipped
//  scroll view had the cards sliding underneath it. It shares the hub's data
//  plumbing — `SportsStore` snapshots, `SportsFollowService` follows, off-main
//  `SportsChannelResolver` — and reuses `SportsHubView`'s static date/assembly
//  helpers so the two hubs stay in step.
//

#if os(tvOS)

    import SwiftData
    import SwiftUI

    /// Focus targets on the hub, so Menu (exit) from a card can return focus to
    /// the filter row rather than dropping to the tab bar mid-browse.
    private enum TVSportsFocus: Hashable {
        case scope(SportsHubScope)
        case segment(SportsHubSegment)
        case manage
        case card(String)
    }

    struct TVSportsHubScreen: View {
        @Environment(\.modelContext) private var modelContext
        @Environment(\.contentRestriction) private var restriction

        @State private var premium = PremiumManager.shared
        @State private var store = SportsStore.shared
        @State private var follows = SportsFollowService.shared
        @State private var epg = EPGSyncService.shared

        @State private var scope: SportsHubScope = .myTeams
        @State private var segment: SportsHubSegment = .today
        @State private var resolved: [String: [ResolvedChannel]] = [:]
        @State private var selectedFixture: SportsFixture?
        @State private var showManageTeams = false
        @State private var showPaywall = false
        @State private var playingMedia: PlayableMedia?
        /// Playback queued behind the dismissing detail cover; see `watch`.
        @State private var pendingMedia: PlayableMedia?
        /// The card to reopen when the player closes; see `reopenGame`.
        @State private var watchReturn: SportsWatchReturn?
        /// The channel the reopened card lands focus on.
        @State private var returnChannelID: String?

        @FocusState private var focus: TVSportsFocus?

        var body: some View {
            Group {
                if premium.isPremium {
                    hub
                } else {
                    lockedState
                }
            }
            .sheet(isPresented: $showManageTeams) { TVManageTeamsPane() }
            .fullScreenCover(item: $selectedFixture, onDismiss: presentPendingMedia) { fixture in
                TVGameDetailSheet(
                    fixture: fixture,
                    resolved: resolved[fixture.id] ?? [],
                    onWatch: watch,
                    focusChannelID: returnChannelID
                )
            }
            .fullScreenCover(item: $playingMedia, onDismiss: reopenGame) { media in
                FullScreenPlayerView(media: media)
            }
            .paywall(isPresented: $showPaywall, highlight: .sportsHub)
            .onAppear(perform: onAppear)
            .onDisappear { SportsSyncService.shared.endLivePolling() }
        }

        // MARK: - Hub

        @ViewBuilder
        private var hub: some View {
            if follows.follows.isEmpty {
                onboardingState
            } else {
                content
            }
        }

        /// The whole hub is one scrolling page so the header can never sit over
        /// the cards: title-style scope menu on the left, the day switch and the
        /// Manage Teams button on the right, then the rails.
        private var content: some View {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 36) {
                        header
                            .id(Self.topAnchor)
                        if groups.isEmpty {
                            noGamesState
                        } else {
                            ForEach(groups) { group in
                                section(for: group)
                            }
                        }
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                }
                .scrollClipDisabled()
                // A new league or day starts from its first game.
                .onChange(of: scope) { proxy.scrollTo(Self.topAnchor, anchor: .top) }
                .onChange(of: segment) { proxy.scrollTo(Self.topAnchor, anchor: .top) }
            }
            .background(alignment: .top) { backdrop }
            .defaultFocus($focus, firstCardFocus)
            .onExitCommand { returnFocusToFilter() }
            .task(id: resolveKey) { await runResolve() }
        }

        // MARK: - Header

        /// The league chips across the top, the day switch and the Manage
        /// Teams button to their right, as on the phone hub. The controls stay
        /// quiet at rest — only the active chip and day carry a fill — so the
        /// row reads as a heading, not a toolbar. Status hints sit under it.
        private var header: some View {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 24) {
                    scopeChips
                    Spacer(minLength: 24)
                    segmentedControl
                    manageButton
                }
                if epg.isSyncing {
                    hintRow("Updating guide…", icon: "arrow.triangle.2.circlepath")
                }
                if store.refreshError {
                    hintRow("Scores unavailable — showing your saved data.", icon: "wifi.slash")
                }
            }
            .padding(.horizontal, 60)
            .focusSection()
        }

        // MARK: - Filter controls

        private var segmentedControl: some View {
            HStack(spacing: 4) {
                ForEach(SportsHubSegment.allCases) { segment in
                    segmentButton(segment)
                }
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.08))
            )
        }

        private func segmentButton(_ value: SportsHubSegment) -> some View {
            let isActive = segment == value
            let isItemFocused = focus == .segment(value)
            return Button {
                segment = value
            } label: {
                TVSportsPillLabel(
                    title: value.title,
                    font: .callout.weight(.semibold),
                    isFocused: isItemFocused,
                    isActive: isActive,
                    horizontalPadding: 22,
                    verticalPadding: 12,
                    cornerRadius: 12
                )
            }
            .buttonStyle(TVCardButtonStyle(focusScale: 1.03))
            .focused($focus, equals: .segment(value))
            .animation(.easeOut(duration: 0.18), value: isItemFocused)
        }

        /// My Teams, then each followed league, as chips that scroll sideways
        /// when there are more than fit. The strip clips, so chips past its end
        /// can't draw over the day switch beside it; the inset padding (undone
        /// outside) leaves room for a focused chip's lift and shadow.
        private var scopeChips: some View {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    scopeChip(.myTeams, title: String(localized: "My Teams"))
                    ForEach(followedLeagues) { league in
                        scopeChip(.league(league.id), title: league.name)
                    }
                }
                .padding(.leading, Self.chipInset)
                // The last chip scrolls clear of the fade.
                .padding(.trailing, Self.chipFade)
                .padding(.vertical, Self.chipInset + 8)
            }
            .padding(.horizontal, -Self.chipInset)
            .padding(.vertical, -Self.chipInset)
            // Fades the strip out where it's cut off, so the clip reads as
            // "more to the side" rather than a sliced chip.
            .mask {
                HStack(spacing: 0) {
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: Self.chipFade)
                }
            }
        }

        /// Room around the chips for `TVCardButtonStyle`'s focus scale and shadow.
        private static let chipInset: CGFloat = 20
        /// Width of the fade at the strip's trailing edge.
        private static let chipFade: CGFloat = 72

        private func scopeChip(_ value: SportsHubScope, title: String) -> some View {
            let isItemFocused = focus == .scope(value)
            return Button {
                scope = value
            } label: {
                TVScopeChipLabel(title: title, isFocused: isItemFocused, isActive: scope == value)
            }
            .buttonStyle(TVCardButtonStyle(focusScale: 1.04))
            .focused($focus, equals: .scope(value))
            .animation(.easeOut(duration: 0.18), value: isItemFocused)
        }

        private var manageButton: some View {
            Button {
                showManageTeams = true
            } label: {
                TVSportsCircleChrome {
                    Image(systemName: "person.2.badge.plus")
                        .font(.system(size: 26, weight: .semibold))
                }
            }
            .buttonStyle(TVCardButtonStyle(focusScale: 1.06))
            .focused($focus, equals: .manage)
            .accessibilityLabel(Text("Manage Teams"))
        }

        // MARK: - Sections

        /// As on the Mac: a bold heading with the competition's crest, then the
        /// group's scoreboard cards one under another. The column is held to a
        /// readable width in the middle of the screen, so a card's two sides sit
        /// close to its score rather than at the far edges of the TV.
        private func section(for group: SportsFixtureGroup) -> some View {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    if let logoURL = group.logoURL {
                        CachedAsyncImage(url: logoURL, maxPixelSize: 72) { phase in
                            if case let .success(image) = phase {
                                image.resizable().scaledToFit()
                            } else {
                                Color.clear
                            }
                        }
                        .frame(width: 36, height: 36)
                        .accessibilityHidden(true)
                    }
                    Text(verbatim: group.title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }

                ForEach(group.fixtures) { fixture in
                    TVFixtureScoreboardCard(
                        fixture: fixture,
                        resolved: resolved[fixture.id] ?? [],
                        isFollowed: isFollowed,
                        showsLeagueMark: !group.isSingleLeague,
                        showsDate: !group.isGroupedByDay,
                        onSelect: { selectedFixture = fixture },
                        onWatch: watch
                    )
                    .focused($focus, equals: .card(fixture.id))
                }
            }
            .frame(maxWidth: Self.columnWidth)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 60)
            .focusSection()
        }

        /// The card column's width: about two thirds of a 1920pt screen.
        private static let columnWidth: CGFloat = 1300

        // MARK: - States

        private var onboardingState: some View {
            fullScreenState(
                title: "Follow Your Teams",
                message: "Add leagues and teams to see fixtures, live scores and standings, with one tap to the channel carrying the game."
            ) {
                Button {
                    showManageTeams = true
                } label: {
                    Label("Manage Teams", systemImage: "person.2.badge.plus")
                        .font(.title3.weight(.semibold))
                        .padding(.horizontal, 44)
                        .padding(.vertical, 20)
                }
                .buttonStyle(TVCardButtonStyle(focusScale: 1.05))
            }
        }

        private var lockedState: some View {
            fullScreenState(
                title: PremiumFeature.sportsHub.title,
                message: PremiumFeature.sportsHub.subtitle
            ) {
                Button {
                    showPaywall = true
                } label: {
                    Text("Unlock Sports Hub")
                        .font(.title3.weight(.semibold))
                        .padding(.horizontal, 44)
                        .padding(.vertical, 20)
                }
                .buttonStyle(TVCardButtonStyle(focusScale: 1.05))
            }
        }

        private var noGamesState: some View {
            VStack(spacing: 24) {
                Image(systemName: "sportscourt")
                    .font(.system(size: 64))
                    .foregroundStyle(.white.opacity(0.35))
                Text("No games")
                    .font(.title.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity, minHeight: 560)
        }

        private func fullScreenState(
            title: LocalizedStringResource,
            message: LocalizedStringResource,
            @ViewBuilder action: () -> some View
        ) -> some View {
            VStack(spacing: 24) {
                Image(systemName: "sportscourt")
                    .font(.system(size: 80))
                    .foregroundStyle(.white.opacity(0.5))
                Text(title)
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.white)
                Text(message)
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 820)
                action()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }

        /// The club colours over the sport's field, as behind the phone hub.
        private var backdrop: some View {
            let leagueId: String? = if case let .league(id) = scope { id } else { nil }
            return SportsBackdrop(
                colors: SportsBackdrop.colors(for: visibleFixtures, preferring: isFollowed),
                sport: SportsBackdrop.sport(for: visibleFixtures, leagueId: leagueId),
                height: 900
            )
            .animation(.easeInOut(duration: 0.4), value: scope)
        }

        private static let topAnchor = "tv-sports-hub-top"

        private func hintRow(_ text: LocalizedStringKey, icon: String) -> some View {
            Label(text, systemImage: icon)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.55))
        }

        // MARK: - Focus

        private var firstCardFocus: TVSportsFocus? {
            groups.first?.fixtures.first.map { TVSportsFocus.card($0.id) }
        }

        private func returnFocusToFilter() {
            Task { @MainActor in focus = .segment(segment) }
        }

        // MARK: - Lifecycle

        private func onAppear() {
            store.loadCached(leagueIds: displayLeagueIds)
            SportsSyncService.shared.refreshIfStale()
            SportsSyncService.shared.beginLivePolling()
            Task { await EPGSyncService.shared.refreshIfMissingSubtitles() }
        }

        private var resolveKey: String {
            visibleFixtures.map(\.id).joined(separator: ",") + "|" + String(epg.isSyncing)
        }

        private func runResolve() async {
            let fixtures = visibleFixtures
            guard !fixtures.isEmpty else {
                resolved = [:]
                return
            }
            // The next day and a half first, so the top of a long list isn't
            // waiting on the guide for the rest of the week; the full pass then only
            // computes what the cache doesn't already hold.
            if let soon = SportsChannelResolver.nearTermSubset(of: fixtures, now: Date()) {
                let first = await SportsChannelResolver.resolve(
                    container: modelContext.container, fixtures: soon, now: Date(), restriction: restriction
                )
                guard !Task.isCancelled else { return }
                resolved = first
            }
            let result = await SportsChannelResolver.resolve(
                container: modelContext.container,
                fixtures: fixtures,
                now: Date(),
                restriction: restriction
            )
            // A resolve superseded by a newer `.task(id:)` pass must not overwrite it.
            guard !Task.isCancelled else { return }
            resolved = result
        }

        // MARK: - Playback

        private func watch(_ channel: ResolvedChannel) {
            guard let media = SportsPlayback.media(for: channel, in: modelContext) else { return }

            if let selectedFixture {
                watchReturn = SportsWatchReturn(fixture: selectedFixture, card: .detail, channelID: channel.id)
                // Presented from the detail cover's `onDismiss`: a cover put up
                // while another is still animating out is torn down and
                // re-presented, opening the stream twice and tripping the
                // provider's connection cap. See `presentPendingMedia`.
                pendingMedia = media
                self.selectedFixture = nil
            } else {
                playingMedia = media
            }
        }

        private func presentPendingMedia() {
            returnChannelID = nil
            guard let media = pendingMedia else { return }
            pendingMedia = nil
            playingMedia = media
        }

        /// Back from the player lands on the game it was started from, focused
        /// on the channel just watched, so the next source is one press away.
        /// Presented from the player cover's `onDismiss` for the same reason
        /// the player is presented from the card's.
        private func reopenGame() {
            guard let watchReturn else { return }
            self.watchReturn = nil
            let fixture = watchReturn.currentFixture(in: store)
            returnChannelID = watchReturn.channelToMark(among: resolved[fixture.id] ?? [])
            selectedFixture = fixture
        }
    }

    private extension TVSportsHubScreen {
        // MARK: - Follow

        private func isFollowed(_ team: SportsTeam) -> Bool {
            follows.isFollowing(team.id)
        }

        // MARK: - Fixture assembly

        /// The shared selection/grouping rules; the tvOS hub keeps only its chrome.
        private var grouping: SportsHubGrouping {
            SportsHubGrouping(scope: scope, segment: segment, follows: follows.follows, store: store)
        }

        private var displayLeagueIds: [String] {
            grouping.displayLeagueIds
        }

        private var followedLeagues: [SportsLeague] {
            grouping.followedLeagues
        }

        private var visibleFixtures: [SportsFixture] {
            grouping.visibleFixtures
        }

        private var groups: [SportsFixtureGroup] {
            grouping.groups
        }
    }

    /// A league chip: a soft wash at rest, a white fill on the chosen one and
    /// under focus — the phone hub's chips at 10 feet.
    private struct TVScopeChipLabel: View {
        let title: String
        let isFocused: Bool
        let isActive: Bool

        var body: some View {
            Text(verbatim: title)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .foregroundStyle(isFocused || isActive ? .black : .white)
                .background(Capsule().fill(fill))
        }

        private var fill: AnyShapeStyle {
            if isFocused { return AnyShapeStyle(.white) }
            return isActive ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.white.opacity(0.1))
        }
    }

    /// A round icon-only control that shares the pills' rest wash and white
    /// focus fill, for actions that need no label at rest.
    private struct TVSportsCircleChrome<Content: View>: View {
        @ViewBuilder var content: () -> Content
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            content()
                .foregroundStyle(isFocused ? .black : .white)
                .frame(width: 64, height: 64)
                .background(Circle().fill(isFocused ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.1))))
        }
    }

#endif
