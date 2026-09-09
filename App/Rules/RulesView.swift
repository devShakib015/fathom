import SwiftUI

/// Rules: what Fathom watches for, and what it does about it.
///
/// The condition shows what it evaluates to right now and there is a button to
/// fire it deliberately, because a rule you cannot test is one you have to
/// trust — and trusting an alert that has never once gone off is how people end
/// up believing a broken rule is working.
struct RulesView: View {
    @Environment(RuleEngine.self) private var engine
    @State private var selection: UUID?

    private var selected: Rule? { engine.rules.first { $0.id == selection } }

    var body: some View {
        HSplitView {
            list.frame(minWidth: 200, idealWidth: 230, maxWidth: 320)
            detail.frame(minWidth: 380)
        }
        .background(Palette.background)
        .task { await engine.refreshNotificationPermission() }
    }

    private var list: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                Section("Rules") {
                    ForEach(engine.rules) { rule in
                        RuleRow(rule: rule, result: engine.lastResult[rule.id])
                            .tag(rule.id)
                            .contextMenu {
                                Button("Delete", role: .destructive) { engine.remove(rule.id) }
                            }
                    }
                }
            }
            .listStyle(.sidebar)

            Divider().overlay(Palette.hairline)
            Button {
                selection = engine.add().id
            } label: {
                Label("New rule", systemImage: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        }
        .background(Palette.background)
    }

    @ViewBuilder
    private var detail: some View {
        if let selected {
            RuleEditor(rule: selected)
        } else {
            ContentUnavailableView(
                "No rule selected",
                systemImage: "bell.badge",
                description: Text("A rule watches your data and does something when a condition holds — a notification, an overlay appearing, a sound."))
                .background(Palette.background)
        }
    }
}

private struct RuleRow: View {
    let rule: Rule
    let result: Bool?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: rule.isEnabled ? "bell" : "bell.slash")
                .foregroundStyle(rule.isEnabled ? Palette.accent : Palette.textDim)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(rule.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(rule.condition)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Palette.textDim)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let result {
                Circle()
                    .fill(result ? Palette.accent : Palette.textDim.opacity(0.4))
                    .frame(width: 6, height: 6)
                    .help(result ? "True at the last check" : "False at the last check")
            }
        }
        .padding(.vertical, 2)
    }
}

private struct RuleEditor: View {
    @Environment(RuleEngine.self) private var engine
    @Environment(OverlayController.self) private var overlays
    let rule: Rule

    @State private var liveResult: Bool?
    @State private var justFired = false

    private func edit(_ change: (inout Rule) -> Void) {
        var copy = rule
        change(&copy)
        engine.update(copy)
    }

    private var problem: String? {
        do { _ = try ExpressionParser.parse(rule.condition); return nil }
        catch { return error.localizedDescription }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                Divider().overlay(Palette.hairline)
                InspectorSection(title: "Condition") { condition }
                Divider().overlay(Palette.hairline)
                InspectorSection(title: "When it fires") { timing }
                Divider().overlay(Palette.hairline)
                InspectorSection(title: "Then") { actions }
            }
        }
        .background(Palette.background)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { rule.isEnabled }, set: { on in edit { $0.isEnabled = on } }))
                .labelsHidden().toggleStyle(.switch).controlSize(.small)
            TextField("Name", text: Binding(get: { rule.name }, set: { new in edit { $0.name = new } }))
                .textFieldStyle(.plain)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Palette.text)
            Spacer()
            Button {
                Task {
                    justFired = true
                    _ = await engine.check(rule)
                    try? await Task.sleep(for: .seconds(2))
                    justFired = false
                }
            } label: {
                Label(justFired ? "Fired" : "Test it", systemImage: justFired ? "checkmark" : "play")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Runs the actions now, ignoring the trigger and the cooldown")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var condition: some View {
        TextField("disk.usedFraction > 0.9", text: Binding(
            get: { rule.condition }, set: { new in edit { $0.condition = new } }), axis: .vertical)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 12, design: .monospaced))
            .lineLimit(1...4)

        if let problem {
            Label(problem, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 10)).foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            HStack(spacing: 8) {
                let result = liveResult ?? engine.lastResult[rule.id]
                Image(systemName: result == true ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(result == true ? Palette.accent : Palette.textDim)
                Text(result == nil ? "Not checked yet"
                     : result! ? "True right now" : "False right now")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(result == true ? Palette.text : Palette.textDim)
                Spacer()
                Button("Check") {
                    Task { liveResult = await engine.check(rule, dryRun: true) }
                }
                .buttonStyle(.borderless)
                .font(.system(size: 10))
                .foregroundStyle(Palette.accent)
            }
            .padding(8)
            .background(Palette.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 7))
        }

        Menu {
            ForEach(Self.recipes, id: \.condition) { recipe in
                Button(recipe.label) { edit { $0.condition = recipe.condition } }
            }
        } label: {
            Label("Examples", systemImage: "function").font(.system(size: 10))
        }
        .menuStyle(.borderlessButton)

        if !rule.declaredHosts.isEmpty {
            Label("Checks \(rule.declaredHosts.joined(separator: ", ")) every \(Int(rule.checkEvery)) s",
                  systemImage: "globe")
                .font(.system(size: 10)).foregroundStyle(Palette.accentAlt)
        }
    }

    @ViewBuilder
    private var timing: some View {
        InspectorRow(label: "Trigger") {
            Picker("", selection: Binding(get: { rule.trigger },
                                          set: { t in edit { $0.trigger = t } })) {
                ForEach(Rule.Trigger.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .labelsHidden()
        }
        Text(rule.trigger.explanation)
            .font(.system(size: 10)).foregroundStyle(Palette.textDim)
            .padding(.leading, 70)

        InspectorRow(label: "Check every") {
            NumberField(label: "Seconds", value: Binding(get: { rule.checkEvery },
                                                         set: { v in edit { $0.checkEvery = v } }),
                        range: Rule.minimumInterval...86400, step: 5, format: "%.0f")
            Text("seconds").font(.system(size: 10)).foregroundStyle(Palette.textDim)
        }

        InspectorRow(label: "Then wait") {
            NumberField(label: "Cooldown", value: Binding(get: { rule.cooldown },
                                                          set: { v in edit { $0.cooldown = v } }),
                        range: 0...86400, step: 30, format: "%.0f")
            Text("seconds").font(.system(size: 10)).foregroundStyle(Palette.textDim)
        }
        Text("A condition sitting on its threshold would otherwise fire on every check, which is how a useful alert becomes one you switch off.")
            .font(.system(size: 10)).foregroundStyle(Palette.textDim.opacity(0.85))
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var actions: some View {
        if rule.actions.contains(where: { $0.kind == .notify }), !engine.notificationsAllowed {
            HStack(spacing: 8) {
                Label("Notifications are not allowed yet", systemImage: "bell.slash")
                    .font(.system(size: 11)).foregroundStyle(.orange)
                Button("Allow") { Task { await engine.requestNotificationPermission() } }
                    .buttonStyle(.bordered).controlSize(.small)
            }
        }

        ForEach(rule.actions) { action in
            ActionEditor(action: action,
                         overlays: overlays.overlays,
                         onChange: { updated in
                             edit { copy in
                                 if let i = copy.actions.firstIndex(where: { $0.id == updated.id }) {
                                     copy.actions[i] = updated
                                 }
                             }
                         },
                         onRemove: { edit { $0.actions.removeAll { $0.id == action.id } } })
            if action.id != rule.actions.last?.id {
                Divider().overlay(Palette.hairline).padding(.vertical, 3)
            }
        }

        Menu {
            ForEach(RuleAction.Kind.allCases, id: \.self) { kind in
                Button(kind.displayName) {
                    edit { $0.actions.append(RuleAction(kind: kind)) }
                }
            }
        } label: {
            Label("Add something to do", systemImage: "plus").font(.system(size: 11))
        }
        .menuStyle(.borderlessButton)
        .frame(width: 190)
    }

    private static let recipes: [(label: String, condition: String)] = [
        ("Disk nearly full", "disk.usedFraction > 0.9"),
        ("Battery low and unplugged", "battery.percent < 0.2 && !battery.isCharging"),
        ("Battery charged", "battery.percent > 0.95 && battery.isCharging"),
        ("Memory under pressure", "memory.usedFraction > 0.85"),
        ("The Mac is working hard", "cpu.usage > 0.8"),
        ("Running hot", "system.thermal != \"nominal\""),
        ("Up for more than a week", "system.uptime > 604800"),
        ("Something is due", "authorised && count > 0"),
    ]
}

private struct ActionEditor: View {
    let action: RuleAction
    let overlays: [Overlay]
    var onChange: (RuleAction) -> Void
    var onRemove: () -> Void

    private func edit(_ change: (inout RuleAction) -> Void) {
        var copy = action
        change(&copy)
        onChange(copy)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: action.kind.symbol).foregroundStyle(Palette.accent).frame(width: 16)
                Picker("", selection: Binding(get: { action.kind },
                                              set: { k in edit { $0.kind = k } })) {
                    ForEach(RuleAction.Kind.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .labelsHidden()
                Button { onRemove() } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless).foregroundStyle(Palette.textDim)
            }

            switch action.kind {
            case .notify:
                TextField("Title", text: Binding(get: { action.primary },
                                                 set: { v in edit { $0.primary = v } }))
                    .textFieldStyle(.roundedBorder).font(.system(size: 11))
                TextField("Body — {bytes(disk.free)} left", text: Binding(
                    get: { action.secondary }, set: { v in edit { $0.secondary = v } }))
                    .textFieldStyle(.roundedBorder).font(.system(size: 11))
                Text("Anything in braces is an expression, so an alert can carry the number that caused it.")
                    .font(.system(size: 9)).foregroundStyle(Palette.textDim.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)

            case .showOverlay, .hideOverlay:
                if overlays.isEmpty {
                    Text("No overlays yet. Put one on screen from a widget's Design tab first.")
                        .font(.system(size: 10)).foregroundStyle(Palette.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Picker("", selection: Binding(get: { action.overlayID ?? overlays[0].id },
                                                  set: { id in edit { $0.overlayID = id } })) {
                        ForEach(overlays) { overlay in
                            Text("\(Int(overlay.width))×\(Int(overlay.height)) · \(overlay.level.displayName)")
                                .tag(overlay.id)
                        }
                    }
                    .labelsHidden()
                }

            case .openURL, .openApp, .revealPath, .runShortcut:
                TextField(placeholder(for: action.kind), text: Binding(
                    get: { action.primary }, set: { v in edit { $0.primary = v } }))
                    .textFieldStyle(.roundedBorder).font(.system(size: 11, design: .monospaced))
                Text("Braces work here too, so a link can carry the value that fired the rule. Links open in your browser; only http and https are allowed.")
                    .font(.system(size: 9)).foregroundStyle(Palette.textDim.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)

            case .playSound:
                Picker("", selection: Binding(get: { action.primary.isEmpty ? "Submarine" : action.primary },
                                              set: { v in edit { $0.primary = v } })) {
                    ForEach(RuleEngine.soundNames, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
            }
        }
    }

    private func placeholder(for kind: RuleAction.Kind) -> String {
        switch kind {
        case .openURL: "https://example.com/{value}"
        case .openApp: "Calendar"
        case .revealPath: "~/Documents"
        case .runShortcut: "Start my day"
        default: ""
        }
    }
}
