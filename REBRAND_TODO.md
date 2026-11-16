# Streamen rebrand — follow-ups

Streamen is a fork. The rename (branch `dustin-custom-v2` in all four repos)
replaced the upstream project's name and bundle prefix with Streamen's and
`hardheaded.`. The goal is no trace of the upstream name anywhere. What's still
open is listed below.

## Still open

| What | Where | What it needs |
|------|-------|---------------|
| Prebuilt `FFmpeg.xcframework` download | StreamenEngine `Package.swift` (`ffmpegArtifactURL`) | It still downloads upstream's checksum-pinned v0.5.0 release. Build our own with `build/scripts/make-xcframework.sh` and publish it as a release on `dustintinsley/StreamenEngine`, then point the URL and checksum at it. |
| C helper prefix and header folder | StreamenEngine `build/support/`, `build/scripts/make-xcframework.sh`, `Package.swift` and the Swift files that call the helpers | The helpers' prefix and the nested FFmpeg header folder are baked into the prebuilt download above. Rename them in the same step as building our own `FFmpeg.xcframework`; until then the names must match the binary. |
| Default branch | GitHub, all four repos | The forks' default branch is still `main` (upstream content), so a plain `git clone` and `blob/main` links show upstream. Consider making `dustin-custom-v2` the default. |
| Discord invite | `README.md` | Check that `discord.gg/DMnQfr69Ug` is Streamen's own server, not the upstream community's. |

If a build keeps using an old binary, clear
`~/Library/Caches/org.swift.swiftpm/manifests` and the engine's folder under the
shared package cache's `artifacts/` (`~/Library/Developer/Streamen-SharedSPM`),
then resolve packages again.

Note for future upstream merges: upstream keeps its own names, so merge through
a rebranded copy of upstream (rebrand script on a branch, then merge it), and
check the merge didn't bring the old names back.

## Licenses

Keep the license terms and the original author's copyright lines intact
(StreamenEngine `LICENSE` and `THIRD-PARTY-NOTICES.md`; Streamen is AGPL-3.0).
Only the project names and paths in those files were changed.

## Apple Developer account setup

The new identifiers don't exist yet in your Apple Developer account. Register
them before signing a build that uses them:

- App IDs: `com.hardheaded.streamen`, `com.hardheaded.streamen.StreamenWidgets`,
  `com.hardheaded.streamen.topshelf`
- App Group: `group.com.hardheaded.streamen`
- iCloud container: `iCloud.hardheaded.streamen` (then deploy the CloudKit schema,
  including `CD_SyncedRecordingServer` and `CD_SyncedBackendChoice`, to Production)
- In-app purchases (App Store Connect): `com.hardheaded.streamen.pro.monthly` as an
  **auto-renewable subscription** in a group named "Streamen Pro", and
  `com.hardheaded.streamen.premium.lifetime` as a **non-consumable**. The IDs must
  match `PremiumManager.Plan` exactly (pinned by `PremiumPlanTests`).

## Other things to know

- User defaults, keychain and store-file names were renamed too, so Streamen
  starts fresh and doesn't read data saved by an installed copy of the upstream app.
- The in-app Acknowledgements screen was removed (2026-11-07). Before any
  public release, add a small "Legal & Licenses" entry back: Streamen's AGPL
  notice and source link, the GPL/LGPL libraries (KSPlayer, FFmpegKit, VLCKit,
  AetherEngine, FFmpeg) with source links, the Big Buck Bunny CC BY 3.0 credit
  for the subtitle preview, and the TMDB attribution its API terms require.
  The removed `CreditsInfo.swift` / `CreditsView.swift` are in git history.
