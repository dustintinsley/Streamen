//
//  GuidePreviewTileHost.swift
//  Streamen
//
//  Keeps the tvOS Guide preview's video playing across category changes.
//  The Guide is rebuilt for every category, so a player living inside it was
//  torn down and reconnected on each one. The player lives here instead, one
//  level up on the Live TV screen: the Guide's hero only marks where the
//  picture goes and claims the channel it wants; a new Guide claiming the same
//  channel carries on with the running stream.
//

#if os(tvOS)
    import SwiftUI

    /// The channel the Guide's hero wants playing, and which hero asked.
    @MainActor @Observable
    final class GuidePreviewTileHost {
        struct Claim {
            /// The tile's identity: the channel and the restart token. A claim
            /// with the same key keeps the running player.
            let key: String
            let media: PlayableMedia
            let isMuted: Bool
            let handle: PreviewPlayerHandle?
            let owner: UUID
            let onFailure: () -> Void
        }

        private(set) var claim: Claim?
        /// The hero's video slot in `Self.space`, kept from the last hero that
        /// reported one so the picture holds still between Guides.
        var slotFrame: CGRect?
        /// The Live TV screen's coordinate space, which the layer is drawn in.
        static let space = "streamen.guidePreviewTileSpace"
        /// The pending release of a hero that went away.
        private var pendingRelease: Task<Void, Never>?

        /// How long a departed hero's channel keeps playing for the Guide that
        /// replaces it to claim it: a category's grid can take a moment to build.
        private static let handOverWindow: Duration = .seconds(3)

        func claim(_ claim: Claim) {
            pendingRelease?.cancel()
            self.claim = claim
        }

        /// The hero no longer plays anything (not allowed, failed, no stream).
        func release(owner: UUID) {
            guard claim?.owner == owner else { return }
            pendingRelease?.cancel()
            claim = nil
        }

        /// The hero left — most often for the next category's Guide, which
        /// claims the same channel within the window if it carries it over.
        func releaseLater(owner: UUID) {
            guard claim?.owner == owner else { return }
            pendingRelease?.cancel()
            pendingRelease = Task { @MainActor [weak self] in
                try? await Task.sleep(for: Self.handOverWindow)
                guard !Task.isCancelled, let self, self.claim?.owner == owner else { return }
                self.claim = nil
            }
        }
    }

    extension EnvironmentValues {
        /// Set by the Live TV screen for the Guide's hero.
        @Entry var guidePreviewTileHost: GuidePreviewTileHost?
    }

    /// The claimed channel's player, at the slot the hero last reported. A
    /// fixed child of the Live TV screen, behind its content (the hero's
    /// gradient and border draw on top), so nothing a category change rebuilds
    /// is above it.
    struct GuidePreviewTileLayer: View {
        let host: GuidePreviewTileHost
        let cornerRadius: CGFloat

        var body: some View {
            if let claim = host.claim, let frame = host.slotFrame {
                let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                ZStack {
                    Color.black
                    MultiViewTilePlayer(
                        media: claim.media,
                        isMuted: claim.isMuted,
                        role: .guidePreview(handle: claim.handle),
                        onFailure: claim.onFailure
                    )
                    .id(claim.key)
                }
                .frame(width: frame.width, height: frame.height)
                .clipShape(shape)
                .background { shape.fill(.black).shadow(color: .black.opacity(0.5), radius: 35, y: 30) }
                .offset(x: frame.minX, y: frame.minY)
                .allowsHitTesting(false)
            }
        }
    }
#endif
