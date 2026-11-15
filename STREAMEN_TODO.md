# Streamen feature TODO

Ideas queued for later. Rebrand cleanup lives in `REBRAND_TODO.md`.

## Mac app: more up-to-date look

Already done: glass Live TV category panel with a collapse button, hover
effects on posters, tiles and channel rows, and the Go menu (⌘1–⌘5, ⌘F).
Tried and dropped: an app-wide sidebar in place of the top tab bar (the
glass tab bar is preferred).

- [x] **Settings in its own window.** Done: Streamen › Settings… (⌘,) opens
      a `Settings` scene with toolbar tabs (`MacSettingsView`). That scene
      centres its toolbar, so sub-pages use an in-page back button
      (`settingsBackButton()`) rather than one in the toolbar.
- [x] **Artwork under the glass.** Done by macOS itself: content already runs
      under the toolbar, which frosts it (the "scroll edge"), in a window and
      in full screen. Only the window title was hidden. Don't hide the toolbar
      background (`toolbarBackgroundVisibility(.hidden, for: .windowToolbar)`):
      it makes the band fully clear in a window but turns full screen into a
      solid grey bar.
- [x] **Playback menu.** Done: the player's shortcuts as a Playback menu,
      driven from the focused player window. Later: Audio / Subtitles track
      submenus and Picture in Picture.
- [x] **Glass player controls.** Done: on macOS every player uses one
      floating glass bar at the bottom (`MacPlayerControlBar`) with transport,
      scrubber and track controls, in place of the big centre buttons. iOS
      and tvOS keep their layout.
- [x] **New menu strings.** Done (2026-11-12): the Go menu's titles and 55
      other strings added since the last Xcode build are in
      `Localizable.xcstrings`.

## StreamenDVR: self-hosted downloads, no GitHub

Let users get the DVR from our own server instead of GitHub Releases and
ghcr.io.

- [ ] **Server.** Forgejo/Gitea (releases page + built-in container
      registry in one install), or Caddy/nginx for the download page plus
      `registry:2` for images. The registry needs real HTTPS: Docker, NAS
      apps and Apple Container refuse plain-HTTP registries.
- [ ] **Mac DMG.** `MacApp/scripts/build-app.sh` with the Developer ID
      certificate and `NOTARY_PROFILE` (signed and notarized), uploaded with a
      `.sha256` beside it.
- [ ] **One multi-arch image** (`linux/amd64,linux/arm64`, arm64 for Apple
      silicon and ARM NAS): `docker buildx build --platform
      linux/amd64,linux/arm64 -t <registry>/streamen-dvr:<version> -t
      <registry>/streamen-dvr:latest --push .`
- [ ] **Install docs per target.**
      - Linux / NAS compose: `image: <registry>/streamen-dvr:latest`, no
        `build:`, `network_mode: host` for Bonjour discovery (Synology
        Container Manager, Unraid, Portainer can add a custom registry).
      - Docker Desktop: the bridge-mode block (`ports: 8090:8090`,
        `BONJOUR=0`); added in Streamen by `<ip>:8090`.
      - Apple Container (`container` CLI, macOS 26): no compose; `container
        run -d --name streamen-dvr -p 8090:8090 -v ~/StreamenDVR:/data -e
        BONJOUR=0 <registry>/streamen-dvr:latest`, or the container's own IP
        from `container ls` if `-p` isn't available. Added by address.
      - Optional offline image: `docker save … | gzip`, `docker load`
        (no updates).
- [ ] **Repo changes.** README and `docker-compose.yml` still point at GitHub
      Releases and `ghcr.io/dustintinsley/streamen-dvr`; replace the GitHub
      Actions release with a local script (build + notarize DMG, push image,
      upload) or a Forgejo Actions runner.
- [ ] **ffmpeg licence.** The DMG bundles an LGPL ffmpeg and the image uses
      Ubuntu's (GPL) ffmpeg: publish the matching ffmpeg source, or a link to
      that exact version, on the download page.

## Before release: remove the screenshot debug features

Added (2026-11-14) to take App Store screenshots with made-up content; all
Debug-only, so Release builds never show them, but the code should go once
the screenshots are final.

- [ ] **Sports Hub screenshot demo.** Settings › Sports › Screenshot Demo
      and `SportsScreenshotDemoProvider` (`SportsScreenshotDemo.swift`), plus
      the Debug-only hooks it added in `SportsCatalog`, `SportsFollowService`,
      `SportsSyncService`, `SettingsView+Sports`, `SettingsView+TVComponents`,
      `GameDetailSheet`, `TVGameDetailSheet`, `LeagueDetailView`,
      `LeagueTeamsView` and `TVManageTeamsPane`. Commit 55da51ae added them
      all; reverting its hunks is the quickest route.
- [ ] **Check nothing else is left.** Search for `ScreenshotDemo` and review
      the other `#if DEBUG` blocks before the release build.
- [ ] **Outside the repo.** The `Screenshot Demo` folder (demo server,
      made-up playlist, crests, `frame.swift`) is not in git; keep it if
      the screenshots will be retaken, otherwise it can be deleted.
