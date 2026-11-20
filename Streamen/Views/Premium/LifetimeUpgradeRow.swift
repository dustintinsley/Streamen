//
//  LifetimeUpgradeRow.swift
//  Streamen
//
//  The way from the monthly plan to Lifetime. Once someone is Pro the paywall
//  never shows again, so without this a subscriber had no route to the
//  one-time unlock. Buying Lifetime does not cancel the subscription — Apple
//  doesn't link the two products — so once both are owned the row turns into
//  a reminder to cancel the monthly plan.
//

import StoreKit
import SwiftUI

extension PremiumManager {
    /// A monthly subscriber who hasn't bought Lifetime yet.
    var canUpgradeToLifetime: Bool {
        owns(.monthly) && !owns(.lifetime)
    }

    /// Lifetime is owned but the subscription is still renewing, so the user
    /// is being charged for nothing until they cancel it.
    var hasRedundantSubscription: Bool {
        owns(.lifetime) && hasManageableSubscription && subscriptionStatus?.willAutoRenew != false
    }
}

struct LifetimeUpgradeRow: View {
    @State private var premium = PremiumManager.shared

    var body: some View {
        if premium.canUpgradeToLifetime {
            upgradeButton
        } else if premium.hasRedundantSubscription {
            cancelReminder
        }
    }

    // MARK: - Upgrade

    private var upgradeButton: some View {
        Button {
            guard let product = premium.product(for: .lifetime) else { return }
            Task { await premium.purchase(product) }
        } label: {
            #if os(tvOS)
                Label(upgradeTitle, systemImage: "infinity")
            #else
                Label {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(upgradeTitle)
                            .foregroundStyle(.primary)
                        Text("Pay once and keep Pro for good. Cancel your monthly plan afterwards.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "infinity")
                        .foregroundStyle(.tint)
                }
            #endif
        }
        .disabled(premium.isWorking || premium.product(for: .lifetime) == nil)
        #if os(tvOS)
            .buttonStyle(TVSettingsActionButtonStyle(prominent: true))
        #endif
    }

    /// "Switch to Lifetime · $9.99", or without the price until products load.
    private var upgradeTitle: String {
        let title = String(localized: "Switch to Lifetime")
        guard let price = premium.product(for: .lifetime)?.displayPrice else { return title }
        return "\(title) · \(price)"
    }

    // MARK: - Reminder

    private var cancelReminder: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("Cancel your monthly plan")
                Text("You own Lifetime, but your monthly subscription is still set to renew. Cancel it in Manage Subscription so you aren't charged again.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    #if os(tvOS)
                    .font(.system(size: 20))
                    #else
                    .font(.caption)
                    #endif
            }
        }
        #if os(tvOS)
        .font(.system(size: 24, weight: .semibold))
        .padding(.horizontal, TVSettingsMetrics.rowHPadding)
        #endif
    }
}
