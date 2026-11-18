//
//  TraktService.swift
//  Streamen
//
//  The app-wide coordinator for the Trakt integration. Owns the OAuth token
//  lifecycle (device-flow connect, refresh, disconnect), exposes connection
//  state for the Settings UI to observe, and provides fire-and-forget watched
//  syncing plus watchlist fetching.
//
//  A shared singleton because watched-state changes originate from many places
//  (player completion, detail-screen toggles, model methods) that don't all
//  have access to the SwiftUI environment. It's still `@Observable`, so views
//  observe `TraktService.shared` directly.
//

import Foundation
import OSLog
import SwiftData
import SwiftUI

@MainActor
@Observable
final class TraktService {
    static let shared = TraktService()

    /// The connected Trakt username, or nil when not connected.
    private(set) var username: String?

    /// The in-flight device code while the user is approving authorization.
    private(set) var pendingCode: TraktDeviceCode?

    /// A human-readable failure from the last connect attempt, surfaced in the
    /// Settings UI. Cleared when a new attempt begins.
    private(set) var connectionError: String?

    /// Whether a device-code authorization is currently being polled.
    private(set) var isConnecting = false

    /// Whether a watched-history import is currently running.
    private(set) var isImporting = false

    /// The result of the most recent import, surfaced in the Settings UI.
    /// Cleared when a new import begins.
    private(set) var lastImport: TraktImportSummary?

    private var tokens: TraktTokens?
    private var pollingTask: Task<Void, Never>?
    private var refreshTask: Task<String?, Never>?

    private let client = TraktClient.shared

    private init() {}

    /// Whether the build has Trakt credentials at all. When false the whole
    /// integration is hidden.
    var isConfigured: Bool {
        client.isConfigured
    }

    var isConnected: Bool {
        username != nil
    }

    // MARK: - Lifecycle

    /// Restores a previously connected session at launch: loads the stored
    /// tokens, refreshes them if stale, and fetches the username. Best-effort.
    func restore() async {
        guard isConfigured, let stored = TraktTokenStore.load() else { return }
        tokens = stored
        guard let accessToken = await validAccessToken() else {
            // Refresh failed (revoked/expired) — drop the dead session quietly.
            await disconnect()
            return
        }
        username = try? await client.currentUser(accessToken: accessToken).username
    }

    // MARK: - Connect (device flow)

    /// Begins the device-flow connect: requests a code and starts polling.
    func connect() {
        guard isConfigured, !isConnecting else { return }
        connectionError = nil
        isConnecting = true

        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            await self?.runDeviceFlow()
        }
    }

    /// Cancels an in-progress connect.
    func cancelConnect() {
        pollingTask?.cancel()
        pollingTask = nil
        pendingCode = nil
        isConnecting = false
    }

    private func runDeviceFlow() async {
        do {
            let code = try await client.requestDeviceCode()
            pendingCode = code

            let deadline = Date().addingTimeInterval(TimeInterval(code.expiresIn))
            var interval = TimeInterval(max(code.interval, 1))

            while !Task.isCancelled, Date() < deadline {
                try await Task.sleep(for: .seconds(interval))
                if Task.isCancelled {
                    return
                }

                do {
                    let response = try await client.pollForToken(deviceCode: code.deviceCode)
                    await finishConnect(with: response)
                    return
                } catch TraktError.authorizationPending {
                    continue
                } catch TraktError.slowDown {
                    interval += 1
                    continue
                } catch TraktError.codeExpired {
                    failConnect("The code expired. Please try connecting again.")
                    return
                } catch TraktError.codeDenied {
                    failConnect("Authorization was declined.")
                    return
                } catch TraktError.codeUsed {
                    failConnect("That code was already used. Please try again.")
                    return
                }
            }

            if !Task.isCancelled {
                failConnect("The code expired. Please try connecting again.")
            }
        } catch is CancellationError {
            // Cancelled via cancelConnect() — state already reset there.
        } catch {
            failConnect("Couldn't reach Trakt. Check your connection and try again.")
        }
    }

    private func finishConnect(with response: TraktTokenResponse) async {
        applyTokens(response.tokens)
        username = try? await client.currentUser(accessToken: response.accessToken).username
        pendingCode = nil
        isConnecting = false
        connectionError = nil
    }

    private func failConnect(_ message: String) {
        connectionError = message
        pendingCode = nil
        isConnecting = false
    }

    // MARK: - Disconnect

    /// Disconnects: revokes the token server-side (best effort) and clears all
    /// local state.
    func disconnect() async {
        pollingTask?.cancel()
        pollingTask = nil
        if let accessToken = tokens?.accessToken {
            try? await client.revokeToken(accessToken)
        }
        TraktTokenStore.clear()
        // Parked watched state belongs to the account that was just signed out.
        TraktPendingWatchedStore.clearAll()
        tokens = nil
        username = nil
        pendingCode = nil
        isConnecting = false
        lastImport = nil
    }

    // MARK: - Watched sync (fire-and-forget)

    /// Syncs a movie's watched state to Trakt. Captures the TMDB id up front so
    /// the model never crosses an actor boundary. No-ops when not connected or
    /// the movie has no TMDB id.
    func syncWatched(movie: Movie, watched: Bool) {
        guard isConnected else { return }
        guard let tmdbID = movie.tmdbId else {
            Logger.network.notice("Trakt: skipped a movie with no TMDB id")
            return
        }
        let items = TraktSyncItems.movie(tmdbID: tmdbID)
        syncHistory(items, add: watched, what: "movie tmdb:\(tmdbID)")
    }

    /// Syncs an episode's watched state to Trakt using its show's TMDB id plus
    /// the season/episode numbers.
    func syncWatched(episode: Episode, watched: Bool) {
        guard isConnected else { return }
        guard let showTMDBID = episode.series?.tmdbId else {
            Logger.network.notice("Trakt: skipped an episode whose series has no TMDB id")
            return
        }
        let items = TraktSyncItems.episode(
            showTMDBID: showTMDBID,
            season: episode.seasonNum,
            episode: episode.episodeNum
        )
        syncHistory(
            items,
            add: watched,
            what: "episode tmdb:\(showTMDBID) S\(episode.seasonNum)E\(episode.episodeNum)"
        )
    }

    /// Best-effort: a failed sync never disrupts playback or the UI, but every
    /// outcome is logged so a history that doesn't arrive can be traced.
    private func syncHistory(_ items: TraktSyncItems, add: Bool, what: String) {
        let verb = add ? "add" : "remove"
        Task { [weak self] in
            guard let self else { return }
            guard let accessToken = await validAccessToken() else {
                Logger.network.warning("Trakt: \(verb, privacy: .public) \(what, privacy: .public) skipped, no valid token")
                return
            }
            do {
                let result = add
                    ? try await client.addToHistory(items, accessToken: accessToken)
                    : try await client.removeFromHistory(items, accessToken: accessToken)
                if result.notFoundCount > 0 {
                    Logger.network.warning("Trakt: \(verb, privacy: .public) \(what, privacy: .public) not matched by Trakt")
                } else {
                    Logger.network.info("Trakt: \(verb, privacy: .public) \(what, privacy: .public) ok, \(result.changedCount) changed")
                }
            } catch {
                Logger.network.error("Trakt: \(verb, privacy: .public) \(what, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    // MARK: - Scrobble

    /// The scrobble in flight, so calls reach Trakt in the order they were
    /// made: a quick start-then-pause must not land as pause-then-start.
    @ObservationIgnored private var scrobbleChain: Task<Void, Never>?

    /// Best-effort, like the watched sync; every outcome is logged.
    func scrobble(_ action: TraktScrobbleAction, _ body: TraktScrobbleBody, what: String) {
        guard isConnected else { return }
        let previous = scrobbleChain
        scrobbleChain = Task { [weak self] in
            await previous?.value
            guard let self, let accessToken = await validAccessToken() else { return }
            let percent = Int(body.progress.rounded())
            do {
                try await client.scrobble(action, item: body, accessToken: accessToken)
                Logger.network.info("Trakt scrobble: \(action.rawValue, privacy: .public) \(what, privacy: .public) at \(percent)%")
            } catch TraktError.server(409) {
                // Trakt already has this exact scrobble from moments ago.
                Logger.network.info("Trakt scrobble: \(action.rawValue, privacy: .public) \(what, privacy: .public) already recorded")
            } catch {
                Logger.network.error("Trakt scrobble: \(action.rawValue, privacy: .public) \(what, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    // MARK: - Watchlist

    /// Fetches the user's watchlist. Returns an empty array when not connected
    /// or on error — the home row simply hides.
    func fetchWatchlist() async -> [TraktWatchlistItem] {
        guard let accessToken = await validAccessToken() else { return [] }
        return await (try? client.watchlist(accessToken: accessToken)) ?? []
    }

    // MARK: - Watched import

    /// Imports the user's Trakt watched history into the local catalog, marking
    /// matching movies and episodes as watched. Writes through a context of its
    /// own on `context`'s container, off the main actor; the UI's context picks
    /// the change up on merge, and the iCloud reconciler then mirrors it to the
    /// user's other devices. No-ops when not connected or an import is already
    /// running.
    func importWatched(into context: ModelContext) async {
        guard isConnected, !isImporting else { return }
        isImporting = true
        lastImport = nil
        defer { isImporting = false }

        guard let accessToken = await validAccessToken() else {
            lastImport = .failure
            return
        }
        do {
            async let movies = client.watchedMovies(accessToken: accessToken)
            async let shows = client.watchedShows(accessToken: accessToken)
            lastImport = try await Self.applyImport(movies: movies, shows: shows, container: context.container)
        } catch {
            lastImport = .failure
        }
    }

    /// Matching the history against the catalog fetches and faults catalog
    /// rows, which ran on the main thread when it wrote through the view context.
    @concurrent
    private static func applyImport(
        movies: [TraktWatchedMovie],
        shows: [TraktWatchedShow],
        container: ModelContainer
    ) async -> TraktImportSummary {
        TraktWatchedImporter.apply(movies: movies, shows: shows, in: ModelContext(container))
    }

    // MARK: - Tokens

    /// Returns a usable access token, refreshing first if it's stale. Coalesces
    /// concurrent refreshes into a single request.
    private func validAccessToken() async -> String? {
        guard let current = tokens else { return nil }
        if !current.needsRefresh {
            return current.accessToken
        }

        if let refreshTask {
            return await refreshTask.value
        }

        let task = Task { [weak self] () -> String? in
            guard let self else { return nil }
            do {
                let response = try await client.refreshToken(current.refreshToken)
                applyTokens(response.tokens)
                return response.tokens.accessToken
            } catch {
                // Refresh token is dead — drop the session so the UI prompts a
                // reconnect rather than retrying forever.
                await disconnect()
                return nil
            }
        }
        refreshTask = task
        let result = await task.value
        refreshTask = nil
        return result
    }

    private func applyTokens(_ newTokens: TraktTokens) {
        tokens = newTokens
        TraktTokenStore.save(newTokens)
    }
}
