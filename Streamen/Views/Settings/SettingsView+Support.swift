//
//  SettingsView+Support.swift
//  Streamen
//
//  Help & Feedback and About. On iOS / macOS they are the last two groups of
//  the root list: the support links (website, email) are tappable rows that
//  open Safari / Mail, next to the diagnostic report; on tvOS they are sidebar
//  panes, where — since the system can't open a URL — the website and email
//  are read-only rows. Links live in SupportInfo so both surfaces stay in sync.
//

import SwiftUI

#if !os(tvOS)

    /// The root list's Help & Feedback group: the support links, then the
    /// diagnostic report.
    struct HelpFeedbackSection: View {
        var body: some View {
            Section {
                if let url = SupportInfo.websiteURL {
                    Link(destination: url) {
                        Label("Website", systemImage: "globe")
                    }
                }
                if let url = SupportInfo.emailURL {
                    Link(destination: url) {
                        Label("Email", systemImage: "envelope")
                    }
                }
                if let url = SupportInfo.appStoreReviewURL {
                    Link(destination: url) {
                        Label("Rate Streamen", systemImage: "star")
                    }
                }
                NavigationLink {
                    DebugSettingsView()
                } label: {
                    Label("Send Diagnostic Report", systemImage: "stethoscope")
                }
            } header: {
                Text("Help & Feedback")
            }
        }
    }

    /// The root list's About group: app identity, TMDB's credit and the link to
    /// Legal & Licenses.
    struct AboutSection: View {
        /// Off in the Mac Settings window's About tab, which lists the
        /// licences right under this group.
        var showsLegalLink = true

        var body: some View {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "play.tv.fill")
                        .font(.title2)
                        .foregroundStyle(.tint)
                        .frame(width: 28, height: 28)
                        .background(.tint.opacity(0.1), in: .rect(cornerRadius: 6))

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Streamen")
                        Text("Version \(SupportInfo.appVersion)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }

                if let url = SupportInfo.tmdbURL {
                    Link(destination: url) {
                        HStack(spacing: 12) {
                            Label("The Movie Database (TMDB)", systemImage: "film")
                            Spacer(minLength: 8)
                            TMDBAttribution.logo(height: 12)
                        }
                    }
                }

                if showsLegalLink {
                    NavigationLink {
                        LegalLicensesView()
                    } label: {
                        Label("Legal & Licenses", systemImage: "doc.text")
                    }
                }
            } header: {
                Text("About")
            } footer: {
                Text(TMDBAttribution.notice)
            }
        }
    }

#endif

/// The credit TMDB's API terms ask every app using the API to show.
enum TMDBAttribution {
    static let notice: LocalizedStringKey = "Movie and series details and artwork come from The Movie Database. This product uses the TMDB API but is not endorsed or certified by TMDB."

    /// TMDB's own logo, unaltered (`TMDBLogo` in the asset catalog, from
    /// themoviedb.org/about/logos-attribution), kept smaller than Streamen's
    /// own branding. Decorative: the row beside it names TMDB.
    static func logo(height: CGFloat) -> some View {
        Image("TMDBLogo")
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .accessibilityHidden(true)
    }
}

extension SettingsView {
    #if os(tvOS)
        /// tvOS Help & Feedback section. Apple TV can't open a URL, so the website
        /// and the support address are read-only rows.
        var tvSupportSection: some View {
            VStack(alignment: .leading, spacing: 16) {
                TVSettingsSectionLabel("Support")

                VStack(spacing: 2) {
                    TVSettingsValueRow("Website", value: SupportInfo.websiteDisplay)
                    TVSettingsValueRow("Email", value: SupportInfo.email)
                }
            }
        }
    #endif
}
