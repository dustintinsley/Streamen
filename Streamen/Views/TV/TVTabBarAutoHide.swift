//
//  TVTabBarAutoHide.swift
//  Streamen
//
//  Fades the tvOS tab bar out whenever focus is anywhere but the bar, and
//  back in the moment focus reaches it. Faded rather than hidden: the bar
//  stays in the layout and focusable, so Up from a screen's top row and Menu
//  from its top level still land on it the way they always have.
//
//  While it's faded, the tabs' content slides up into the room it leaves:
//  each tab's top safe-area inset gives back the bar's height, and takes it
//  again as the bar fades in.
//

#if os(tvOS)
    import SwiftUI
    import UIKit

    @MainActor
    final class TVTabBarAutoHider {
        static let shared = TVTabBarAutoHider()

        /// Low enough to read as gone, above the 0.01 below which UIKit stops
        /// treating a view as visible and the focus engine skips it.
        private static let fadedAlpha: CGFloat = 0.011
        private static let fadeDuration: TimeInterval = 0.25

        private weak var tabBar: UITabBar?
        /// How far the content moves up while the bar is faded: the bar's share
        /// of a tab's top safe-area inset, measured while it shows.
        private var barInset: CGFloat = 0
        private var observer: NSObjectProtocol?

        func start() {
            guard observer == nil else { return }
            observer = NotificationCenter.default.addObserver(
                forName: UIFocusSystem.didUpdateNotification,
                object: nil,
                queue: .main
            ) { [weak self] note in
                let context = note.userInfo?[UIFocusSystem.focusUpdateContextUserInfoKey] as? UIFocusUpdateContext
                let next = context?.nextFocusedItem
                MainActor.assumeIsolated {
                    self?.focusDidMove(to: next)
                }
            }
        }

        /// SwiftUI content reports its focus items as plain `UIFocusItem`s,
        /// not views; only the tab bar's own buttons are views inside it.
        private func focusDidMove(to item: UIFocusItem?) {
            guard item != nil, let window = Self.keyWindow, let tabBar = tabBar(in: window) else { return }
            let inTabBar = (item as? UIView)?.isDescendant(of: tabBar) ?? false
            let target: CGFloat = inTabBar ? 1 : Self.fadedAlpha
            let controller = Self.tabBarController(of: tabBar)
            let children = controller?.viewControllers ?? []
            if inTabBar || barInset == 0 {
                measureBarInset(children: children, window: window)
            }
            let topAdjustment = inTabBar ? 0 : -barInset
            let needsShift = children.contains { $0.additionalSafeAreaInsets.top != topAdjustment }
            guard tabBar.alpha != target || needsShift else { return }
            UIView.animate(withDuration: Self.fadeDuration, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                tabBar.alpha = target
                for child in children where child.additionalSafeAreaInsets.top != topAdjustment {
                    child.additionalSafeAreaInsets.top = topAdjustment
                }
                controller?.view.layoutIfNeeded()
            }
        }

        /// The bar's part of the selected tab's top inset: what's left once
        /// the screen's own (overscan) inset and any shift already applied
        /// are taken out.
        private func measureBarInset(children: [UIViewController], window: UIWindow) {
            guard let child = children.first(where: { $0.viewIfLoaded?.window != nil }) else { return }
            let inset = child.view.safeAreaInsets.top - child.additionalSafeAreaInsets.top - window.safeAreaInsets.top
            if inset > 0 { barInset = inset }
        }

        private static func tabBarController(of tabBar: UITabBar) -> UITabBarController? {
            var responder: UIResponder? = tabBar
            while let next = responder?.next {
                if let controller = next as? UITabBarController { return controller }
                responder = next
            }
            return nil
        }

        private static var keyWindow: UIWindow? {
            UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow }
                .first
        }

        /// The root tab bar, found once per window and kept weakly.
        private func tabBar(in window: UIWindow) -> UITabBar? {
            if let tabBar, tabBar.window === window { return tabBar }
            let found = Self.firstTabBar(under: window)
            tabBar = found
            return found
        }

        private static func firstTabBar(under view: UIView) -> UITabBar? {
            if let tabBar = view as? UITabBar { return tabBar }
            for subview in view.subviews {
                if let tabBar = firstTabBar(under: subview) { return tabBar }
            }
            return nil
        }
    }

    extension View {
        /// Starts the tab bar's auto-hide (see `TVTabBarAutoHider`). Idempotent,
        /// so every tab's content can carry it.
        func tvAutoHidingTabBar() -> some View {
            onAppear { TVTabBarAutoHider.shared.start() }
        }
    }
#endif
