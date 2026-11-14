//
//  DisabledPlaylistTests.swift
//  StreamenTests
//
//  Settings › Playlist › Enabled. A disabled playlist stays in Settings but
//  leaves every browse surface: the resolved scope, the switcher rows, Combined
//  and auto-sync. The plan lock still counts it, so disabling the oldest never
//  hands the free plan another playlist. The flag rides Streamen Cloud only
//  while it's off, so existing records don't read as changed.
//

import Foundation
@testable import Streamen
import StreamenCloudKit
import SwiftData
import Testing

@MainActor
struct DisabledPlaylistTests {
    private typealias Codec = StreamenCloudPayloadCodec

    private func makePlaylists(_ names: [String], in context: ModelContext) throws -> [Playlist] {
        let playlists = names.map { Playlist(name: $0, serverURL: "http://\($0)", username: "u", password: "p") }
        for (offset, playlist) in playlists.enumerated() {
            playlist.addedAt = Date(timeIntervalSince1970: 1_700_000_000 + Double(offset))
            context.insert(playlist)
        }
        try context.save()
        return playlists
    }

    private func makeCombined(_ playlists: [Playlist]) {
        for (offset, playlist) in playlists.enumerated() {
            playlist.combinedTabs = [.movies]
            playlist.combinedPriority = offset + 1
        }
    }

    // MARK: - Selection

    @Test func `a disabled selection falls back to the oldest enabled playlist`() throws {
        let container = try makeProfileTestContainer()
        let playlists = try makePlaylists(["First", "Second", "Third"], in: container.mainContext)
        playlists[0].isEnabled = false
        playlists[2].isEnabled = false

        let scope = playlists.scope(for: playlists[2].id.uuidString, isPremium: true)

        #expect(scope.playlistIDs == [playlists[1].id])
    }

    @Test func `re-enabling a playlist lands back on the stored selection`() throws {
        let container = try makeProfileTestContainer()
        let playlists = try makePlaylists(["First", "Second"], in: container.mainContext)
        let stored = playlists[1].id.uuidString
        playlists[1].isEnabled = false
        #expect(playlists.scope(for: stored, isPremium: true).playlistIDs == [playlists[0].id])

        playlists[1].isEnabled = true

        #expect(playlists.scope(for: stored, isPremium: true).playlistIDs == [playlists[1].id])
    }

    @Test func `disabling the oldest leaves the free plan nothing rather than unlocking another`() throws {
        let container = try makeProfileTestContainer()
        let playlists = try makePlaylists(["First", "Second"], in: container.mainContext)
        playlists[0].isEnabled = false

        #expect(playlists.unlocked(premium: false).isEmpty)
        #expect(playlists.isLocked(playlists[1], isPremium: false))
    }

    @Test func `the last usable playlist must stay enabled`() throws {
        let container = try makeProfileTestContainer()
        let playlists = try makePlaylists(["First", "Second"], in: container.mainContext)

        #expect(!playlists.mustStayEnabled(playlists[0], isPremium: true))
        playlists[1].isEnabled = false
        #expect(playlists.mustStayEnabled(playlists[0], isPremium: true))
        #expect(!playlists.mustStayEnabled(playlists[1], isPremium: true))
    }

    @Test func `on the free plan the oldest must stay enabled and locked ones can go off`() throws {
        let container = try makeProfileTestContainer()
        let playlists = try makePlaylists(["First", "Second"], in: container.mainContext)

        #expect(playlists.mustStayEnabled(playlists[0], isPremium: false))
        #expect(!playlists.mustStayEnabled(playlists[1], isPremium: false))
    }

    // MARK: - Switcher

    @Test func `the switcher rows leave out disabled playlists`() throws {
        let container = try makeProfileTestContainer()
        let playlists = try makePlaylists(["First", "Second", "Third"], in: container.mainContext)
        playlists[1].isEnabled = false
        let scope = playlists.scope(for: playlists[0].id.uuidString, isPremium: true)

        let rows = QuickSwitchResolver.playlistRows(playlists, scope: scope, isPremium: true)

        #expect(rows.map(\.item.name) == ["First", "Third"])
    }

    // MARK: - Combined

    @Test func `combined skips a disabled member`() throws {
        let container = try makeProfileTestContainer()
        let playlists = try makePlaylists(["First", "Second", "Third"], in: container.mainContext)
        makeCombined(playlists)
        playlists[1].isEnabled = false

        let scope = playlists.scope(for: PlaylistSelectionStore.combined, isPremium: true)

        #expect(scope.isCombined)
        #expect(scope.playlistIDs == [playlists[0].id, playlists[2].id])
        #expect(playlists.combinedMembers.count == 3)
    }

    @Test func `combined needs two enabled members`() throws {
        let container = try makeProfileTestContainer()
        let playlists = try makePlaylists(["First", "Second"], in: container.mainContext)
        makeCombined(playlists)
        playlists[0].isEnabled = false

        let scope = playlists.scope(for: PlaylistSelectionStore.combined, isPremium: true)

        #expect(!scope.isCombined)
        #expect(scope.playlistIDs == [playlists[1].id])
        #expect(QuickSwitchResolver.combinedAction(playlists, scope: scope, isPremium: true) == .configure)
    }

    // MARK: - Auto-sync

    @Test func `a disabled playlist is never an auto-sync candidate`() throws {
        let container = try makeProfileTestContainer()
        let playlists = try makePlaylists(["First"], in: container.mainContext)
        playlists[0].isEnabled = false

        #expect(!playlists[0].autoSyncCandidate(in: .isolated(playlists[0].id)).syncEnabled)
    }

    // MARK: - Streamen Cloud

    private func synced(isEnabled: Bool) -> SyncedPlaylist {
        SyncedPlaylist(
            id: UUID(uuidString: "0A1B2C3D-0000-4000-8000-00000000EE01")!, name: "Harbor Lights",
            serverURL: "http://provider.example:8080", username: "viewer", password: "secret",
            sourceTypeRaw: PlaylistSourceType.xtream.rawValue, epgURL: nil, syncEnabled: true,
            isEnabled: isEnabled, updatedAt: Date(timeIntervalSince1970: 1_760_000_000)
        )
    }

    @Test func `an enabled playlist carries no isEnabled field`() {
        #expect(Codec.payload(for: synced(isEnabled: true), previous: nil).data["isEnabled"] == nil)
    }

    @Test func `a disabled playlist round-trips`() throws {
        let payload = Codec.payload(for: synced(isEnabled: false), previous: nil)
        #expect(payload.data["isEnabled"] == .bool(false))

        #expect(try Codec.makeModel(from: payload, as: SyncedPlaylist.self).isEnabled == false)
    }

    @Test func `re-enabling writes true over a synced false`() throws {
        let previous = try Codec.encoded(synced(isEnabled: false), previous: nil)

        let payload = Codec.payload(for: synced(isEnabled: true), previous: previous)

        #expect(payload.data["isEnabled"] == .bool(true))
    }

    @Test func `a payload without isEnabled leaves the row's flag alone`() throws {
        let payload = Codec.payload(for: synced(isEnabled: true), previous: nil)
        let row = synced(isEnabled: false)

        try Codec.apply(payload, to: row)

        #expect(row.isEnabled == false)
        #expect(try Codec.makeModel(from: payload, as: SyncedPlaylist.self).isEnabled == true)
    }

    // MARK: - iCloud

    @Test func `an iCloud config written before the flag decodes as enabled`() throws {
        let original = PlaylistConfigValues(
            name: "Harbor Lights", serverURL: "http://provider.example:8080", username: "viewer",
            password: "secret", sourceTypeRaw: PlaylistSourceType.xtream.rawValue, epgURL: nil, syncEnabled: true
        )
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        json.removeValue(forKey: "isEnabled")

        let decoded = try JSONDecoder().decode(PlaylistConfigValues.self, from: JSONSerialization.data(withJSONObject: json))

        #expect(decoded.isEnabled)
    }
}
