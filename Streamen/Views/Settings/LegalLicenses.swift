//
//  LegalLicenses.swift
//  Streamen
//
//  Settings › About › Legal & Licenses: the open-source players and media
//  stack the app ships with (KSPlayer, VLCKit, FFmpeg), each with its
//  licence and where its source lives. TMDB's credit stays in the About group itself (`TMDBAttribution`).
//  It is a screen of its own behind About, except in the Mac Settings
//  window, where it sits under About in the About tab; on Apple TV, which can't open a link,
//  it is read-only rows in the About pane.
//

import SwiftUI

/// The names, licences and links. Proper nouns and licence names are verbatim
/// data; the copy around them is localised in the views.
nonisolated enum LegalInfo {
    struct Component: Identifiable {
        let name: String
        let license: String
        let urlString: String

        var id: String {
            name
        }

        var url: URL? {
            URL(string: urlString)
        }

        /// Without the scheme, for display.
        var displayURL: String {
            urlString.replacingOccurrences(of: "https://", with: "")
        }
    }

    static let components: [Component] = [
        Component(name: "KSPlayer", license: "GPL v3", urlString: "https://github.com/kingslay/KSPlayer"),
        Component(name: "VLCKit", license: "LGPL v2.1", urlString: "https://code.videolan.org/videolan/VLCKit"),
        Component(name: "FFmpeg", license: "LGPL v2.1+ / GPL v3", urlString: "https://ffmpeg.org")
    ]
}

#if !os(tvOS)

    /// The licence sections, shown in their own screen and inline in the Mac
    /// Settings window's About tab.
    struct LegalLicensesSections: View {
        var body: some View {
            Section {
                ForEach(LegalInfo.components) { component in
                    LegalComponentRow(component: component)
                }
            } header: {
                Text("Open Source")
            } footer: {
                Text("Streamen's players are built on these open-source projects. Each remains under its own license, and its source code is available at the link shown. FFmpeg is a trademark of Fabrice Bellard.")
            }
        }
    }

    /// The sections as a screen of their own.
    struct LegalLicensesView: View {
        var body: some View {
            List {
                LegalLicensesSections()
            }
            .platformNavigationTitle("Legal & Licenses")
        }
    }

    private struct LegalComponentRow: View {
        let component: LegalInfo.Component

        var body: some View {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(verbatim: component.name)
                    Spacer()
                    Text(verbatim: component.license)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let url = component.url {
                    Link(destination: url) {
                        Text(verbatim: component.displayURL)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            .padding(.vertical, 1)
        }
    }

#else

    /// Apple TV: read-only rows, since the system can't open a link.
    struct TVLegalLicensesSection: View {
        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                TVSettingsSectionLabel("Legal & Licenses")
                VStack(spacing: 2) {
                    ForEach(LegalInfo.components) { component in
                        TVLegalRow(component: component)
                    }
                }
                Text("Streamen's players are built on these open-source projects. Each remains under its own license, with its source code at the address shown. FFmpeg is a trademark of Fabrice Bellard.")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, TVSettingsMetrics.rowHPadding)
            }
        }
    }

    private struct TVLegalRow: View {
        let component: LegalInfo.Component

        var body: some View {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: component.name)
                    Text(verbatim: component.displayURL)
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 16)
                Text(verbatim: component.license)
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: TVSettingsMetrics.rowFontSize))
            .padding(.horizontal, TVSettingsMetrics.rowHPadding)
            .padding(.vertical, TVSettingsMetrics.rowVPadding + 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: TVSettingsMetrics.rowCornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
        }
    }

#endif
