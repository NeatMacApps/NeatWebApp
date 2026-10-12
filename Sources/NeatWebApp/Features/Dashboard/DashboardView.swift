import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Main window: web app management and app settings share one window as native tab panes.
/// There is no separate Settings scene; menu bar, launcher Add and ⌘, all open this window.
struct DashboardView: View {
    @AppStorage(DashboardPane.storageKey) private var selectedPane: DashboardPane = .webApps

    var body: some View {
        TabView(selection: $selectedPane) {
            Tab("dashboard.section_title", systemImage: "square.grid.2x2", value: DashboardPane.webApps) {
                WebAppsPane()
            }

            Tab("settings.pane.general", systemImage: "gearshape", value: DashboardPane.general) {
                GeneralSettingsPane()
            }
        }
        .frame(width: DashboardLayout.width)
        // The window (content-size resizability) follows the current pane's height.
        .fixedSize(horizontal: false, vertical: true)
        .focusEffectDisabled()
    }
}

/// Panes of the main window. The raw value is persisted so the window reopens on the last pane.
enum DashboardPane: String {
    case webApps
    case general

    static let storageKey = "dashboard.selectedPane"
}

private enum DashboardLayout {
    static let width: CGFloat = 480
    /// Beyond this height the web app list scrolls inside its pane instead of growing the window.
    static let webAppsMaxHeight: CGFloat = 560
}

/// "Web Apps" pane: the user's catalog. The list is the only region allowed to scroll,
/// and only once it outgrows the maximum pane height.
private struct WebAppsPane: View {
    @Environment(AppModel.self) private var appModel

    @State private var editorTarget: WebAppEditorTarget?
    @State private var appToDelete: WebAppDefinition?
    @State private var hoveredAppID: String?
    @State private var draggedApp: WebAppDefinition?
    @State private var dropTargetID: String?

    var body: some View {
        Form {
            Section {
                // Reordering uses drag and drop rather than `onMove`, which grouped forms do not support.
                // The move is applied and persisted once on drop; cancelled drags change nothing.
                ForEach(appModel.apps) { app in
                    appRow(for: app)
                }
            } footer: {
                // Both actions belong to the launcher's content, so they sit on the list itself.
                HStack {
                    Button("settings.reveal_launcher.action") {
                        appModel.revealLauncherManually()
                    }

                    Spacer()

                    Button {
                        editorTarget = .new
                    } label: {
                        Label("dashboard.add_accessibility", systemImage: "plus")
                    }
                }
            }
        }
        .settingsPaneStyle(maxHeight: DashboardLayout.webAppsMaxHeight)
        .sheet(item: $editorTarget) { target in
            WebAppEditorSheet(appModel: appModel, target: target)
        }
        .alert(
            String(format: String(localized: "dashboard.delete_title_format"), appToDelete?.name ?? ""),
            isPresented: Binding(
                get: { appToDelete != nil },
                set: { if !$0 { appToDelete = nil } }
            )
        ) {
            Button(String(localized: "dashboard.delete"), role: .destructive) {
                if let appToDelete {
                    appModel.deleteCustomApp(appToDelete)
                }
                appToDelete = nil
            }
            Button(String(localized: "dashboard.cancel"), role: .cancel) {
                appToDelete = nil
            }
        }
    }

    private func appRow(for app: WebAppDefinition) -> some View {
        let host = app.homeURL.host ?? app.homeURL.absoluteString
        let showsActions = hoveredAppID == app.id && draggedApp == nil
        let isDropTarget = dropTargetID == app.id && draggedApp?.id != app.id

        return HStack(spacing: 10) {
            // Visible drag grip: the whole row drags, the grip makes that discoverable.
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .help(String(localized: "dashboard.drag_help"))
                .accessibilityLabel(String(format: String(localized: "dashboard.drag_accessibility_format"), app.name))

            WebAppIconView(
                app: app,
                size: 24,
                font: .system(size: 12, weight: .semibold),
                favicon: appModel.faviconImage(for: app),
                loadFavicon: { appModel.ensureFaviconLoaded(for: app) }
            )

            VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                    .lineLimit(1)

                Text(host)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            // Row actions appear on hover so the resting list stays quiet; the context menu
            // and double-click offer the same actions at any time.
            HStack(spacing: 6) {
                Button(String(localized: "dashboard.open")) {
                    appModel.openWebApp(app)
                }

                Menu {
                    rowMenuItems(for: app)
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .opacity(showsActions ? 1 : 0)
            .allowsHitTesting(showsActions)
        }
        .contentShape(Rectangle())
        // While dragging, a single insertion line marks the destination without moving rows.
        .overlay(alignment: .top) {
            if isDropTarget {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
                    .offset(y: -7)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(format: String(localized: "dashboard.row_accessibility_format"), app.name, host))
        .accessibilityAction(named: Text("dashboard.open")) {
            appModel.openWebApp(app)
        }
        .onHover { isInside in
            if isInside {
                hoveredAppID = app.id
            } else if hoveredAppID == app.id {
                hoveredAppID = nil
            }
        }
        .onTapGesture(count: 2) {
            appModel.openWebApp(app)
        }
        .onDrag {
            draggedApp = app
            dropTargetID = nil
            return NSItemProvider(object: app.id as NSString)
        } preview: {
            // Only the icon and name travel with the pointer, not the whole row and its actions.
            Label {
                Text(app.name)
            } icon: {
                WebAppIconView(
                    app: app,
                    size: 24,
                    font: .system(size: 12, weight: .semibold),
                    favicon: appModel.faviconImage(for: app),
                    loadFavicon: {}
                )
            }
            .padding(6)
        }
        .onDrop(
            of: [.text],
            delegate: AppDropDelegate(
                item: app,
                items: appModel.apps,
                draggedItem: $draggedApp,
                dropTargetID: $dropTargetID,
                appModel: appModel
            )
        )
        .contextMenu {
            Button(String(localized: "dashboard.open")) {
                appModel.openWebApp(app)
            }

            rowMenuItems(for: app)
        }
    }

    @ViewBuilder
    private func rowMenuItems(for app: WebAppDefinition) -> some View {
        Button(String(localized: "dashboard.edit")) {
            editorTarget = .existing(app)
        }

        Divider()

        Button(String(localized: "dashboard.delete"), role: .destructive) {
            appToDelete = app
        }
    }
}

// MARK: - 编辑弹窗

/// 新增与编辑共用一个弹窗，两者的字段完全一致。
enum WebAppEditorTarget: Identifiable {
    case new
    case existing(WebAppDefinition)

    var id: String {
        switch self {
        case .new:
            "new"
        case .existing(let app):
            app.id
        }
    }
}

private struct WebAppEditorSheet: View {
    let appModel: AppModel
    let target: WebAppEditorTarget

    @Environment(\.dismiss) private var dismiss

    @FocusState private var focusedField: Field?

    @State private var urlString: String
    @State private var name: String
    @State private var accentColorName: String
    /// 名称被手动改过之后就不再跟着网址自动填充。
    @State private var hasEditedName: Bool

    private enum Field {
        case url
        case name
    }

    private static let accentColors: [(name: String, label: String, color: Color)] = [
        ("WebAppAccentBlue", String(localized: "dashboard.accent.blue"), .blue),
        ("WebAppAccentGreen", String(localized: "dashboard.accent.green"), .green),
        ("WebAppAccentOrange", String(localized: "dashboard.accent.orange"), .orange),
        ("WebAppAccentRed", String(localized: "dashboard.accent.red"), .red),
        ("WebAppAccentPurple", String(localized: "dashboard.accent.purple"), .indigo),
        ("WebAppAccentGray", String(localized: "dashboard.accent.gray"), .gray)
    ]

    init(appModel: AppModel, target: WebAppEditorTarget) {
        self.appModel = appModel
        self.target = target

        switch target {
        case .new:
            _urlString = State(initialValue: "")
            _name = State(initialValue: "")
            _accentColorName = State(initialValue: "WebAppAccentBlue")
            _hasEditedName = State(initialValue: false)
        case .existing(let app):
            _urlString = State(initialValue: app.homeURL.absoluteString)
            _name = State(initialValue: app.name)
            _accentColorName = State(initialValue: app.accentColorName)
            _hasEditedName = State(initialValue: true)
        }
    }

    private var isEditing: Bool {
        if case .existing = target {
            return true
        }

        return false
    }

    private var resolvedURL: URL? {
        WebAppURLInputResolver.resolve(urlString)
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && resolvedURL != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField(String(localized: "dashboard.field_url"), text: $urlString, prompt: Text(verbatim: "example.com"))
                        .focused($focusedField, equals: .url)
                        .onChange(of: urlString) { _, newValue in
                            guard !hasEditedName else {
                                return
                            }

                            name = Self.suggestedName(from: newValue)
                        }

                    TextField(String(localized: "dashboard.field_name"), text: $name, prompt: Text("dashboard.field_name_prompt"))
                        .focused($focusedField, equals: .name)
                        .onChange(of: name) { _, _ in
                            if focusedField == .name {
                                hasEditedName = true
                            }
                        }

                    LabeledContent(String(localized: "dashboard.accent_title")) {
                        HStack(spacing: 8) {
                            ForEach(Self.accentColors, id: \.name) { item in
                                accentSwatch(item)
                            }
                        }
                    }
                } header: {
                    Text(isEditing ? String(localized: "dashboard.editor_title_edit") : String(localized: "dashboard.add_accessibility"))
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()

                Button(String(localized: "dashboard.cancel")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(isEditing ? String(localized: "dashboard.save") : String(localized: "dashboard.add")) {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 420)
        .focusEffectDisabled()
        .onAppear {
            // Put the cursor in the URL field when adding; editing does not grab focus,
            // so existing content is not selected on open.
            if !isEditing {
                focusedField = .url
            }
        }
    }

    private func accentSwatch(_ item: (name: String, label: String, color: Color)) -> some View {
        Button {
            accentColorName = item.name
        } label: {
            Circle()
                .fill(item.color)
                .frame(width: 18, height: 18)
                .overlay {
                    if accentColorName == item.name {
                        Circle()
                            .stroke(.white, lineWidth: 2)
                            .frame(width: 12, height: 12)
                    }
                }
        }
        .buttonStyle(.plain)
        .help(item.label)
        .accessibilityLabel(item.label)
        .accessibilityAddTraits(accentColorName == item.name ? .isSelected : [])
    }

    private func save() {
        guard let resolvedURL else {
            return
        }

        let trimmedName = name.trimmingCharacters(in: .whitespaces)

        switch target {
        case .new:
            let id = trimmedName.lowercased().replacingOccurrences(of: " ", with: "_")
                + "_" + String(Int(Date().timeIntervalSince1970))

            appModel.addCustomApp(
                WebAppDefinition(
                    id: id,
                    name: trimmedName,
                    homeURL: resolvedURL,
                    accentColorName: accentColorName,
                    shortDescription: resolvedURL.host ?? trimmedName
                )
            )
        case .existing(let app):
            appModel.updateWebApp(
                app,
                name: trimmedName,
                homeURL: resolvedURL,
                accentColorName: accentColorName
            )
        }

        dismiss()
    }

    /// 从网址推导默认名称，省去手动输入：取主域名并首字母大写。
    private static func suggestedName(from urlString: String) -> String {
        guard let host = WebAppURLInputResolver.resolve(urlString)?.host else {
            return ""
        }

        let components = host
            .replacingOccurrences(of: "www.", with: "")
            .split(separator: ".")

        guard let mainComponent = components.first else {
            return ""
        }

        return mainComponent.prefix(1).uppercased() + String(mainComponent.dropFirst())
    }
}

enum WebAppURLInputResolver {
    static func resolve(_ input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }

        return URL(string: "https://\(trimmed)")
    }
}

private struct AppDropDelegate: DropDelegate {
    let item: WebAppDefinition
    let items: [WebAppDefinition]
    @Binding var draggedItem: WebAppDefinition?
    @Binding var dropTargetID: String?
    let appModel: AppModel

    /// 拖过时只记「准备放到哪一行前面」，不改数组、不写盘、不刷新运行时。
    /// 真正换位和持久化只在松手那一刻做一次；中途取消则什么都不发生。
    func dropEntered(info: DropInfo) {
        guard let draggedItem,
              draggedItem.id != item.id,
              items.contains(where: { $0.id == draggedItem.id }),
              items.contains(where: { $0.id == item.id }) else {
            return
        }

        dropTargetID = item.id
    }

    func dropExited(info: DropInfo) {
        if dropTargetID == item.id {
            dropTargetID = nil
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            draggedItem = nil
            dropTargetID = nil
        }

        guard let draggedItem,
              draggedItem.id != item.id,
              let from = items.firstIndex(of: draggedItem),
              let to = items.firstIndex(of: item) else {
            return false
        }

        // 无变化的松手不写盘：避免一次空拖也触发保存和运行时刷新。
        guard from != to else {
            return true
        }

        var indexSet = IndexSet()
        indexSet.insert(from)
        let destination = to > from ? to + 1 : to
        withAnimation(.default) {
            appModel.moveCustomApps(from: indexSet, to: destination)
        }
        return true
    }
}

#Preview {
    DashboardView()
        .environment(AppModel())
        .environmentObject(AppUpdater {})
}
