import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DashboardView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppModel.self) private var appModel

    @State private var isAddSheetPresented = false
    @State private var appToDelete: WebAppDefinition?
    @State private var draggedApp: WebAppDefinition?

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

            VStack(spacing: 12) {
                ForEach(appModel.apps) { app in
                    appListItem(for: app)
                }
            }
        }
    }

    private func appListItem(for app: WebAppDefinition) -> some View {
        HStack(spacing: 16) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .imageScale(.large)
                .frame(width: 24)

            WebAppIconView(
                app: app,
                size: 32,
                font: .system(size: 16, weight: .semibold)
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.headline)
                Text(app.shortDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()

            Text(app.homeURL.host ?? app.homeURL.absoluteString)
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Button("Open Window") {
                appModel.openWebApp(app)
            }
            .buttonStyle(.borderedProminent)

            Button {
                appToDelete = app
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Delete this web app")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(secondaryPanelBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(panelBorder, lineWidth: 1)
        }
        .onDrag {
            self.draggedApp = app
            return NSItemProvider(object: app.id as NSString)
        }
        .onDrop(of: [.text], delegate: AppDropDelegate(item: app, items: appModel.apps, draggedItem: $draggedApp, appModel: appModel))
        .contextMenu {
            Button("Open Window") {
                appModel.openWebApp(app)
            }
            Divider()
            Button("Delete", role: .destructive) {
                appToDelete = app
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

                        Text("launcherRetentionRect: \(screen.launcherRetentionRect.debugSummary)")
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
            Text("Planned Improvements")
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                Text("1. Expand import and export support for user-managed web app catalogs.")
                Text("2. Persist more per-site state, including permissions, last visited URL, and richer window restore details.")
                Text("3. Refine notch-trigger behavior with better non-notched fallback handling and stronger diagnostics.")
                Text("4. Add more per-site controls, such as custom user agents and tighter permission rules.")
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

private struct AppDropDelegate: DropDelegate {
    let item: WebAppDefinition
    let items: [WebAppDefinition]
    @Binding var draggedItem: WebAppDefinition?
    let appModel: AppModel

    func dropEntered(info: DropInfo) {
        guard let draggedItem,
              draggedItem.id != item.id,
              let from = items.firstIndex(of: draggedItem),
              let to = items.firstIndex(of: item) else {
            return
        }

        if from != to {
            var indexSet = IndexSet()
            indexSet.insert(from)
            let destination = to > from ? to + 1 : to
            withAnimation(.default) {
                appModel.moveCustomApps(from: indexSet, to: destination)
            }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedItem = nil
        return true
    }
}
