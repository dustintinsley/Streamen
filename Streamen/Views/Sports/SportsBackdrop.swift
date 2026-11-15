//
//  SportsBackdrop.swift
//  Streamen
//
//  The Sports Hub's ambient backdrop: a soft blurred glow in the clubs'
//  colours at the top of the screen, fading into the page, with the line
//  markings of the sport on show (`SportsFieldMarkings`). It gives the hub's
//  glass controls colour to refract, the way album art does behind Apple
//  Music's. Also the dark panel the game detail sheet lays its sections on.
//

import SwiftUI

struct SportsBackdrop: View {
    let colors: [Color]
    /// The ESPN sport slug ("soccer", "basketball" …); nil draws no field.
    let sport: String?
    /// How far below the top bars the backdrop runs before it has faded out.
    var height: CGFloat = 720
    var glowOpacity = 0.45

    var body: some View {
        // The glow runs up under the bars; the field starts below them (the
        // navigation bar and any inset bar such as the hub's glass controls),
        // so none of it hides behind them.
        GeometryReader { proxy in
            let top = proxy.safeAreaInsets.top
            let total = top + height
            ZStack(alignment: .top) {
                glow
                if let markings = SportsFieldMarkings(sport: sport) {
                    markings
                        .stroke(.primary.opacity(0.14), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .aspectRatio(0.62, contentMode: .fit)
                        .padding(.horizontal, 16)
                        .padding(.top, top + 16)
                }
            }
            .frame(width: proxy.size.width, height: total, alignment: .top)
            .clipped()
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: (top + height * 0.55) / total),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        // tvOS insets every screen by its overscan margins; the glow fills
        // the whole TV rather than leaving grey bands down the sides.
        #if os(tvOS)
            .ignoresSafeArea(edges: [.top, .horizontal])
        #else
            .ignoresSafeArea(edges: .top)
        #endif
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Two colours (a matchup) hold over their own sides and blend in the
    /// middle, like the fixture cards; one or three spread evenly.
    private var glow: some View {
        let tints = (colors.isEmpty ? [Color.accentColor] : colors).map { $0.opacity(glowOpacity) }
        let gradient = tints.count == 2
            ? Gradient(stops: TeamPalette.matchupStops(tints[0], tints[1]))
            : Gradient(colors: tints.count == 1 ? tints + tints : tints)
        return LinearGradient(gradient: gradient, startPoint: .leading, endPoint: .trailing)
            .blur(radius: 50)
            .padding(-60)
    }

    // MARK: - Picking colours and sport

    /// Up to three distinct club colours, followed clubs first.
    static func colors(for fixtures: [SportsFixture], preferring isFollowed: (SportsTeam) -> Bool) -> [Color] {
        let teams = fixtures.flatMap { [$0.home?.team, $0.away?.team].compactMap(\.self) }
        let ordered = teams.filter(isFollowed) + teams
        var seen = Set<String>()
        var colors: [Color] = []
        for team in ordered {
            guard let hex = team.colorHex, !seen.contains(hex), let color = TeamPalette.usableTint(fromHex: hex) else { continue }
            seen.insert(hex)
            colors.append(color)
            if colors.count == 3 { break }
        }
        return colors
    }

    /// The league's sport when the hub is scoped to one, else the sport most
    /// of the visible games share.
    static func sport(for fixtures: [SportsFixture], leagueId: String?) -> String? {
        if let leagueId { return SportsCatalog.league(id: leagueId)?.sport }
        let sports = fixtures.compactMap { SportsCatalog.league(id: $0.leagueId)?.sport }
        let counts = Dictionary(sports.map { ($0, 1) }, uniquingKeysWith: +)
        return counts.max { $0.value < $1.value }?.key
    }
}

extension View {
    /// A dark rounded panel for a section laid over the sports backdrop.
    func sportsPanel(cornerRadius: CGFloat = 20) -> some View {
        background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
