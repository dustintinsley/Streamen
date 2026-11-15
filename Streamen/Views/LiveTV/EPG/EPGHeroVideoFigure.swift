//
//  EPGHeroVideoFigure.swift
//  Streamen
//
//  The tvOS Guide hero's 16:9 picture: the settled channel playing (muted
//  unless Settings › Live TV › Preview Sound is on), or,
//  while it may not play, the channel's logo on a card tinted with it.
//

#if os(tvOS)
    import SwiftUI

    struct EPGHeroVideoFigure: View {
        let target: EPGPreviewTarget?
        let isAllowed: Bool
        let isFailed: Bool
        let restartToken: Int
        let handle: PreviewPlayerHandle?
        /// Read only by the placeholder card, for the settled channel's tint.
        let hero: GuideHeroModel?
        let onFailure: () -> Void

        private let metrics = EPGMetrics.current
        @Environment(\.epgHeroLayout) private var layout
        /// Runs the player outside the Guide when the Live TV screen offers it
        /// (see `GuidePreviewTileHost`); this figure then only marks the slot.
        @Environment(\.guidePreviewTileHost) private var tileHost
        @AppStorage(PlayerSettings.tvGuidePreviewSoundKey)
        private var playsSound = PlayerSettings.tvGuidePreviewSoundDefault
        /// This figure's claims on the host, told apart from the next Guide's.
        @State private var claimOwner = UUID()

        private var shape: RoundedRectangle {
            RoundedRectangle(cornerRadius: metrics.previewVideoCornerRadius, style: .continuous)
        }

        var body: some View {
            ZStack(alignment: .bottom) {
                content

                LinearGradient(colors: [.black.opacity(0), .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                    .frame(height: layout.height / 3)
            }
            .frame(width: layout.videoWidth, height: layout.height)
            .clipShape(shape)
            .overlay { shape.strokeBorder(.white.opacity(0.18), lineWidth: 1) }
            .background {
                // The hosted player draws its own plate behind the slot.
                if !isHostedPlaying {
                    shape.fill(.black).shadow(color: .black.opacity(0.5), radius: 35, y: 30)
                }
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(GuidePreviewTileHost.space)) } action: { frame in
                if tileHost?.slotFrame != frame { tileHost?.slotFrame = frame }
            }
            .onChange(of: claimKey, initial: true) { _, _ in
                updateClaim()
            }
            .onDisappear {
                tileHost?.releaseLater(owner: claimOwner)
            }
        }

        /// The stream this figure should be showing, if any.
        private var playingMedia: PlayableMedia? {
            guard let target, !isFailed, isAllowed else { return nil }
            return target.media
        }

        private var isHostedPlaying: Bool {
            tileHost != nil && playingMedia != nil
        }

        /// Changes whenever the claim must: another channel, a restart, sound.
        private var claimKey: String? {
            guard let target, playingMedia != nil else { return nil }
            return "\(target.streamID)-\(restartToken)-\(playsSound)"
        }

        private func updateClaim() {
            guard let tileHost else { return }
            guard let target, let media = playingMedia else {
                tileHost.release(owner: claimOwner)
                return
            }
            tileHost.claim(GuidePreviewTileHost.Claim(
                key: "\(target.streamID)-\(restartToken)",
                media: media,
                isMuted: !playsSound,
                handle: handle,
                owner: claimOwner,
                onFailure: onFailure
            ))
        }

        @ViewBuilder
        private var content: some View {
            if tileHost != nil, playingMedia != nil {
                // The host's player shows through from behind.
                Color.clear
            } else if let target, !isFailed, isAllowed, let media = target.media {
                ZStack {
                    Color.black
                    MultiViewTilePlayer(
                        media: media,
                        isMuted: !playsSound,
                        role: .guidePreview(handle: handle),
                        onFailure: onFailure
                    )
                    .id("\(target.streamID)-\(restartToken)")
                }
            } else {
                EPGHeroPlaceholderCard(
                    logoURL: target?.logoURL,
                    isUnavailable: isFailed && target != nil,
                    hero: hero
                )
            }
        }
    }

    /// The video slot when nothing plays: never empty, so the hero keeps its
    /// shape and the settle `.task` above it keeps running.
    private struct EPGHeroPlaceholderCard: View {
        let logoURL: URL?
        let isUnavailable: Bool
        let hero: GuideHeroModel?

        @Environment(\.epgHeroLayout) private var layout

        private var tint: Color {
            hero?.glowTint ?? LiveTVPalette.accent
        }

        /// A third of the hero's height: 120 pt regular, about 67 pt small.
        private var logoSide: CGFloat {
            layout.height / 3
        }

        var body: some View {
            ZStack {
                Color(red: 13 / 255, green: 16 / 255, blue: 24 / 255)
                LinearGradient(
                    colors: [tint.opacity(0.42), tint.opacity(0.12)],
                    startPoint: .topTrailing,
                    endPoint: .bottomLeading
                )
                .animation(.easeInOut(duration: 0.6), value: tint)

                if isUnavailable {
                    LiveChannelUnavailableBadge(logoURL: logoURL, logoSide: logoSide)
                } else {
                    LiveChannelLogoPlaceholder(url: logoURL, side: logoSide)
                }
            }
        }
    }
#endif
