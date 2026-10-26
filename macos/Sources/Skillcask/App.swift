import AppKit
import SkillcaskCore
import SwiftUI

@main
struct SkillcaskApp: App {
    @State private var model = AppModel()

    init() {
        // Without a bundle (`swift run`) the process would start as a background app.
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup("skillcask") {
            ContentView().environment(model)
        }
        Settings { SettingsView() }
    }
}

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var importing = false

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: $model.scope) {
                Section("Personal") {
                    Label("Global (-g)", systemImage: "person").tag(AppModel.Scope.global)
                }
                Section("Projects") {
                    ForEach(model.recent, id: \.self) { path in
                        Label(URL(fileURLWithPath: path).lastPathComponent, systemImage: "folder")
                            .help(path)
                            .tag(AppModel.Scope.project(path))
                            .contextMenu { Button("Remove from List") { model.forget(path) } }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            .toolbar {
                Button("Open Project", systemImage: "folder.badge.plus") { importing = true }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result { model.open(url) }
            }
        } content: {
            SkillsView()
                .navigationSplitViewColumnWidth(min: 300, ideal: 380)
        } detail: {
            DetailView()
        }
        .task(id: model.scope) { await model.refresh() }
        .task(id: model.selected) { await model.loadInfo() }
    }
}

struct SkillsView: View {
    @Environment(AppModel.self) private var model
    @State private var adding = false

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            if let why = model.tooOld {
                ContentUnavailableView("Update skillcask", systemImage: "arrow.up.circle", description: Text(why))
            } else if model.scope == nil {
                ContentUnavailableView(
                    "Open a Project", systemImage: "folder",
                    description: Text("A folder with skills.toml, or Global for personal skills."))
            } else if model.needsInit {
                ContentUnavailableView {
                    Label("No skills.toml", systemImage: "doc.badge.plus")
                } actions: {
                    Button("Run skillcask init") { Task { await model.change(["init"]) } }
                }
            } else {
                List(model.status?.entries ?? [], id: \.self, selection: $model.selected) { entry in
                    EntryRow(entry: entry, update: entry.package.flatMap { model.outdated[$0] })
                }
            }
            OutputView()
        }
        .toolbar {
            if model.busy > 0 { ProgressView().controlSize(.small) }
            Button("Install", systemImage: "square.and.arrow.down") { Task { await model.change(["install"]) } }
            Button("Add", systemImage: "plus") { adding = true }
            Button("Doctor", systemImage: "stethoscope") { Task { await model.runDoctor() } }
            Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.refresh() } }
        }
        .disabled(model.scope == nil)
        .sheet(isPresented: $adding) { AddView() }
        .sheet(isPresented: Binding(get: { model.doctor != nil }, set: { if !$0 { model.doctor = nil } })) {
            DoctorView()
        }
    }
}

struct EntryRow: View {
    let entry: StatusDoc.Entry
    let update: OutdatedDoc.Package?

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(entry.skill ?? entry.package ?? "-").bold()
                Text([entry.package, entry.version].compactMap { $0 }.joined(separator: " "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let latest = update?.within ?? update?.latest, latest != update?.locked {
                Text("↑ \(latest)").font(.caption).foregroundStyle(.blue).help(update?.note ?? "")
            }
            Text(entry.state).font(.caption)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(entry.ok ? Color.green.opacity(0.2) : Color.red.opacity(0.25), in: Capsule())
        }
    }
}

struct DetailView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmRemove = false

    var body: some View {
        if let entry = model.selected, entry.state == "not managed" {
            AdoptView(entry: entry).id(entry)
        } else if let entry = model.selected {
            Form {
                if let info = model.info { InfoSection(info: info) } else { ProgressView() }
                if let u = entry.package.flatMap({ model.outdated[$0] }) {
                    Section("Updates") {
                        LabeledContent("Locked", value: u.locked ?? "-")
                        LabeledContent("Within constraint", value: u.within ?? "-")
                        LabeledContent("Latest", value: u.latest ?? "-")
                        if let note = u.note { Text(note).foregroundStyle(.secondary) }
                    }
                }
                if let package = entry.package {
                    Section {
                        HStack {
                            Button("Update \(package)") { Task { await model.change(["update", package]) } }
                            Button("Remove…", role: .destructive) { confirmRemove = true }
                        }
                    }
                    .confirmationDialog("Remove \(package)?", isPresented: $confirmRemove) {
                        Button("Remove", role: .destructive) { Task { await model.change(["remove", package]) } }
                    } message: {
                        Text("Drops it from skills.toml and skills.lock and deletes its files and links.")
                    }
                }
            }
            .formStyle(.grouped)
        } else {
            ContentUnavailableView("Select a Skill", systemImage: "sidebar.right")
        }
    }
}

/// A global skill another tool installed (D38): `add --adopt` moves it to
/// ~/.config/skillcask/adopted/ and installs the package's skill in its place.
struct AdoptView: View {
    @Environment(AppModel.self) private var model
    let entry: StatusDoc.Entry
    @State private var source = ""

    var body: some View {
        Form {
            Section(entry.skill ?? "") {
                Text("Not managed by skillcask. Adopting moves it to ~/.config/skillcask/adopted/ and installs the skill from a package instead.")
                    .foregroundStyle(.secondary)
                TextField("Source", text: $source, prompt: Text("github:owner/repo/\(entry.skill ?? "skill"), vendor/name or git:https://…"))
                Button("Adopt") { Task { await model.change(["add", "--adopt", source.trimmingCharacters(in: .whitespaces)]) } }
                    .disabled(source.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .formStyle(.grouped)
        .onAppear { source = entry.adopt ?? "" }
    }
}

struct InfoSection: View {
    let info: InfoDoc

    var body: some View {
        Section(info.package ?? info.skill ?? "") {
            row("Kind", info.kind)
            row("Version", info.version.map { $0 + (info.locked == true ? " (locked)" : "") })
            row("Source", info.source)
            row("Repository", info.repository)
            row("Path", info.path)
            row("From", info.from)
            row("License", info.license?.joined(separator: ", "))
            if let a = info.abandoned {
                row("Abandoned", a.replacement.map { "use \($0) instead" } ?? "yes")
            }
            if let d = info.description { Text(d) }
        }
        if let skills = info.skills, !skills.isEmpty {
            Section("Skills") {
                ForEach(skills, id: \.name) { s in
                    VStack(alignment: .leading) {
                        Text(s.name).bold()
                        if let d = s.description { Text(d).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
        }
        if let req = info.requires, !req.isEmpty {
            Section("Requires") {
                ForEach(req.sorted(by: { $0.key < $1.key }), id: \.key) { LabeledContent($0.key, value: $0.value) }
            }
        }
        if let why = info.why, !why.isEmpty {
            Section("Why") { ForEach(why, id: \.self) { Text($0) } }
        }
        if let v = info.versions, !v.isEmpty {
            Section("Versions") { Text(v.prefix(20).joined(separator: ", ") + (v.count > 20 ? " and \(v.count - 20) more" : "")) }
        }
    }

    @ViewBuilder private func row(_ label: String, _ value: String?) -> some View {
        if let value { LabeledContent(label, value: value) }
    }
}

struct AddView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading) {
            Text("Add a Package").font(.headline)
            HStack {
                TextField("Search, or vendor/name, github:owner/repo, git:https://…", text: $query)
                    .onSubmit { Task { await model.search(query) } }
                Button("Search") { Task { await model.search(query) } }
                Button("Add as Typed") { add(query) }.disabled(query.isEmpty)
            }
            List(model.searchResults, id: \.self) { r in
                HStack {
                    VStack(alignment: .leading) {
                        Text(r.name).bold()
                        if let d = r.description { Text(d).font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    Button("Add") { add(r.name) }
                }
            }
            .frame(minHeight: 240)
            HStack {
                if model.busy > 0 { ProgressView().controlSize(.small) }
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding()
        .frame(minWidth: 560)
    }

    private func add(_ spec: String) {
        dismiss()
        Task { await model.change(["add", spec.trimmingCharacters(in: .whitespaces)]) }
    }
}

struct DoctorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading) {
            if let d = model.doctor {
                Label(d.ok ? "No problems" : "\(d.problems.count) problem(s)", systemImage: d.ok ? "checkmark.seal" : "exclamationmark.triangle")
                    .font(.headline)
                List {
                    lines(d.problems, "xmark.circle", .red)
                    lines(d.warnings, "exclamationmark.triangle", .orange)
                    lines(d.fixed, "wrench", .blue)
                    lines(d.passed, "checkmark.circle", .green)
                }
                .frame(minHeight: 240)
            }
            HStack {
                Button("Fix") { Task { await model.runDoctor(fix: true) } }.disabled(model.doctor?.ok ?? true)
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding()
        .frame(minWidth: 560)
    }

    private func lines(_ items: [String], _ icon: String, _ color: Color) -> some View {
        ForEach(items, id: \.self) { Label($0, systemImage: icon).foregroundStyle(color) }
    }
}

struct OutputView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let r = model.last {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("$ \(r.command)").monospaced()
                    Spacer()
                    Text("exit \(r.status)").foregroundStyle(r.ok ? Color.secondary : Color.red)
                    Button("Dismiss", systemImage: "xmark") { model.last = nil }.labelStyle(.iconOnly).buttonStyle(.borderless)
                }
                .font(.caption)
                ScrollView {
                    Text(r.output).monospaced().font(.caption).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 140)
            }
            .padding(8)
            .background(r.ok ? Color.secondary.opacity(0.1) : Color.red.opacity(0.12))
        }
    }
}

struct SettingsView: View {
    @AppStorage("skillcaskPath") private var path = ""

    var body: some View {
        Form {
            TextField("skillcask binary", text: $path, prompt: Text("found on PATH"))
            LabeledContent("Using", value: CLI.locate(configured: path)?.path ?? "not found")
        }
        .padding()
        .frame(width: 480)
    }
}
