import AppKit
import SwiftUI

struct DashboardView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppModel.self) private var appModel

    @State private var isAddSheetPresented = false
    @State private var appToDelete: WebAppDefinition?

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
        .sheet(isPresented: $isAddSheetPresented) {
            AddWebAppSheet(appModel: appModel)
        }
        .alert(
            "Delete \(appToDelete?.name ?? "")?",
            isPresented: Binding(
                get: { appToDelete != nil },
                set: { if !$0 { appToDelete = nil } }
            )
        ) {
            Button("Delete", role: .destructive) {
                if let app = appToDelete {
                    appModel.deleteCustomApp(app)
                }
                appToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                appToDelete = nil
            }
        } message: {
            Text("This web app will be removed from the list.")
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
            HStack {
                Text("Web Apps")
                    .font(.title2.weight(.semibold))

                Spacer()

                Button {
                    isAddSheetPresented = true
                } label: {
                    Label("Add Web App", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                ForEach(appModel.apps) { app in
                    appCard(for: app)
                }
            }
        }
    }

    private func appCard(for app: WebAppDefinition) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                WebAppIconView(
                    app: app,
                    size: 42,
                    font: .system(size: 20, weight: .semibold)
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name)
                        .font(.headline)
                    Text(app.shortDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if appModel.canDeleteApp(app) {
                    Button {
                        appToDelete = app
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Delete this web app")
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
        .contextMenu {
            Button("Open Window") {
                appModel.openWebApp(app)
            }

            if appModel.canDeleteApp(app) {
                Divider()
                Button("Delete", role: .destructive) {
                    appToDelete = app
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

// MARK: - Add Web App Sheet

private struct AddWebAppSheet: View {
    let appModel: AppModel

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var urlString = ""
    @State private var shortDescription = ""
    @State private var selectedAccentColor = "WebAppAccentBlue"

    private static let accentColors: [(name: String, label: String, color: Color)] = [
        ("WebAppAccentBlue", "Blue", .blue),
        ("WebAppAccentGreen", "Green", .green),
        ("WebAppAccentOrange", "Orange", .orange),
        ("WebAppAccentRed", "Red", .red),
        ("WebAppAccentPurple", "Purple", .indigo),
        ("WebAppAccentGray", "Gray", .gray)
    ]

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
        && resolvedURL != nil
    }

    private var resolvedURL: URL? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }

        return URL(string: "https://\(trimmed)")
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add Web App")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Divider()

            // Form
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Name")
                        .font(.subheadline.weight(.medium))
                    TextField("e.g. YouTube", text: $name)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("URL")
                        .font(.subheadline.weight(.medium))
                    TextField("e.g. youtube.com", text: $urlString)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Description")
                        .font(.subheadline.weight(.medium))
                    TextField("Short description (optional)", text: $shortDescription)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Accent Color")
                        .font(.subheadline.weight(.medium))

                    HStack(spacing: 8) {
                        ForEach(Self.accentColors, id: \.name) { item in
                            Button {
                                selectedAccentColor = item.name
                            } label: {
                                Circle()
                                    .fill(item.color)
                                    .frame(width: 24, height: 24)
                                    .overlay {
                                        if selectedAccentColor == item.name {
                                            Circle()
                                                .stroke(.white, lineWidth: 2)
                                                .frame(width: 18, height: 18)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .help(item.label)
                        }
                    }
                }
            }
            .padding(20)

            Divider()

            // Actions
            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Add") {
                    addApp()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
            .padding(20)
        }
        .frame(width: 400)
    }

    private func addApp() {
        guard let url = resolvedURL else {
            return
        }

        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let id = trimmedName.lowercased().replacingOccurrences(of: " ", with: "_")
            + "_" + String(Int(Date().timeIntervalSince1970))

        let description = shortDescription.trimmingCharacters(in: .whitespaces)

        let app = WebAppDefinition(
            id: id,
            name: trimmedName,
            homeURL: url,
            accentColorName: selectedAccentColor,
            shortDescription: description.isEmpty ? url.host ?? "Custom app" : description
        )

        appModel.addCustomApp(app)
        dismiss()
    }
}

#Preview {
    DashboardView()
        .environment(AppModel())
}
