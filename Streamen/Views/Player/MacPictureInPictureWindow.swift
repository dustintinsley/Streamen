//
//  MacPictureInPictureWindow.swift
//  Streamen
//
//  Hides the macOS player window while its video plays in Picture in Picture.
//
//  Once the video moves into the PiP panel the window behind it only shows
//  AVKit's "playing in Picture in Picture" placeholder, so it steps out of the
//  way and comes back when PiP ends (the panel's return button, the player's
//  own toggle, or its close button, which leaves the stream paused). With
//  "Hide App During Picture in Picture" on, the whole app hides with it.
//

import SwiftUI

#if os(macOS)
    import AppKit

    extension View {
        /// Order the player window out while `isActive`, and back in after.
        func hidesPlayerWindowDuringPictureInPicture(_ isActive: Bool) -> some View {
            modifier(PictureInPictureWindowHiding(isActive: isActive))
        }
    }

    private struct PictureInPictureWindowHiding: ViewModifier {
        let isActive: Bool

        /// Weak, so the window's own view tree does not keep it alive.
        @State private var host = WeakWindow()

        func body(content: Content) -> some View {
            content
                .background(MacWindowAccessor { host.window = $0 })
                .onChange(of: isActive) { _, active in
                    if active { host.hide() } else { host.restore() }
                }
        }
    }

    private final class WeakWindow {
        weak var window: NSWindow?
        private var isHidden = false
        private var hidAppToo = false

        func hide() {
            guard let window, window.isVisible else { return }
            // A full-screen window owns its Space: ordering it out would leave
            // an empty Space behind, so full screen keeps the placeholder.
            if !window.styleMask.contains(.fullScreen) {
                isHidden = true
                window.orderOut(nil)
            }
            // The viewer asked for only the PiP video to stay on screen.
            if PlayerSettings.Playback.hideAppDuringPip, !NSApp.isHidden {
                hidAppToo = true
                NSApp.hide(nil)
            }
        }

        func restore() {
            if hidAppToo {
                hidAppToo = false
                NSApp.unhide(nil)
            }
            guard isHidden, let window else { return }
            isHidden = false
            if window.isMiniaturized { window.deminiaturize(nil) }
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
        }
    }

#else

    extension View {
        /// No-op off macOS, where the player is not a window of its own.
        func hidesPlayerWindowDuringPictureInPicture(_: Bool) -> some View {
            self
        }
    }

#endif
