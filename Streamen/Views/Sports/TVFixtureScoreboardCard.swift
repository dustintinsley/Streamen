//
//  TVFixtureScoreboardCard.swift
//  Streamen
//
//  The tvOS Sports Hub's card: the Mac and phone hub's scoreboard
//  (`FixtureCard+Scoreboard`) at 10 feet, one per row in a column. The
//  competition line on top, away on the left and home on the right, each with
//  a large crest, its short name (a star when followed) and season record; the
//  scores big and heavy beside the status (LIVE and the clock, Final, or the
//  kickoff time). A live game with one confident channel shows a Watch capsule
//  under its clock, and Play/Pause on the focused card starts it — a second
//  focus target inside the card would fight the column's up/down movement.
//  Events without two sides keep their crest, title and venue over the same
//  coloured base. Focus is a gentle lift plus a white ring.
//

#if os(tvOS)

    import SwiftUI

    struct TVFixtureScoreboardCard: View {
        let fixture: SportsFixture
        let resolved: [ResolvedChannel]
        let isFollowed: (SportsTeam) -> Bool
        /// Off inside a group that is already one competition.
        var showsLeagueMark = true
        /// Off under a day header, where the date would only repeat it.
        var showsDate = true
        var onSelect: () -> Void
        var onWatch: (ResolvedChannel) -> Void
        @AppStorage(SportsSyncService.hideScoresKey) private var hidesScores = false

        /// The lone confident channel a live card offers one-press playback for.
        private var confidentChannel: ResolvedChannel? {
            guard fixture.isInProgress else { return nil }
            return resolved.first { $0.isConfident }
        }

        var body: some View {
            Button(action: onSelect) {
                TVFixtureScoreboardContent(
                    fixture: fixture,
                    isFollowed: isFollowed,
                    showsLeagueMark: showsLeagueMark,
                    showsDateLine: fixture.headlineIsOnAnotherDay || (showsDate && !fixture.headlineIsToday),
                    hidesScores: hidesScores,
                    watchChannel: confidentChannel
                )
            }
            .buttonStyle(TVCardButtonStyle(focusScale: 1.02))
            .onPlayPauseCommand {
                if let confidentChannel { onWatch(confidentChannel) }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: fixture.tvSpokenSummary(showsScore: !hidesScores)))
        }
    }

    private struct TVFixtureScoreboardContent: View {
        let fixture: SportsFixture
        let isFollowed: (SportsTeam) -> Bool
        let showsLeagueMark: Bool
        let showsDateLine: Bool
        let hidesScores: Bool
        let watchChannel: ResolvedChannel?
        @Environment(\.isFocused) private var isFocused

        private let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)

        var body: some View {
            VStack(spacing: 14) {
                if let tournament = fixture.tournamentLine {
                    Text(verbatim: tournament)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                }
                if fixture.hasTeams {
                    HStack(spacing: 10) {
                        // Away left, home right (see `SportsFixture.awayLeads`).
                        side(fixture.leadingSide)
                        score(fixture.leadingSide)
                        status.frame(minWidth: 150)
                        score(fixture.trailingSide)
                        side(fixture.trailingSide)
                    }
                } else {
                    event
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
            .background { background }
            .overlay(alignment: .topLeading) {
                if showsLeagueMark, fixture.hasTeams, let logo = leagueLogo {
                    LeagueCrest(url: logo, size: 28).padding(18)
                }
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(.white.opacity(isFocused ? 1 : 0.08), lineWidth: isFocused ? 4 : 1))
            .environment(\.colorScheme, .dark)
        }

        private var leagueLogo: URL? {
            fixture.leagueLogoURL ?? SportsCatalog.league(id: fixture.leagueId)?.logoURL
        }

        // MARK: - Background

        /// The two clubs' colours meeting across the card, deepened towards the
        /// bottom so white type stays legible over a bright brand colour.
        private var background: some View {
            ZStack {
                Color(white: 0.1)
                LinearGradient(
                    stops: TeamPalette.matchupStops(
                        fixture.matchupColors.leading.opacity(0.85), fixture.matchupColors.trailing.opacity(0.85)
                    ),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                LinearGradient(colors: [.black.opacity(0.05), .black.opacity(0.4)], startPoint: .top, endPoint: .bottom)
            }
        }

        // MARK: - Sides

        private func side(_ competitor: SportsCompetitor?) -> some View {
            VStack(spacing: 8) {
                if let competitor {
                    TeamCrest(team: competitor.team, size: 80, backdrop: fixture.matchupRGB(for: competitor))
                    HStack(spacing: 6) {
                        Text(verbatim: competitor.team.shortName.isEmpty ? competitor.team.name : competitor.team.shortName)
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        if isFollowed(competitor.team) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.yellow)
                        }
                    }
                    if let record = competitor.record, !record.isEmpty {
                        Text(verbatim: record)
                            .font(.system(size: 20))
                            .foregroundStyle(.white.opacity(0.65))
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .opacity(isDimmed(competitor) ? 0.6 : 1)
        }

        @ViewBuilder
        private func score(_ competitor: SportsCompetitor?) -> some View {
            if showsScores, let competitor {
                Text(verbatim: competitor.displayScore)
                    .font(.system(
                        size: fixture.hasTextScores || fixture.hasSetScores ? 34 : 64,
                        weight: .heavy,
                        design: .rounded
                    ))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(.white.opacity(isDimmed(competitor) ? 0.55 : 1))
            }
        }

        private var showsScores: Bool {
            !hidesScores && (fixture.status.state == .inProgress || fixture.status.state == .final)
        }

        /// A finished game greys the loser; ties, live games and hidden scores
        /// keep both sides level.
        private func isDimmed(_ competitor: SportsCompetitor?) -> Bool {
            guard let competitor, !hidesScores, fixture.status.state == .final, competitor.isWinner != true else {
                return false
            }
            return fixture.home?.isWinner == true || fixture.away?.isWinner == true
        }

        // MARK: - Status

        private var status: some View {
            VStack(spacing: 6) {
                switch fixture.status.state {
                case .inProgress:
                    Text("LIVE")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(.red)
                    if let line = fixture.status.liveDetail(family: fixture.periodFamily, hidingScores: hidesScores) {
                        Text(verbatim: line)
                            .font(.system(size: 22, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    if watchChannel != nil { watchCapsule }
                case .final:
                    Text("Final")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                    if !hidesScores, let qualifier = fixture.status.localizedEndingQualifier(family: fixture.periodFamily) {
                        Text(verbatim: qualifier)
                            .font(.system(size: 18))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                    if showsDateLine { dateLine }
                case .postponed:
                    Text(verbatim: fixture.status.localizedStoppage)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                case .scheduled:
                    if fixture.startTimeIsTentative == true {
                        Text("TBD")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    } else {
                        Text(fixture.headlineDate, format: .dateTime.hour().minute())
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    if showsDateLine { dateLine }
                }
            }
        }

        private var dateLine: some View {
            Text(fixture.headlineDate, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.65))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }

        /// The Mac's Watch capsule; Play/Pause on the focused card plays it.
        private var watchCapsule: some View {
            Label("Watch", systemImage: "playpause.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(.white.opacity(0.2), in: Capsule())
                .padding(.top, 2)
        }

        // MARK: - Events

        /// A race session, a race weekend or a fight night: its crest, its name
        /// over its venue or Grand Prix, and the status on the right.
        private var event: some View {
            HStack(spacing: 20) {
                if let logo = leagueLogo {
                    LeagueCrest(url: logo, size: 56)
                }
                VStack(alignment: .leading, spacing: 6) {
                    if let kind = fixture.sessionKind {
                        Text(kind.displayName)
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(verbatim: fixture.eventTitle)
                            .font(.system(size: 22))
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(1)
                    } else {
                        Text(verbatim: fixture.eventTitle)
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        if let subtitle = fixture.eventSubtitle {
                            Text(verbatim: subtitle)
                                .font(.system(size: 22))
                                .foregroundStyle(.white.opacity(0.65))
                                .lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 12)
                status.frame(minWidth: 150)
            }
        }
    }

#endif
