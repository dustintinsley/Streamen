//
//  SportsScreenshotDemo.swift
//  Streamen
//
//  Debug builds only: a screenshot mode for the Sports Hub. With it on, the hub
//  reads made-up leagues, teams, crests, fixtures and standings from the
//  Screenshot Demo server (`Screenshot Demo/serve.py`, the `/sports/…`
//  endpoints) instead of ESPN, so App Store and website shots carry no real
//  team or league marks. The server answers in the app's own Codable models.
//
//  It touches nothing that syncs: the demo leagues stand in for the profile's
//  follows while it's on, and the real follows come back when it's off.
//  Release builds compile none of it (`SportsProviders.current` is ESPN and
//  `SportsScreenshotDemo.isEnabled` is false).
//

import Foundation
import os

/// The data source the Sports Hub reads: ESPN, or the screenshot demo server
/// while that's on (Debug builds).
nonisolated enum SportsProviders {
    static var current: any SportsDataProvider {
        #if DEBUG
            if let server = SportsScreenshotDemo.serverURL {
                return SportsScreenshotDemoProvider(base: server)
            }
        #endif
        return ESPNClient.shared
    }
}

nonisolated enum SportsScreenshotDemo {
    #if DEBUG
        private static let serverKey = "sports.screenshotDemo.server"
        private static let leaguesKey = "sports.screenshotDemo.leagues"
        private static let cache = OSAllocatedUnfairLock<[SportsLeague]>(initialState: storedLeagues())

        /// The demo server, while the mode is on.
        static var serverURL: URL? {
            UserDefaults.standard.string(forKey: serverKey).flatMap(URL.init(string:))
        }

        static var isEnabled: Bool {
            serverURL != nil
        }

        /// The demo leagues, while the mode is on.
        static var leagues: [SportsLeague] {
            isEnabled ? cache.withLock { $0 } : []
        }

        /// Turns the mode on: fetches the server's leagues, and throws when it
        /// doesn't answer with them.
        static func enable(server: URL) async throws {
            let (data, response) = try await URLSession.shared.data(from: server.appending(path: "sports/leagues"))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let leagues = try SportsScreenshotDemoProvider.decoder.decode([SportsLeague].self, from: data)
            guard !leagues.isEmpty else { throw URLError(.cannotParseResponse) }
            UserDefaults.standard.set(data, forKey: leaguesKey)
            UserDefaults.standard.set(server.absoluteString, forKey: serverKey)
            cache.withLock { $0 = leagues }
        }

        static func disable() {
            UserDefaults.standard.removeObject(forKey: serverKey)
            UserDefaults.standard.removeObject(forKey: leaguesKey)
            cache.withLock { $0 = [] }
        }

        /// The Settings switch: turns the mode on against the demo playlist's
        /// server (the Xtream playlist with username "demo"), or off, then
        /// repoints the hub. Returns a message when it couldn't turn on.
        @MainActor
        static func setEnabled(_ enabled: Bool, playlists: [Playlist]) async -> String? {
            if enabled {
                guard let playlist = playlists.first(where: { $0.username == "demo" }),
                      let server = URL(string: playlist.serverURL)
                else { return "Add the Screenshot Demo playlist first (username demo)." }
                do {
                    try await enable(server: server)
                } catch {
                    return "The demo server didn't answer. Is serve.py running?"
                }
            } else {
                disable()
            }
            SportsSyncService.shared.configure(provider: SportsProviders.current)
            SportsFollowService.shared.reload()
            SportsSyncService.shared.syncNow()
            return nil
        }

        private static func storedLeagues() -> [SportsLeague] {
            guard let data = UserDefaults.standard.data(forKey: leaguesKey) else { return [] }
            return (try? SportsScreenshotDemoProvider.decoder.decode([SportsLeague].self, from: data)) ?? []
        }
    #else
        static let isEnabled = false
        static let leagues: [SportsLeague] = []
    #endif

    /// Every demo league, followed in the server's order.
    static var follows: [SportsFollow] {
        leagues.enumerated().map { SportsFollow(key: $1.id, kind: .league, sortOrder: $0) }
    }
}

#if DEBUG

    /// Reads the demo server's `/sports/…` endpoints. Like `ESPNClient`, a
    /// failed request degrades to an empty result.
    nonisolated struct SportsScreenshotDemoProvider: SportsDataProvider {
        let base: URL

        static let decoder: JSONDecoder = {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return decoder
        }()

        func fixtures(league: SportsLeague, month: DateComponents) async throws -> [SportsFixture] {
            guard let year = month.year, let value = month.month else { return [] }
            return await get("fixtures", league: league, ["month": String(format: "%04d%02d", year, value)]) ?? []
        }

        func fixtures(league: SportsLeague, day: Date) async throws -> [SportsFixture] {
            let parts = Calendar.current.dateComponents([.year, .month, .day], from: day)
            let value = String(format: "%04d%02d%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
            return await get("fixtures", league: league, ["day": value]) ?? []
        }

        func teams(league: SportsLeague) async throws -> [SportsTeam] {
            await get("teams", league: league) ?? []
        }

        func standings(league: SportsLeague) async throws -> [SportsStandingRow] {
            await get("standings", league: league) ?? []
        }

        func eventDetail(league _: SportsLeague, eventId _: String) async throws -> SportsEventDetail? {
            nil
        }

        private func get<Value: Decodable>(_ path: String, league: SportsLeague, _ query: [String: String] = [:]) async -> Value? {
            let items = [URLQueryItem(name: "league", value: league.id)] + query.map { URLQueryItem(name: $0, value: $1) }
            let url = base.appending(path: "sports/\(path)").appending(queryItems: items)
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200
            else { return nil }
            return try? Self.decoder.decode(Value.self, from: data)
        }
    }

#endif
