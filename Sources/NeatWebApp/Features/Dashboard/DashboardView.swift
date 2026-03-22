import AppKit
import SwiftUI

struct DashboardView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppModel.self) private var appModel

    var body: some View {
        ZStack {
            backgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    appsSection
                    screensSection
                    roadmapSection
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("NeatWebApp")
                .font(.system(size: 42, weight: .bold, design: .rounded))

            Text("A MenubarX-inspired macOS web app shell built on the system browser engine, with a notch-triggered launcher and content-first windows.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button("Reveal Launcher") {
                    appModel.revealLauncherManually()
                }
                .buttonStyle(.borderedProminent)

                Button("Refresh Geometry") {
                    appModel.refreshScreenState()
                }
                .buttonStyle(.bordered)

                Button(appModel.isNotchDebugOverlayVisible ? "Hide Debug Overlay" : "Show Debug Overlay") {
                    appModel.toggleNotchDebugOverlay()
                }
                .buttonStyle(.bordered)
            }

            Text(appModel.diagnosticsMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .background(primaryPanelBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(panelBorder, lineWidth: 1)
        }
    }

    private var appsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Starter Web Apps")
                .font(.title2.weight(.semibold))

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                ForEach(appModel.apps) { app in
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            WebAppIconView(
                                app: app,
                                size: 42,
                                cornerRadius: 13,
                                font: .system(size: 20, weight: .semibold)
                            )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.name)
                                    .font(.headline)
                                Text(app.shortDescription)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Text(app.homeURL.absoluteString)
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Button("Open Window") {
                            appModel.openWebApp(app)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(secondaryPanelBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(panelBorder, lineWidth: 1)
                    }
                }
            }
        }
    }

    private var screensSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Notch Diagnostics")
                .font(.title2.weight(.semibold))

            if appModel.detectedNotchScreens.isEmpty {
                Text("No notched screens are currently exposed by AppKit.")
                    .foregroundStyle(.secondary)
            } else {
                Text(appModel.isNotchDebugOverlayVisible ? "Debug overlay is visible on detected notched screens." : "Debug overlay is currently hidden.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                ForEach(appModel.detectedNotchScreens) { screen in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(screen.localizedName)
                            .font(.headline)

                        Text("notchRect: \(screen.notchRect.debugSummary)")
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)

                        Text("activationRect: \(screen.activationRect.debugSummary)")
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(secondaryPanelBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
        }
    }

    private var roadmapSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Scaffolded Next")
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                Text("1. Persist fetched favicons to disk so launcher icons are available instantly offline.")
                Text("2. Persist per-app permissions, last visited URL, and window restore state.")
                Text("3. Tune the notch trigger with a visual debug overlay and optional dead-zone settings.")
                Text("4. Add per-site user agents, menu bar presence, and app-bound permission rules.")
            }
            .foregroundStyle(.secondary)
        }
        .padding(20)
        .background(primaryPanelBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [backgroundBaseColor, backgroundAccentColor],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var backgroundBaseColor: Color {
        Color(nsColor: .windowBackgroundColor)
    }

    private var backgroundAccentColor: Color {
        let accent = colorScheme == .dark ? NSColor.underPageBackgroundColor : NSColor.controlBackgroundColor
        return Color(nsColor: accent)
    }

    private var primaryPanelBackground: Color {
        Color(nsColor: .controlBackgroundColor)
            .opacity(colorScheme == .dark ? 0.82 : 0.78)
    }

    private var secondaryPanelBackground: Color {
        Color(nsColor: .controlBackgroundColor)
            .opacity(colorScheme == .dark ? 0.9 : 0.86)
    }

    private var panelBorder: Color {
        Color(nsColor: .separatorColor)
            .opacity(colorScheme == .dark ? 0.4 : 0.22)
    }
}

private extension CGRect {
    var debugSummary: String {
        "[x:\(Int(origin.x)) y:\(Int(origin.y)) w:\(Int(width)) h:\(Int(height))]"
    }
}

#Preview {
    DashboardView()
        .environment(AppModel())
}
