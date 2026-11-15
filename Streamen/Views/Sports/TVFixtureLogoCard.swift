//
//  TVFixtureLogoCard.swift
//  Streamen
//
//  The tvOS Home rail's fixture card (the hub uses `TVFixtureScoreboardCard`): the phone's
//  scoreboard card at 10 feet. Each side's crest and short name, its score big
//  and heavy beside it, and the status between them (LIVE and the clock,
//  Final, or the kickoff time), over the two clubs' colours. Focus is a scale
//  lift (TVCardButtonStyle) plus a white ring, since the system white-fill
//  idiom would paint the colours over.
//

#if os(tvOS)

    import SwiftUI

    struct TVFixtureLogoCard: View {
        let fixture: SportsFixture
        /// Off inside a rail that is already one competition, where the crest
        /// would only repeat the rail's heading.
        var showsLeagueMark = true
        var onSelect: () -> Void
        @AppStorage(SportsSyncService.hideScoresKey) private var hidesScores = false

        var body: some View {
            Button(action: onSelect) {
                TVFixtureLogoCardContent(fixture: fixture, showsLeagueMark: showsLeagueMark, showsScore: !hidesScores)
            }
            .buttonStyle(TVCardButtonStyle(focusScale: 1.06))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: fixture.tvSpokenSummary(showsScore: !hidesScores)))
        }
    }

    extension SportsFixture {
        /// One spoken line for a whole card — the matchup, the status (with the
        /// score for a live or finished game) and the competition. Team and league
        /// names come from the provider verbatim. Shared by the hub card and the
        /// Home rail's crest card.
        func tvSpokenSummary(showsScore: Bool) -> String {
            var parts: [String] = []
            if let leading = leadingSide?.team, let trailing = trailingSide?.team {
                parts.append(String(localized: "\(leading.name) versus \(trailing.name)"))
            } else {
                if let sessionKind { parts.append(String(localized: sessionKind.displayName)) }
                parts.append(eventTitle)
            }
            let score = String(localized: "\(leadingSide?.displayScore ?? "0") to \(trailingSide?.displayScore ?? "0")")
            switch status.state {
            case .scheduled:
                parts.append(headlineDate.formatted(
                    date: headlineIsOnAnotherDay || !headlineIsToday ? .abbreviated : .omitted, time: .shortened
                ))
            case .inProgress:
                parts.append(String(localized: "Live"))
                if hasTeams, showsScore { parts.append(score) }
                if let line = status.liveDetail(family: periodFamily, hidingScores: !showsScore) { parts.append(line) }
            case .final:
                parts.append(String(localized: "Final"))
                if hasTeams, showsScore {
                    parts.append(score)
                    if let qualifier = status.localizedEndingQualifier(family: periodFamily) { parts.append(qualifier) }
                }
            case .postponed:
                parts.append(status.localizedStoppage)
            }
            parts.append(tournamentLine ?? leagueName)
            return parts.joined(separator: ", ")
        }
    }

    private struct TVFixtureLogoCardContent: View {
        let fixture: SportsFixture
        let showsLeagueMark: Bool
        let showsScore: Bool
        @Environment(\.isFocused) private var isFocused

        /// The header line pins to the top on every card so a row of mixed team
        /// and event cards lines up; the crests centre in the space below it.
        var body: some View {
            VStack(spacing: 0) {
                topLine
                // Away left, home right (see `SportsFixture.awayLeads`).
                if let leading = fixture.leadingSide, let trailing = fixture.trailingSide {
                    Spacer(minLength: 0)
                    HStack(spacing: 6) {
                        side(leading).frame(maxWidth: .infinity)
                        score(leading)
                        centre.frame(minWidth: 96)
                        score(trailing)
                        side(trailing).frame(maxWidth: .infinity)
                    }
                    Spacer(minLength: 0)
                } else {
                    eventLine
                        .padding(.top, 14)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
            .frame(width: 400, height: 220)
            .background { background }
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(.white.opacity(isFocused ? 1 : 0.1), lineWidth: isFocused ? 4 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }

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

        /// The competition's crest (its abbreviation only when no crest is
        /// known; nothing in a single-league rail); an event card's status at
        /// the trailing edge — a two-sided card carries it between the scores.
        private var topLine: some View {
            HStack(spacing: 8) {
                if !showsLeagueMark {
                    EmptyView()
                } else if let logo = fixture.leagueLogoURL ?? SportsCatalog.league(id: fixture.leagueId)?.logoURL {
                    LeagueCrest(url: logo, size: 26)
                } else {
                    Text(verbatim: fixture.leagueAbbreviation)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if !fixture.hasTeams {
                    switch fixture.status.state {
                    case .inProgress:
                        Text("LIVE").font(.system(size: 20, weight: .heavy)).foregroundStyle(.red)
                    case .final:
                        Text("Final").font(.system(size: 20, weight: .bold)).foregroundStyle(.white.opacity(0.7))
                    case .postponed:
                        Text("PP").font(.callout.weight(.bold)).foregroundStyle(.white.opacity(0.7))
                    case .scheduled:
                        EmptyView()
                    }
                }
            }
            // A scheduled card in a single-league rail has nothing on this line;
            // hold its height so the crests stay level with the neighbours'.
            .frame(minHeight: 26)
        }

        /// A side's crest (a tennis player's flag) over its short name.
        private func side(_ competitor: SportsCompetitor) -> some View {
            VStack(spacing: 8) {
                TeamCrest(team: competitor.team, size: 64, backdrop: fixture.matchupRGB(for: competitor))
                Text(verbatim: competitor.team.shortName.isEmpty ? competitor.team.name : competitor.team.shortName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .opacity(isDimmed(competitor) ? 0.6 : 1)
        }

        /// A side's score once the game is live or over, unless scores are hidden.
        @ViewBuilder
        private func score(_ competitor: SportsCompetitor) -> some View {
            if showsScore, fixture.status.state == .inProgress || fixture.status.state == .final {
                Text(verbatim: competitor.displayScore)
                    .font(.system(size: fixture.hasTextScores || fixture.hasSetScores ? 26 : 44, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(isDimmed(competitor) ? 0.55 : 1))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }

        /// A finished game greys the loser; ties, live games and hidden scores
        /// keep both sides level.
        private func isDimmed(_ competitor: SportsCompetitor) -> Bool {
            guard showsScore, fixture.status.state == .final, competitor.isWinner != true else { return false }
            return fixture.home?.isWinner == true || fixture.away?.isWinner == true
        }

        /// LIVE and the clock, Final, or the kickoff time.
        private var centre: some View {
            VStack(spacing: 4) {
                switch fixture.status.state {
                case .inProgress:
                    Text("LIVE")
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(.red)
                    if let line = fixture.status.liveDetail(family: fixture.periodFamily, hidingScores: !showsScore) {
                        Text(verbatim: line)
                            .font(.system(size: 18, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                case .final:
                    Text("Final")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                    if showsScore, let qualifier = fixture.status.localizedEndingQualifier(family: fixture.periodFamily) {
                        Text(verbatim: qualifier)
                            .font(.system(size: 16))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                case .postponed:
                    Text(verbatim: fixture.status.localizedStoppage)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                case .scheduled:
                    if fixture.startTimeIsTentative == true {
                        Text("TBD")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                    } else {
                        Text(fixture.startDate, format: .dateTime.hour().minute())
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
            }
        }

        /// Competitor-less events, left-aligned so the card reads top-down: the
        /// session (or the event's short name) as the title, the Grand Prix as a
        /// quiet second line, then the time. Sizes are fixed rather than text
        /// styles — tvOS's `title3` alone would spill a three-line stack out of a
        /// 200pt card.
        private var eventLine: some View {
            VStack(alignment: .leading, spacing: 6) {
                if let kind = fixture.sessionKind {
                    Text(kind.displayName)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(verbatim: fixture.eventShortTitle)
                        .font(.system(size: 20))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                } else {
                    Text(verbatim: fixture.eventShortTitle)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Text(
                    fixture.headlineDate,
                    format: fixture.headlineIsOnAnotherDay || !fixture.headlineIsToday
                        ? .dateTime.weekday(.abbreviated).hour().minute()
                        : .dateTime.hour().minute()
                )
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.85))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
#endif
