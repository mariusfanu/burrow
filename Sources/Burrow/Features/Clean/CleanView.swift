import BurrowCore
import SwiftUI

/// One continuous page: the results fill in during the scan and are already in place when it
/// ends, so there's no jump between scanning and reviewing.
struct CleanView: View {
    @Bindable var model: CleanModel
    let cli: CLIInfo
    @Environment(AppModel.self) private var app

    var body: some View {
        ZStack {
            switch model.state {
            case .idle:
                CleanIntro(model: model, cli: cli)
                    .transition(Motion.materialize)
            case .scanning, .review:
                CleanReportView(model: model, cli: cli)
                    .transition(Motion.materialize)
            case .running:
                RunPanel(run: model.run)
                    .transition(Motion.materialize)
            }
        }
        .animation(Motion.glide, value: model.state)
        .onChange(of: model.state) { _, state in
            if state == .review { Announcer.say("Scan finished. \(model.summaryLine).") }
        }
        .sheet(isPresented: $model.isChoosingVolume) {
            ExternalVolumeSheet(model: model, cli: cli, isPreview: app.effectivePreview)
        }
    }
}

private struct CleanIntro: View {
    let model: CleanModel
    let cli: CLIInfo

    var body: some View {
        ToolIntro(
            symbol: "sparkles",
            title: "See What Can Go",
            message: "Burrow previews first. Nothing is removed until you’ve reviewed the results and chosen to clean.",
            errorMessage: model.errorMessage
        ) {
            HStack {
                Button("Clean External Volume…", action: chooseVolume)
                    .controlSize(.large)
                Button("Scan This Mac", action: scan)
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func scan() {
        model.scan(cli: cli)
    }

    private func chooseVolume() {
        model.isChoosingVolume = true
    }
}

private struct CleanReportView: View {
    @Bindable var model: CleanModel
    let cli: CLIInfo
    @Environment(AppModel.self) private var app

    private var groups: [CleanReport.Section] {
        model.report.sections.filter { !$0.isEmpty }
    }

    private var empties: [CleanReport.Section] {
        model.report.sections.filter(\.isEmpty)
    }

    var body: some View {
        let largestBytes = groups.map(\.bytes).max() ?? 0
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.group) {
                CleanTotalHeader(
                    bytes: model.report.potentialBytes,
                    isScanning: model.state == .scanning,
                    activity: model.scanActivity
                )
                if let errorMessage = model.errorMessage {
                    InlineNotice(text: errorMessage, tint: .red) { model.errorMessage = nil }
                }
                if !model.protectedThisSession.isEmpty {
                    InlineNotice(text: "Protected items are left alone from now on. Scan again to update the total.", symbol: "lock.shield.fill", tint: .blue)
                }
                ForEach(groups) { section in
                    CleanSectionCard(
                        section: section,
                        largestBytes: largestBytes,
                        model: model,
                        cli: cli,
                        isEditable: model.state == .review && !app.effectivePreview
                    )
                    .transition(Motion.rise)
                }
                if !empties.isEmpty, model.state == .review {
                    Text("Nothing to clean in \(empties.map(\.name).formatted(.list(type: .and))).")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
            }
            .padding(Theme.Space.page)
        }
        // Here rather than on the page, whose body would otherwise read the report on every
        // update of a scan. This question only comes up once the report is finished.
        .alert("Clean \(model.report.potentialBytes.fileSize) from This Mac?", isPresented: $model.isConfirming) {
            // Return mustn't be the way something permanent happens.
            Button("Cancel", role: .cancel) {}
                .keyboardShortcut(.defaultAction)
            Button("Clean") { model.clean(cli: cli, preview: false) }
        } message: {
            Text(model.confirmationMessage)
        }
    }
}

/// The running total, which rolls upward as the scan finds more.
private struct CleanTotalHeader: View {
    let bytes: Int64
    let isScanning: Bool
    let activity: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.tight) {
            HeroNumber(text: bytes.countedSize, value: Double(bytes))
            HStack(spacing: Theme.Space.row) {
                if isScanning {
                    ProgressView()
                        .controlSize(.small)
                        .transition(Motion.materialize)
                }
                Text(isScanning ? activity : "can be reclaimed")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
            }
            .animation(Motion.snap, value: activity)
        }
        .padding(.bottom, Theme.Space.tight)
        .accessibilityElement(children: .combine)
    }
}

/// Stable inputs let unchanged sections skip updates while the scan progresses.
private struct CleanSectionCard: View {
    let section: CleanReport.Section
    let largestBytes: Int64
    @Bindable var model: CleanModel
    let cli: CLIInfo
    let isEditable: Bool

    var body: some View {
        Surface(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                CleanSectionHeader(section: section, largestBytes: largestBytes,
                                   isExpanded: $model[isExpanded: section.id])
                if model[isExpanded: section.id] {
                    Divider()
                    CleanSectionDetails(section: section, isEditable: isEditable,
                                        protected: model.protectedThisSession, protect: protect)
                        .transition(Motion.content(y: -6))
                }
            }
        }
        .clipShape(.rect(cornerRadius: Theme.Radius.card))
    }

    private func protect(_ path: String) {
        withAnimation(Motion.snap) { model.protect(path: path, cli: cli) }
    }
}

private struct CleanSectionHeader: View {
    let section: CleanReport.Section
    let largestBytes: Int64
    @Binding var isExpanded: Bool

    var body: some View {
        Button(action: toggle) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: Theme.Space.item) {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .bold()
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .transaction { transaction in
                            if Motion.isReduced { transaction.animation = nil }
                        }
                        .frame(width: 12)
                        .accessibilityHidden(true)
                    Image(systemName: Self.symbol(for: section.name))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 20)
                        .accessibilityHidden(true)
                    Text(section.name)
                        .font(.headline)
                    Spacer()
                    if section.bytes > 0 {
                        Text(section.bytes.fileSize)
                            .font(.callout)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText(value: Double(section.bytes)))
                    } else if section.rows.contains(where: { $0.kind == .review }) {
                        // These are pointers for you to look at. Clean leaves them alone, so
                        // they add nothing to the total.
                        FactTag(text: "For Review")
                            .help("Clean doesn’t remove these. Look at them yourself, for example in Disk Explorer.")
                    }
                }
                if section.bytes > 0, largestBytes > 0 {
                    LevelBar(fraction: Double(section.bytes) / Double(largestBytes), height: 3)
                        .padding(.leading, 52)
                }
            }
            .padding(.horizontal, Theme.Space.card)
            .padding(.vertical, Theme.Space.cluster)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        .help(isExpanded ? "Hide the files in this group" : "Show the files in this group")
    }

    private func toggle() {
        withAnimation(Motion.glide) { isExpanded.toggle() }
    }

    private static func symbol(for name: String) -> String {
        switch name.lowercased() {
        case let value where value.contains("user"): "person"
        case let value where value.contains("app cache"): "square.stack.3d.up"
        case let value where value.contains("browser"): "safari"
        case let value where value.contains("cloud"): "icloud"
        case let value where value.contains("developer"): "hammer"
        case let value where value.contains("apps &"): "app.badge"
        case let value where value.contains("virtual"): "cube"
        case let value where value.contains("application support"): "folder"
        case let value where value.contains("leftover"): "shippingbox"
        case let value where value.contains("silicon"): "cpu"
        case let value where value.contains("backup"): "iphone"
        case let value where value.contains("time machine"): "clock.arrow.circlepath"
        case let value where value.contains("large"): "doc.badge.ellipsis"
        case let value where value.contains("project"): "folder.badge.gearshape"
        case let value where value.contains("system"): "gearshape"
        default: "tray"
        }
    }
}

private struct CleanSectionDetails: View {
    let section: CleanReport.Section
    let isEditable: Bool
    let protected: Set<String>
    let protect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.snug) {
            ForEach(section.rows) { LogRow(line: $0) }
            if !section.paths.isEmpty {
                Text("Files")
                    .font(.subheadline)
                    .bold()
                    .foregroundStyle(.secondary)
                    .padding(.top, Theme.Space.row)
                ForEach(section.paths.prefix(200)) { entry in
                    CleanPathRow(
                        entry: entry,
                        isProtected: protected.contains(entry.path),
                        isEditable: isEditable,
                        protect: protect
                    )
                }
                if section.paths.count > 200 {
                    Text("And \(section.paths.count - 200) more.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(Theme.Space.card)
    }
}

/// A file row whose actions appear on hover, with the same commands on secondary click.
private struct CleanPathRow: View {
    let entry: CleanReport.PathEntry
    let isProtected: Bool
    let isEditable: Bool
    let protect: (String) -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Theme.Space.row) {
            if isProtected {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .symbolEffect(.bounce, options: .nonRepeating)
                    .accessibilityLabel("Protected")
            }
            Text(entry.path.abbreviatingHome)
                .font(.callout.monospaced())
                .foregroundStyle(isProtected ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(entry.path)
            Spacer(minLength: 8)
            if !isProtected, isEditable {
                // Always present, because a control that needs a pointer can't be reached
                // with the keyboard or VoiceOver. It only stays quiet until you're near it.
                Button("Protect", systemImage: "lock", action: protectEntry)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .opacity(isHovered ? 1 : 0.35)
                    .help("Keep cleanup away from this path from now on")
            }
            Text(entry.sizeText)
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .frame(minHeight: 20)
        .onHover { isHovered = $0 }
        .animation(Motion.snap, value: isHovered)
        .contextMenu {
            Button("Show in Finder", action: reveal)
            Button("Always Protect This", action: protectEntry)
                .disabled(isProtected || !isEditable)
        }
    }

    private func reveal() {
        FilePicker.reveal(entry.path)
    }

    private func protectEntry() {
        protect(entry.path)
    }
}

/// Lists mounted external volumes for `mo clean --external`.
struct ExternalVolumeSheet: View {
    let model: CleanModel
    let cli: CLIInfo
    let isPreview: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var selection: String?
    @State private var volumes: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.card) {
            Text("Clean an External Volume")
                .font(.title3)
                .bold()
            Text("Removes macOS metadata such as .DS_Store files and resource forks from the volume you choose.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if volumes.isEmpty {
                InlineNotice(text: "No external volumes are mounted.", symbol: "externaldrive", tint: .secondary)
            } else {
                List(volumes, id: \.self, selection: $selection) { volume in
                    Label((volume as NSString).lastPathComponent, systemImage: "externaldrive")
                }
                .frame(height: 140)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isPreview ? "Preview" : "Clean…", action: submit)
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(selection == nil)
            }
        }
        .padding(Theme.Space.sheet)
        .frame(width: 440)
        .onAppear { volumes = Self.mountedVolumes() }
        .alert(confirmationTitle, isPresented: isConfirming) {
            // Return mustn't be the way something permanent happens.
            Button("Cancel", role: .cancel) {}
                .keyboardShortcut(.defaultAction)
            Button("Clean") { model.confirmExternalClean(cli: cli) }
        } message: {
            Text("This removes .DS_Store files, AppleDouble files and temporary items, and it can’t be undone. The volume’s Trash is left alone.")
        }
    }

    private var confirmationTitle: String {
        let name = model.volumeAwaitingConfirmation.map { ($0 as NSString).lastPathComponent } ?? "This Volume"
        return "Clean Metadata from \(name)?"
    }

    private var isConfirming: Binding<Bool> {
        Binding(
            get: { model.volumeAwaitingConfirmation != nil },
            set: { if !$0 { model.volumeAwaitingConfirmation = nil } }
        )
    }

    private func submit() {
        guard let selection else { return }
        model.requestExternalClean(path: selection, cli: cli, preview: isPreview)
    }

    private static func mountedVolumes() -> [String] {
        let keys: [URLResourceKey] = [.volumeIsInternalKey, .volumeIsReadOnlyKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard url.path.hasPrefix("/Volumes/"),
                  values?.volumeIsInternal != true,
                  values?.volumeIsReadOnly != true else {
                return nil
            }
            return url.path
        }
    }
}
