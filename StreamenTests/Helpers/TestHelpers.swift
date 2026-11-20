import Foundation
import os
@testable import Streamen
import SwiftData
import Testing

func makeTestContainer() throws -> ModelContainer {
    let schema = Schema([
        Playlist.self,
        Streamen.Category.self,
        LiveStream.self,
        Movie.self,
        Series.self,
        Episode.self,
        CastMember.self,
        EPGListing.self,
        EPGSource.self
    ])
    // `cloudKitDatabase: .none` is required: the catalog uses `@Attribute(.unique)`,
    // which CloudKit forbids. The default `.automatic` mirrors to CloudKit on a
    // signed/entitled test host and fails the load with `loadIssueModelContainer`.
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try ModelContainer(for: schema, configurations: [config])
    // Tests save explicitly. Left on, the main context's autosave timer can
    // fire on the main run loop after a test has finished with the container
    // (while another test's sync is writing), and SwiftData traps. Only a test
    // on the main actor can touch `mainContext`, and those build their
    // container there, so this reaches every context that could autosave.
    if Thread.isMainThread {
        MainActor.assumeIsolated { container.mainContext.autosaveEnabled = false }
    }
    return container
}

/// The in-memory iCloud `CloudUserData` mirror, `extraModels` added to its
/// schema. `cloudKitDatabase: .none` for the same reason as the catalog.
func makeICloudMirrorTestContainer(extraModels: [any PersistentModel.Type] = []) throws -> ModelContainer {
    let schema = Schema(StreamenApp.cloudMirrorModels + extraModels)
    let config = ModelConfiguration(
        ContentSyncManager.cloudMirrorConfigurationName,
        schema: schema,
        isStoredInMemoryOnly: true,
        cloudKitDatabase: .none
    )
    return try ModelContainer(for: schema, configurations: config)
}

/// A fresh UUID-named `UserDefaults` suite, removed again once `body` returns.
func withIsolatedDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
    let suiteName = UUID().uuidString
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    try body(defaults)
}

/// The repo root, walked up from a test file's own path: neither the JSON
/// fixtures nor the string catalog are copied into the test bundle.
func repoRootURL(filePath: String = #filePath) -> URL {
    var url = URL(fileURLWithPath: filePath)
    while url.lastPathComponent != "StreamenTests", url.lastPathComponent != "StreamenUITests", url.pathComponents.count > 1 {
        url.deleteLastPathComponent()
    }
    url.deleteLastPathComponent()
    return url
}

func exampleDataURL(_ filename: String, filePath: String = #filePath) -> URL {
    repoRootURL(filePath: filePath).appendingPathComponent("ExampleData/\(filename)")
}

/// A committed Dispatcharr fixture, read from disk (not the test bundle, which
/// flattens resources).
func dispatcharrFixture(_ name: String, filePath: String = #filePath) throws -> String {
    let url = repoRootURL(filePath: filePath).appendingPathComponent("StreamenTests/Fixtures/Dispatcharr/\(name)")
    return try String(contentsOf: url, encoding: .utf8)
}

/// Whether the gitignored `ExampleData/` payloads are on this machine; tests
/// that decode them are skipped without it.
let exampleDataAvailable = FileManager.default.fileExists(atPath: exampleDataURL("").path)

func loadExampleJSON<T: Decodable>(_ filename: String, filePath: String = #filePath) throws -> T {
    let url = exampleDataURL(filename, filePath: filePath)
    let data = try Data(contentsOf: url)
    let decoder = JSONDecoder()
    return try decoder.decode(T.self, from: data)
}

/// Two-configuration in-memory container: the local catalog plus the CloudKit
/// mirror's models, matching the app's split containers.
///
/// Both configurations pin `cloudKitDatabase: .none`: the catalog uses
/// `@Attribute(.unique)`, which CloudKit forbids, so the default `.automatic`
/// fails the load with `loadIssueModelContainer` on an entitled simulator host.
func makeProfileTestContainer() throws -> ModelContainer {
    let catalogModels: [any PersistentModel.Type] = [
        Playlist.self, Streamen.Category.self, LiveStream.self, Movie.self,
        Series.self, Episode.self, CastMember.self, EPGListing.self, EPGSource.self
    ]
    let cloudModels: [any PersistentModel.Type] = [
        SyncedPlaylist.self, UserContentState.self, UserProfile.self, SyncedEPGSource.self,
        SyncedParentalPIN.self, SyncedCategoryRestriction.self, SyncedSportsFollow.self,
        SyncedRecordingServer.self, SyncedLiveTVPreferences.self
    ]
    let localConfig = ModelConfiguration(
        "local",
        schema: Schema(catalogModels),
        isStoredInMemoryOnly: true,
        cloudKitDatabase: .none
    )
    let cloudConfig = ModelConfiguration(
        "cloud",
        schema: Schema(cloudModels),
        isStoredInMemoryOnly: true,
        cloudKitDatabase: .none
    )
    return try ModelContainer(
        for: Schema(catalogModels + cloudModels),
        configurations: localConfig, cloudConfig
    )
}

/// Minimal reader for `Streamen/Localizable.xcstrings`. The catalog is asserted
/// directly because runtime resolution can't tell a translated key from an
/// English one that resolves to itself.
struct StringCatalog {
    let sourceLanguage: String
    private let strings: [String: Any]

    /// The catalog entry for `key`, so an extension can read fields that
    /// `localizations(for:)` deliberately flattens away.
    private func rawEntry(for key: String) -> [String: Any]? {
        strings[key] as? [String: Any]
    }

    static func localizable(filePath: String = #filePath) throws -> Self {
        try table("Localizable", filePath: filePath)
    }

    /// One of the app's String Catalogs, by table name.
    static func table(_ name: String, filePath: String = #filePath) throws -> Self {
        let url = repoRootURL(filePath: filePath).appendingPathComponent("Streamen/\(name).xcstrings")
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        return Self(
            sourceLanguage: root?["sourceLanguage"] as? String ?? "en",
            strings: root?["strings"] as? [String: Any] ?? [:]
        )
    }

    /// Every non-source-language translation of `key`, or `nil` when the key is
    /// absent from the catalog entirely.
    func localizations(for key: String) -> [String: String]? {
        guard let entry = strings[key] as? [String: Any] else { return nil }
        let localizations = entry["localizations"] as? [String: Any] ?? [:]
        var resolved: [String: String] = [:]
        for (language, value) in localizations where language != sourceLanguage {
            resolved[language] = displayUnit(value)?["value"] as? String ?? ""
        }
        return resolved
    }
}

/// A localization's string unit, or for a plural variation its `other` form,
/// which every language has and which carries the same format arguments.
func displayUnit(_ value: Any?) -> [String: Any]? {
    let localization = value as? [String: Any]
    if let unit = localization?["stringUnit"] as? [String: Any] { return unit }
    let plural = (localization?["variations"] as? [String: Any])?["plural"] as? [String: Any]
    return (plural?["other"] as? [String: Any])?["stringUnit"] as? [String: Any]
}

/// The locales Streamen ships. `en` is the catalog's source language and carries no
/// `stringUnit` of its own for all but a handful of entries, so its value is the
/// key itself.
let shippingLocales: Set<String> = ["ar", "en", "de", "es", "fr", "it", "ja", "ko", "nl", "pl", "pt", "ru", "tr", "zh-Hans"]

extension StringCatalog {
    /// Every key in the catalog.
    var keys: [String] {
        Array(strings.keys)
    }

    /// The English text of `key`: its own `en` unit where one exists, otherwise
    /// the key itself.
    func sourceValue(for key: String) -> String {
        let localizations = rawEntry(for: key)?["localizations"] as? [String: Any]
        let unit = (localizations?[sourceLanguage] as? [String: Any])?["stringUnit"] as? [String: Any]
        return unit?["value"] as? String ?? key
    }

    /// The languages whose translation of `key` is present, non-empty *and* in
    /// the `translated` state, plus the source language when the key exists at
    /// all. State is part of the answer: a `new` or `needs_review` unit still
    /// reaches the user as English, so a value alone does not mean translated.
    ///
    /// Returns `nil` when the key is absent from the catalog entirely.
    func translatedLanguages(for key: String) -> Set<String>? {
        guard let entry = rawEntry(for: key) else { return nil }
        let localizations = entry["localizations"] as? [String: Any] ?? [:]
        var languages: Set<String> = [sourceLanguage]
        for (language, value) in localizations {
            guard let unit = displayUnit(value),
                  unit["state"] as? String == "translated",
                  let text = unit["value"] as? String, !text.isEmpty
            else { continue }
            languages.insert(language)
        }
        return languages
    }
}

/// Asserts `key` ships a usable value in every locale in `shippingLocales`.
func expectTranslatedEverywhere(
    _ key: String,
    in catalog: StringCatalog,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    guard let languages = catalog.translatedLanguages(for: key) else {
        Issue.record("\(key) is not in the string catalog", sourceLocation: sourceLocation)
        return
    }
    let missing = shippingLocales.subtracting(languages).sorted()
    #expect(missing.isEmpty, "\(key) is untranslated in \(missing)", sourceLocation: sourceLocation)
}

/// Clears every `sync.m3uDigest.*` key from the test host's defaults.
///
/// The m3u skip-if-unchanged fingerprint is device-local `UserDefaults` state,
/// so a suite that drives `syncPlaylist` leaves one key behind per playlist it
/// creates. The ids are fresh UUIDs, so a leftover can never make a *later*
/// test skip — but they accumulate in the host for the life of the simulator,
/// and a suite that wants the real import path has to start from a known-clean
/// slate. Call it from a suite's `init()`, which Swift Testing runs before
/// every test in the suite.
func clearM3UDigests() {
    let defaults = UserDefaults.standard
    for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("sync.m3uDigest.") {
        defaults.removeObject(forKey: key)
    }
}

/// Clears every `sync.webdavDigest.*` key from the test host's defaults, for
/// the same reason `clearM3UDigests()` exists: the WebDAV listing fingerprint
/// is device-local `UserDefaults` state that outlives a test, and a suite that
/// wants the real import path has to start from a known-clean slate.
func clearWebDAVDigests() {
    let defaults = UserDefaults.standard
    for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("sync.webdavDigest.") {
        defaults.removeObject(forKey: key)
    }
}

extension ParentalPINStorage {
    /// A PIN store of the test's own. The keychain item is one per process,
    /// so a sync pass in a parallel test would otherwise read, overwrite or
    /// clear the PIN another test set.
    static func inMemory(hash initial: String? = nil) -> ParentalPINStorage {
        let hash = OSAllocatedUnfairLock<String?>(initialState: initial)
        return ParentalPINStorage(
            storedHash: { hash.withLock { $0.map { .hash($0) } ?? .notSet } },
            store: { value in hash.withLock { $0 = value }; return true },
            clear: { hash.withLock { $0 = nil }; return true }
        )
    }
}

/// A settings store of the test's own. `CloudSyncEngine` reads the active
/// profile from its preferences, and a parallel test that sets the profile in
/// `.standard` would otherwise change what this test's engine projects.
func isolatedPreferences() -> UserDefaults {
    UserDefaults(suiteName: "streamen.tests.prefs.\(UUID().uuidString)")!
}
