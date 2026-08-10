import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 主窗口：网页应用管理与应用设置合在同一个窗口里，没有独立的设置窗口。
struct DashboardView: View {
    @Environment(AppModel.self) private var appModel

    @State private var editorTarget: WebAppEditorTarget?
    @State private var appToDelete: WebAppDefinition?
    @State private var draggedApp: WebAppDefinition?
    @State private var hoveredAppID: String?
    @FocusState private var focusedAppID: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                appsSection
                SettingsSectionView()
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(width: 520, height: 620)
        .focusEffectDisabled()
        .sheet(item: $editorTarget) { target in
            WebAppEditorSheet(appModel: appModel, target: target)
        }
        .alert(
            "删除「\(appToDelete?.name ?? "")」？",
            isPresented: Binding(
                get: { appToDelete != nil },
                set: { if !$0 { appToDelete = nil } }
            )
        ) {
            Button("删除", role: .destructive) {
                if let appToDelete {
                    appModel.deleteCustomApp(appToDelete)
                }
                appToDelete = nil
            }
            Button("取消", role: .cancel) {
                appToDelete = nil
            }
        }
    }

    private var appsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("网页应用")
                    .panelSectionTitle()

                Spacer()

                Button {
                    editorTarget = .new
                } label: {
                    Label("添加", systemImage: "plus")
                }
                .controlSize(.small)
                .focusEffectDisabled()
                .accessibilityLabel("添加网页应用")
            }

            VStack(spacing: 0) {
                ForEach(appModel.apps) { app in
                    if app.id != appModel.apps.first?.id {
                        Divider()
                            .padding(.leading, 50)
                    }

                    appRow(for: app)
                }
            }
            .panelCard()
        }
    }

    private func appRow(for app: WebAppDefinition) -> some View {
        let isHovered = hoveredAppID == app.id
        let isFocused = focusedAppID == app.id

        return HStack(spacing: 12) {
            WebAppIconView(
                app: app,
                size: 24,
                font: .system(size: 12, weight: .semibold)
            )

            VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                Text(app.homeURL.host ?? app.homeURL.absoluteString)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            // 操作按钮只在指针移到该行时出现，静态列表保持干净。
            HStack(spacing: 4) {
                Button("打开") {
                    appModel.openWebApp(app)
                }
                .controlSize(.small)
                .focusEffectDisabled()

                Menu {
                    Button("编辑…") {
                        editorTarget = .existing(app)
                    }

                    Divider()

                    Button("删除", role: .destructive) {
                        appToDelete = app
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 18)
                .focusEffectDisabled()
            }
            .opacity(isHovered || isFocused ? 1 : 0)
            .allowsHitTesting(isHovered || isFocused)
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .contentShape(Rectangle())
        .background((isHovered || isFocused) ? Color.primary.opacity(0.05) : Color.clear)
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(isFocused ? 0.7 : 0), lineWidth: 2)
        }
        .focusable()
        .focused($focusedAppID, equals: app.id)
        .focusEffectDisabled()
        .onKeyPress(.return) {
            appModel.openWebApp(app)
            return .handled
        }
        .accessibilityLabel("\(app.name)，\(app.homeURL.host ?? app.homeURL.absoluteString)")
        .accessibilityHint("按下回车打开网页应用")
        .accessibilityAction {
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
            return NSItemProvider(object: app.id as NSString)
        }
        .onDrop(
            of: [.text],
            delegate: AppDropDelegate(
                item: app,
                items: appModel.apps,
                draggedItem: $draggedApp,
                appModel: appModel
            )
        )
        .contextMenu {
            Button("打开") {
                appModel.openWebApp(app)
            }

            Button("编辑…") {
                editorTarget = .existing(app)
            }

            Divider()

            Button("删除", role: .destructive) {
                appToDelete = app
            }
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
        ("WebAppAccentBlue", "蓝色", .blue),
        ("WebAppAccentGreen", "绿色", .green),
        ("WebAppAccentOrange", "橙色", .orange),
        ("WebAppAccentRed", "红色", .red),
        ("WebAppAccentPurple", "紫色", .indigo),
        ("WebAppAccentGray", "灰色", .gray)
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
        VStack(alignment: .leading, spacing: 16) {
            Text(isEditing ? "编辑网页应用" : "添加网页应用")
                .font(.system(size: 15, weight: .semibold))

            textField("网址", prompt: "example.com", text: $urlString, field: .url)
                .onChange(of: urlString) { _, newValue in
                    guard !hasEditedName else {
                        return
                    }

                    name = Self.suggestedName(from: newValue)
                }

            textField("名称", prompt: "显示在启动器中的名称", text: $name, field: .name)
                .onChange(of: name) { _, _ in
                    if focusedField == .name {
                        hasEditedName = true
                    }
                }

            VStack(alignment: .leading, spacing: 8) {
                Text("底色")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach(Self.accentColors, id: \.name) { item in
                        Button {
                            accentColorName = item.name
                        } label: {
                            Circle()
                                .fill(item.color)
                                .frame(width: 20, height: 20)
                                .overlay {
                                    if accentColorName == item.name {
                                        Circle()
                                            .stroke(.white, lineWidth: 2)
                                            .frame(width: 14, height: 14)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .help(item.label)
                    }
                }
            }

            HStack {
                Spacer()

                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(isEditing ? "保存" : "添加") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 360)
        .focusEffectDisabled()
        .onAppear {
            // 新增时直接把光标放到网址框；编辑时不抢焦点，避免一打开就选中已有内容。
            if !isEditing {
                focusedField = .url
            }
        }
    }

    private func textField(
        _ title: String,
        prompt: String,
        text: Binding<String>,
        field: Field
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            TextField(prompt, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($focusedField, equals: field)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(
                    Color(nsColor: .textBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
                // 系统焦点框已关闭，这里补一套克制的自绘焦点态，保证键盘操作仍看得见焦点。
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(
                            focusedField == field
                            ? Color.accentColor.opacity(0.8)
                            : Color(nsColor: .separatorColor),
                            lineWidth: focusedField == field ? 2 : 1
                        )
                }
        }
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
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedItem = nil
        return true
    }
}

#Preview {
    DashboardView()
        .environment(AppModel())
}
