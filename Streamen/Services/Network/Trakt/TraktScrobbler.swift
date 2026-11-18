//
//  TraktScrobbler.swift
//  Streamen
//
//  Live Trakt scrobbling for the player. While a movie or episode plays,
//  Trakt hears when it starts, pauses and resumes, so the title shows as
//  watching now; when the player closes or moves to another episode short of
//  the end, Trakt is told the title paused there, which saves it as in
//  progress at that spot without touching the history. Finishing a title is
//  still the watched sync's job (`WatchedTrackers`, at 90%), so a title is
//  never added to the history twice.
//
//  Driven by `NowPlayingService`, which already samples every engine's
//  play/pause state once a second. Live channels and recordings are skipped,
//  and so is anything without a TMDB id, which Trakt needs to match it.
//

import Foundation
import OSLog
import SwiftData

@MainActor
final class TraktScrobbler {
    static let shared = TraktScrobbler()

    /// What is playing, resolved once per stream.
    private struct Item {
        let label: String
        let body: (Double) -> TraktScrobbleBody
    }

    private var item: Item?
    /// The last state Trakt was told: playing (start) or not (pause).
    private var reportedPlaying = false
    /// The latest progress in percent, kept for a switch that arrives after
    /// the clock was reset for the next stream.
    private var lastProgress: Double = 0

    /// Below this, closing the player saves nothing: the title was barely
    /// started. At or above the watched line, the watched sync owns it.
    private static let minimumSavedProgress = 1.0
    private static let watchedProgress = 90.0

    private init() {}

    /// A new stream is on screen. Settles the one before it first.
    func begin(media: PlayableMedia, container: ModelContainer) {
        finish(clock: nil)
        guard TraktService.shared.isConnected, !media.isLive else { return }
        item = Self.resolve(media.contentRef, in: container.mainContext)
        reportedPlaying = false
        lastProgress = 0
    }

    /// Called every second with the engine's play state.
    func update(playing: Bool, clock: PlaybackClock) {
        guard let item, clock.duration > 0 else { return }
        lastProgress = Self.percent(clock)
        guard playing != reportedPlaying else { return }
        reportedPlaying = playing
        TraktService.shared.scrobble(playing ? .start : .pause, item.body(lastProgress), what: item.label)
    }

    /// The player closed or moved on: save the spot as in progress, unless it
    /// was barely started or already finished.
    func finish(clock: PlaybackClock?) {
        guard let item else { return }
        if let clock, clock.duration > 0 {
            lastProgress = Self.percent(clock)
        }
        self.item = nil
        reportedPlaying = false
        guard lastProgress >= Self.minimumSavedProgress, lastProgress < Self.watchedProgress else { return }
        TraktService.shared.scrobble(.pause, item.body(lastProgress), what: item.label)
    }

    private static func percent(_ clock: PlaybackClock) -> Double {
        min(100, max(0, clock.current / clock.duration * 100))
    }

    private static func resolve(_ ref: PlayableMedia.ContentRef, in context: ModelContext) -> Item? {
        switch ref {
        case let .movie(id):
            var descriptor = FetchDescriptor<Movie>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            guard let movie = try? context.fetch(descriptor).first else { return nil }
            guard let tmdbID = movie.tmdbId else {
                Logger.network.notice("Trakt scrobble: skipped a movie with no TMDB id")
                return nil
            }
            return Item(label: "movie tmdb:\(tmdbID)") { .movie(tmdbID: tmdbID, progress: $0) }
        case let .episode(id):
            var descriptor = FetchDescriptor<Episode>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            guard let episode = try? context.fetch(descriptor).first else { return nil }
            guard let showTMDBID = episode.series?.tmdbId else {
                Logger.network.notice("Trakt scrobble: skipped an episode whose series has no TMDB id")
                return nil
            }
            let season = episode.seasonNum
            let number = episode.episodeNum
            return Item(label: "episode tmdb:\(showTMDBID) S\(season)E\(number)") {
                .episode(showTMDBID: showTMDBID, season: season, episode: number, progress: $0)
            }
        case .live, .recording:
            return nil
        }
    }
}
