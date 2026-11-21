import SwiftUI
import FreeTurnKit
import UniformTypeIdentifiers

extension AppModel {
    /// Имена встроенных профилей переводятся; свои показываются как есть.
    func displayName(_ profile: RoutingProfile) -> String {
        switch profile.id {
        case Presets.allViaVPN.id: L("Всё через VPN")
        case Presets.russiaDirect.id: L("Российские сервисы напрямую")
        default: profile.name
        }
    }
}

struct RoutingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.compactLayout) private var compact
    @State private var selectedId: String?
    @State private var transferError: String?
    /// Узкая раскладка: профиль открыт отдельным экраном.
    @State private var opened = false

    var body: some View {
        Group {
            if compact { compactBody } else { wideBody }
        }
        .toolbar {
            // Разделы живут скрытыми (см. RootView): кнопки панели - только у видимого.
            if model.section == .routing {
                ToolbarItem {
                    Menu {
                        Button(L("Новый профиль"), systemImage: "plus") {
                            let profile = RoutingProfile(name: L("Новый профиль"), defaultAction: .vpn, rules: [])
                            model.routing.add(profile)
                            model.persist()
                            selectedId = profile.id
                        }
                        Button(L("Импорт из файла…"), systemImage: "square.and.arrow.down") { importProfile() }
                    } label: {
                        Label(L("Добавить профиль"), systemImage: "plus")
                    }
                }
            }
        }
        .onAppear { if selectedId == nil { selectedId = model.activeProfile?.id ?? model.routing.sharedProfileId } }
        .alert(L("Не удалось"), isPresented: Binding(get: { transferError != nil }, set: { if !$0 { transferError = nil } })) {
            Button(L("Понятно"), role: .cancel) {}
        } message: {
            Text(transferError ?? "")
        }
    }

    /// Узкая раскладка: список профилей на всю ширину, редактор - отдельным экраном.
    @ViewBuilder private var compactBody: some View {
        if opened, let id = selectedId, let profile = model.routing.profiles.first(where: { $0.id == id }) {
            VStack(spacing: 0) {
                CompactBackBar(title: model.displayName(profile)) { opened = false }
                ProfileEditor(profileId: id, selectedId: $selectedId, transferError: $transferError)
            }
        } else {
            List {
                ForEach(model.routing.profiles) { profile in
                    Button {
                        selectedId = profile.id
                        opened = true
                    } label: {
                        HStack {
                            profileRow(profile)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden)
                }
            }
        }
    }

    private func profileRow(_ profile: RoutingProfile) -> some View {
        HStack(alignment: .top) {
            Image(systemName: profile.builtIn ? "lock" : "arrow.triangle.branch")
                .foregroundStyle(.secondary).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.displayName(profile))
                if profile.id == model.routing.sharedProfileId {
                    Text(L("По умолчанию")).font(.caption).foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 3)
    }

    private var wideBody: some View {
        HStack(spacing: 0) {
            List(selection: $selectedId) {
                ForEach(model.routing.profiles) { profile in
                    profileRow(profile)
                    .tag(profile.id)
                    .listRowSeparator(.hidden)
                }
            }
            .frame(width: 250)

            Divider()

            Group {
                if let id = selectedId, model.routing.profiles.contains(where: { $0.id == id }) {
                    ProfileEditor(profileId: id, selectedId: $selectedId, transferError: $transferError)
                } else {
                    ContentUnavailableView(L("Выберите профиль"), systemImage: "arrow.triangle.branch")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func importProfile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let profile = try ProfileTransfer.importProfile(Data(contentsOf: url))
            model.routing.add(profile)
            model.persist()
            selectedId = profile.id
        } catch ProfileTransferError.unsupportedVersion {
            transferError = L("Файл создан более новой версией приложения.")
        } catch {
            transferError = L("Это не файл профиля маршрутов FreeTurn.")
        }
    }
}

private struct ProfileEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.compactLayout) private var compact
    let profileId: String
    @Binding var selectedId: String?
    @Binding var transferError: String?
    @State private var editing: RoutingRule?

    private var profile: RoutingProfile {
        model.routing.profiles.first { $0.id == profileId } ?? Presets.allViaVPN
    }

    private func mutate(_ change: (inout RoutingProfile) -> Void) {
        var copy = profile
        change(&copy)
        model.routing.update(copy)
        model.persist()
    }

    var body: some View {
        @Bindable var model = model
        let profile = profile
        VStack(alignment: .leading, spacing: 12) {
            if profile.builtIn {
                Label(L("Встроенный профиль нельзя менять. Клонируйте его, чтобы настроить под себя."), systemImage: "lock")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                TextField(L("Название профиля"), text: Binding(get: { profile.name }, set: { name in mutate { $0.name = name } }))
                    .textFieldStyle(.roundedBorder)
            }

            if compact {
                // Узкая раскладка: режим - списком, действия с профилем - в одном меню.
                HStack {
                    Picker(L("Режим"), selection: Binding(get: { profile.defaultAction }, set: { action in mutate { $0.defaultAction = action } })) {
                        Text(L("Всё через VPN, кроме выбранного")).tag(RouteAction.vpn)
                        Text(L("Только выбранное через VPN")).tag(RouteAction.direct)
                    }
                    .labelsHidden()
                    .disabled(profile.builtIn)
                    Menu {
                        Button(L("Сделать профилем по умолчанию")) { model.routing.sharedProfileId = profileId; model.persist() }
                            .disabled(model.routing.sharedProfileId == profileId)
                        Button(L("Клонировать")) {
                            if let copy = model.routing.clone(id: profileId) { model.persist(); selectedId = copy.id }
                        }
                        Button(L("Экспорт…")) { export(profile) }
                        if !profile.builtIn {
                            Divider()
                            Button(L("Удалить"), role: .destructive) {
                                model.routing.remove(id: profileId)
                                model.persist()
                                selectedId = model.routing.sharedProfileId
                            }
                        }
                    } label: {
                        Label(L("Действия"), systemImage: "ellipsis.circle")
                    }
                    .fixedSize()
                }
            } else {
            Picker(L("Режим"), selection: Binding(get: { profile.defaultAction }, set: { action in mutate { $0.defaultAction = action } })) {
                Text(L("Всё через VPN, кроме выбранного")).tag(RouteAction.vpn)
                Text(L("Только выбранное через VPN")).tag(RouteAction.direct)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(profile.builtIn)

            HStack {
                Button(L("Сделать профилем по умолчанию")) { model.routing.sharedProfileId = profileId; model.persist() }
                    .fixedSize()
                    .disabled(model.routing.sharedProfileId == profileId)
                    .help(L("Профиль по умолчанию применяется к серверам, для которых не выбран отдельный профиль."))
                Button(L("Клонировать")) {
                    if let copy = model.routing.clone(id: profileId) { model.persist(); selectedId = copy.id }
                }
                Button(L("Экспорт…")) { export(profile) }
                Spacer()
                if !profile.builtIn {
                    Button(L("Удалить"), role: .destructive) {
                        model.routing.remove(id: profileId)
                        model.persist()
                        selectedId = model.routing.sharedProfileId
                    }
                }
            }
            }

            if profile.rules.isEmpty {
                ContentUnavailableView(L("Правил нет"), systemImage: "list.bullet",
                                       description: Text(L("Весь трафик идёт по режиму профиля.")))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(profile.rules) { rule in
                        RuleRow(rule: rule, locked: profile.builtIn,
                                onToggle: { on in mutate { p in p.rules[index(of: rule, in: p)].enabled = on } },
                                onAction: { action in mutate { p in p.rules[index(of: rule, in: p)].action = action } },
                                onEdit: { editing = rule })
                    }
                    .onMove { from, to in mutate { $0.rules.move(fromOffsets: from, toOffset: to) } }
                    .onDelete { offsets in mutate { $0.rules.remove(atOffsets: offsets) } }
                    .moveDisabled(profile.builtIn)
                    .deleteDisabled(profile.builtIn)
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                Button(L("Добавить правило"), systemImage: "plus") {
                    editing = RoutingRule(kind: .app, value: "", action: profile.defaultAction == .vpn ? .direct : .vpn)
                }
                .disabled(profile.builtIn)
                Spacer()
                Picker(compact ? L("Стек") : L("Тип туннеля"), selection: $model.settings.tunStack) {
                    Text("mixed").tag("mixed")
                    Text("system").tag("system")
                    Text("gvisor").tag("gvisor")
                }
                .fixedSize()
                .onChange(of: model.settings.tunStack) { model.persist() }
            }

            if model.connection.state.isActive {
                HStack {
                    Label(L("Изменения применятся при следующем подключении."), systemImage: "info.circle")
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button(L("Переподключить")) {
                        Task {
                            await model.connection.disconnect()
                            await model.connect()
                        }
                    }
                }
            }
        }
        .padding(16)
        .sheet(item: $editing) { rule in
            RuleEditorView(rule: rule) { saved in
                mutate { profile in
                    if let index = profile.rules.firstIndex(where: { $0.id == saved.id }) {
                        profile.rules[index] = saved
                    } else {
                        profile.rules.insert(saved, at: 0)
                    }
                }
            }
        }
    }

    private func index(of rule: RoutingRule, in profile: RoutingProfile) -> Int {
        profile.rules.firstIndex { $0.id == rule.id } ?? 0
    }

    private func export(_ profile: RoutingProfile) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = model.displayName(profile) + ".json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ProfileTransfer.export(profile).write(to: url)
        } catch {
            transferError = error.localizedDescription
        }
    }
}

private struct RuleRow: View {
    let rule: RoutingRule
    let locked: Bool
    let onToggle: (Bool) -> Void
    let onAction: (RouteAction) -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { rule.enabled }, set: { onToggle($0) })).labelsHidden()
            Image(systemName: rule.kind.icon).foregroundStyle(.secondary).frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(rule.kind == .app ? URL(fileURLWithPath: rule.value).deletingPathExtension().lastPathComponent : rule.value)
                Text(rule.kind == .app ? rule.value : rule.kind.title)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            if !EngineConfig.isValid(rule) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            }
            Picker("", selection: Binding(get: { rule.action }, set: { onAction($0) })) {
                ForEach(RouteAction.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            Button(L("Изменить"), systemImage: "pencil", action: onEdit).labelStyle(.iconOnly).buttonStyle(.borderless)
        }
        .opacity(rule.enabled ? 1 : 0.5)
        .disabled(locked)
    }
}
