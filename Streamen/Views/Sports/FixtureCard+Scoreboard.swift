//
//  FixtureCard+Scoreboard.swift
//  Streamen
//
//  The Sports Hub's scoreboard card: a bold, team-coloured tile in the
//  manner of a stadium board. Away on the left, home on the right, each with
//  a large crest, its short name and season record; the score sits big and
//  heavy beside each side with the game's status between them (LIVE and the
//  clock, Final, or the kickoff time). A live game with one confident channel
//  offers a Watch capsule under its clock. Events without two sides (a race,
//  a fight night) keep their title and venue over the same coloured base.
//

import SwiftUI

extension FixtureCard {
    var scoreboard: some View {
        VStack(spacing: 10) {
            if let tournament = fixture.tournamentLine {
                Text(verbatim: tournament)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if fixture.hasTeams {
                HStack(spacing: 6) {
                    // Away left, home right (see `SportsFixture.awayLeads`).
                    scoreboardSide(fixture.leadingSide)
                    scoreboardScore(fixture.leadingSide)
                    scoreboardStatus
                        .frame(minWidth: 72)
                    scoreboardScore(fixture.trailingSide)
                    scoreboardSide(fixture.trailingSide)
                }
            } else {
                scoreboardEvent
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background { scoreboardBackground }
        .overlay(alignment: .topLeading) {
            if showsLeagueMark, fixture.hasTeams {
                scoreboardLeagueMark
                    .padding(10)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.08))
        }
        // Light type over the team colours, whatever the app's appearance.
        .environment(\.colorScheme, .dark)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    // MARK: - Background

    /// The two clubs' colours meeting across the card, deepened towards the
    /// bottom so white type stays legible over a bright brand colour.
    private var scoreboardBackground: some View {
        ZStack {
            Color(white: 0.1)
            LinearGradient(
                stops: TeamPalette.matchupStops(
                    fixture.matchupColors.leading.opacity(0.85), fixture.matchupColors.trailing.opacity(0.85)
                ),
                startPoint: .leading,
                endPoint: .trailing
            )
            LinearGradient(
                colors: [.black.opacity(0.05), .black.opacity(0.4)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    // MARK: - Sides

    private func scoreboardSide(_ competitor: SportsCompetitor?) -> some View {
        VStack(spacing: 6) {
            if let competitor {
                TeamCrest(team: competitor.team, size: 44, backdrop: fixture.matchupRGB(for: competitor))
                HStack(spacing: 3) {
                    Text(verbatim: shortName(competitor.team))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if isFollowed(competitor.team) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.yellow)
                    }
                }
                if let record = competitor.record, !record.isEmpty {
                    Text(verbatim: record)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .opacity(isDimmed(competitor) ? 0.6 : 1)
    }

    @ViewBuilder
    private func scoreboardScore(_ competitor: SportsCompetitor?) -> some View {
        if showsScores, let competitor {
            Text(verbatim: competitor.displayScore)
                .font(scoreFont)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(isDimmed(competitor) ? .secondary : .primary)
        }
    }

    private var showsScores: Bool {
        !hidesScores && (fixture.status.state == .inProgress || fixture.status.state == .final)
    }

    /// Big heavy digits for a plain score; cricket's "225/6" and tennis sets
    /// keep a size that fits.
    private var scoreFont: Font {
        fixture.hasTextScores || fixture.hasSetScores
            ? .system(.title3, design: .rounded, weight: .bold)
            : .system(size: 38, weight: .heavy, design: .rounded)
    }

    /// A finished game greys the loser; ties, live games and hidden scores
    /// keep both sides level.
    private func isDimmed(_ competitor: SportsCompetitor?) -> Bool {
        guard let competitor, fixture.status.state == .final, !hidesScores else { return false }
        return rowWeight(competitor) != .bold && (fixture.home?.isWinner == true || fixture.away?.isWinner == true)
    }

    private func shortName(_ team: SportsTeam) -> String {
        team.shortName.isEmpty ? team.name : team.shortName
    }

    // MARK: - Status

    private var scoreboardStatus: some View {
        VStack(spacing: 4) {
            switch fixture.status.state {
            case .inProgress:
                Text("LIVE")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(.red)
                if let line = fixture.status.liveDetail(family: fixture.periodFamily, hidingScores: hidesScores) {
                    Text(verbatim: line)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                if let confidentChannel {
                    watchCapsule(confidentChannel)
                }
            case .final:
                Text("Final")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                if !hidesScores, let qualifier = fixture.status.localizedEndingQualifier(family: fixture.periodFamily) {
                    Text(verbatim: qualifier)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if showsDateLine { scoreboardDateLine }
            case .postponed:
                Text(verbatim: fixture.status.localizedStoppage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            case .scheduled:
                if fixture.startTimeIsTentative == true {
                    Text("TBD")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                } else {
                    Text(fixture.headlineDate, format: .dateTime.hour().minute())
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                if showsDateLine { scoreboardDateLine }
            }
        }
    }

    private var scoreboardDateLine: some View {
        Text(fixture.headlineDate, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }

    private func watchCapsule(_ channel: ResolvedChannel) -> some View {
        Button {
            onWatch(channel)
        } label: {
            // One line always: a narrow centre column (a soccer clock like
            // "52'") must not break the label into "Watc / h".
            Label("Watch", systemImage: "play.fill")
                .font(.caption2.weight(.bold))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.white.opacity(0.2), in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
    }

    // MARK: - League mark

    @ViewBuilder
    private var scoreboardLeagueMark: some View {
        if let logo = fixture.leagueLogoURL ?? SportsCatalog.league(id: fixture.leagueId)?.logoURL {
            LeagueCrest(url: logo, size: 16)
        }
    }

    // MARK: - Events

    /// A race session, a race weekend or a fight night: its crest, its name
    /// over its venue or Grand Prix, and the status on the right.
    private var scoreboardEvent: some View {
        HStack(spacing: 12) {
            if let logo = fixture.leagueLogoURL ?? SportsCatalog.league(id: fixture.leagueId)?.logoURL {
                LeagueCrest(url: logo, size: 36)
            }
            VStack(alignment: .leading, spacing: 3) {
                if let kind = fixture.sessionKind {
                    Text(kind.displayName)
                        .font(.headline)
                        .lineLimit(1)
                    Text(verbatim: fixture.eventTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(verbatim: fixture.eventTitle)
                        .font(.headline)
                        .lineLimit(2)
                    if let subtitle = fixture.eventSubtitle {
                        Text(verbatim: subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 8)
            scoreboardStatus
                .frame(minWidth: 72)
        }
    }
}
