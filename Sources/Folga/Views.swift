import SwiftUI

// MARK: - Helpers

/// Local view state. (`@State` is a macro the Command Line Tools can't expand.)
final class Flag: ObservableObject { @Published var on = false }

private let byteFormatter: ByteCountFormatter = {
    let f = ByteCountFormatter()
    f.countStyle = .file
    f.allowsNonnumericFormatting = false
    return f
}()

func bytes(_ n: Int64) -> String { byteFormatter.string(fromByteCount: n) }

/// Whole numbers for big values ("260 GB"), for the hero and the menu bar.
func bytesShort(_ n: Int64) -> String {
    let gb = Double(n) / 1e9
    guard gb >= 10 else { return bytes(n) }
    if gb >= 1000 { return (gb / 1000).formatted(.number.precision(.fractionLength(gb >= 10_000 ? 0 : 1))) + " TB" }
    return gb.formatted(.number.precision(.fractionLength(gb >= 100 ? 0 : 1))) + " GB"
}

extension AppReport {
    var tint: Color {
        switch id {
        case "chatgpt": Color(red: 0.06, green: 0.64, blue: 0.50)
        case "claude": Color(red: 0.85, green: 0.47, blue: 0.34)
        case "antigravity": Color(red: 0.26, green: 0.52, blue: 0.96)
        case "pnpm": Color(red: 0.96, green: 0.57, blue: 0.13)
        case "npm": Color(red: 0.80, green: 0.22, blue: 0.22)
        case "node": Color(red: 0.37, green: 0.63, blue: 0.31)
        case "uv": Color(red: 0.60, green: 0.36, blue: 0.86)
        case "bun": Color(red: 0.72, green: 0.56, blue: 0.40)
        case "docker": Color(red: 0.11, green: 0.39, blue: 0.93)
        case "huggingface": Color(red: 0.95, green: 0.65, blue: 0.10)
        case "browsers": Color(red: 0.18, green: 0.68, blue: 0.40)
        case "whisper": Color(red: 0.37, green: 0.36, blue: 0.90)
        default: .gray
        }
    }

    var icon: NSImage {
        if let url = appURL { return NSWorkspace.shared.icon(forFile: url.path) }
        return NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()
    }
}

/// The app's own icon, or the tool's symbol on a tinted tile.
struct ReportIcon: View {
    let report: AppReport
    let size: CGFloat

    var body: some View {
        if report.appURL == nil, let symbol = report.symbol {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(report.tint.gradient)
                .frame(width: size, height: size)
                .overlay(Image(systemName: symbol)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white))
        } else {
            Image(nsImage: report.icon).resizable().frame(width: size, height: size)
        }
    }
}

// MARK: - Root

struct RootView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        Group {
            switch store.phase {
            case .overview: OverviewView()
            case .review: ReviewView()
            case .confirm: ConfirmView()
            case .cleaning: CleaningView()
            case .done(let result): DoneView(result: result)
            }
        }
        .frame(width: 340)
        .animation(.snappy(duration: 0.25), value: phaseKey)
        .onAppear { store.refreshIfStale() }
    }

    private var phaseKey: Int {
        switch store.phase {
        case .overview: 0
        case .review: 1
        case .confirm: 2
        case .cleaning: 3
        case .done: 4
        }
    }
}

// MARK: - Overview

struct OverviewView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DiskHeader().padding(16)
            Divider().padding(.horizontal, 16)

            HStack(alignment: .firstTextBaseline) {
                Text("Inteligência artificial").font(.headline)
                Spacer()
                Text(bytes(store.aiTotal))
                    .font(.headline).monospacedDigit()
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 6)

            VStack(spacing: 2) {
                if store.reports.isEmpty {
                    ForEach(0..<3, id: \.self) { _ in AppRowPlaceholder() }
                } else {
                    ForEach(store.aiReports) { AppRow(report: $0) }
                }
            }
            .padding(.horizontal, 8)

            if !store.devReports.isEmpty {
                DevSection().padding(.top, 8)
            }

            Group {
                if store.selectedReports.isEmpty {
                    Button {} label: {
                        Text("Selecione o que quer limpar").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered).disabled(true)
                } else {
                    Button { store.phase = .review } label: {
                        Text(store.reclaimable > 0 ? "Revisar limpeza · \(bytes(store.reclaimable))" : "Revisar limpeza")
                            .frame(maxWidth: .infinity)
                            .contentTransition(.numericText())
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.reclaimable == 0 && store.blockedCache == 0)
                }
            }
            .controlSize(.large)
            .padding(.horizontal, 16).padding(.top, 12)

            Divider().padding(.horizontal, 16).padding(.top, 14)
            AwakeSection().padding(.horizontal, 16).padding(.top, 12)

            Footer().padding(.horizontal, 16).padding(.vertical, 10)
        }
    }
}

struct DiskHeader: View {
    @EnvironmentObject var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let disk = store.disk {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(bytesShort(disk.available))
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("disponíveis").foregroundStyle(.secondary)
                    Spacer()
                }
                StorageBar(disk: disk, reports: store.aiReports)
                HStack(spacing: 12) {
                    ForEach(store.aiReports) { r in
                        Legend(color: r.tint, label: r.name)
                    }
                    Spacer()
                    Text("de \(bytesShort(disk.total))")
                        .foregroundStyle(.tertiary)
                        .help(disk.name)
                }
                .font(.caption)
            }
        }
    }
}

struct StorageBar: View {
    let disk: DiskInfo
    let reports: [AppReport]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let scale = w / CGFloat(max(disk.total, 1))
            let aiWidths = reports.map { max(CGFloat($0.total) * scale, $0.total > 0 ? 3 : 0) }
            let usedWidth = max(CGFloat(disk.used) * scale, aiWidths.reduce(0, +))
            HStack(spacing: 1.5) {
                ForEach(Array(reports.enumerated()), id: \.offset) { i, r in
                    Rectangle().fill(r.tint).frame(width: aiWidths[i])
                }
                Rectangle().fill(Color.secondary.opacity(0.45))
                    .frame(width: max(usedWidth - aiWidths.reduce(0, +) - CGFloat(reports.count) * 1.5, 0))
                Rectangle().fill(Color.secondary.opacity(0.14))
            }
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .frame(height: 14)
        .animation(.smooth, value: disk.available)
    }
}

struct Legend: View {
    let color: Color
    let label: String
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).foregroundStyle(.secondary)
        }
    }
}

struct AppRow: View {
    @EnvironmentObject var store: Store
    let report: AppReport
    @StateObject private var hover = Flag()

    var body: some View {
        let picked = store.isSelected(report)
        Button { store.toggle(report) } label: {
            HStack(spacing: 10) {
                Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(picked ? AnyShapeStyle(report.tint) : AnyShapeStyle(.tertiary))
                    .contentTransition(.symbolEffect(.replace))
                ReportIcon(report: report, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(report.name).font(.body.weight(.medium))
                        if store.isRunning(report) {
                            Circle().fill(.green).frame(width: 5, height: 5)
                                .help("Aberto agora")
                        }
                    }
                    Text(detail)
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1)
                    if lockedCache > 0 {
                        Text("+\(bytes(lockedCache)) se fechar o app")
                            .font(.caption).foregroundStyle(.orange)
                            .lineLimit(1)
                            .help("Cache temporário preso porque o app está aberto. Feche-o, ou marque \"Fechar e reabrir\" na revisão, para limpar esse cache.")
                    }
                }
                Spacer(minLength: 8)
                Text(bytes(report.total))
                    .font(.body.weight(.medium)).monospacedDigit()
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(picked ? report.tint.opacity(0.12) : hover.on ? Color.primary.opacity(0.06) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover.on = $0 }
        .help(picked ? "Clique para tirar da limpeza\n\n" + breakdown : "Clique para incluir na limpeza\n\n" + breakdown)
        .accessibilityAddTraits(picked ? .isSelected : [])
    }

    /// Cache we can't touch while the app is open.
    private var lockedCache: Int64 {
        store.isRunning(report) && store.includeCache && !store.quitRunning ? report.cacheSize : 0
    }

    private var detail: String {
        let free = store.reclaimable(report, ignoringSelection: true)
        if free > 0 { return "\(bytes(free)) liberáveis agora" }
        return lockedCache > 0 ? "Nada liberável agora" : "Nada para limpar"
    }

    private var breakdown: String {
        """
        App: \(bytes(report.appSize))
        Conversas: \(bytes(report.chatSize))
        Cache: \(bytes(report.cacheSize))
        Outros dados: \(bytes(max(report.dataSize - report.chatSize - report.cacheSize, 0)))
        """
    }
}

// MARK: - Dev tools

struct DevSection: View {
    @EnvironmentObject var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button { store.devExpanded.toggle() } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Desenvolvimento").font(.headline)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold)).foregroundStyle(.secondary)
                        .rotationEffect(.degrees(store.devExpanded ? 90 : 0))
                    if !store.devExpanded {
                        let picked = store.devReports.filter(store.isSelected).count
                        if picked > 0 {
                            Text("\(picked) selecionado\(picked > 1 ? "s" : "")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(bytes(store.devTotal)).font(.headline).monospacedDigit()
                        .contentTransition(.numericText())
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16).padding(.vertical, 6)

            if store.devExpanded {
                VStack(spacing: 0) {
                    ForEach(store.devReports) { DevRow(report: $0) }
                }
                .padding(.horizontal, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.snappy(duration: 0.2), value: store.devExpanded)
    }
}

struct DevRow: View {
    @EnvironmentObject var store: Store
    let report: AppReport
    @StateObject private var hover = Flag()

    var body: some View {
        let picked = store.isSelected(report)
        let free = store.reclaimable(report, ignoringSelection: true)
        Button { store.toggle(report) } label: {
            HStack(spacing: 10) {
                Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(picked ? AnyShapeStyle(report.tint) : AnyShapeStyle(.tertiary))
                ReportIcon(report: report, size: 20)
                Text(report.name).lineLimit(1)
                Spacer(minLength: 8)
                if let note = report.note {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(free > 0 ? bytes(free) : "—")
                        .monospacedDigit()
                        .foregroundStyle(free > 0 ? .primary : .tertiary)
                }
            }
            .font(.callout)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(picked ? report.tint.opacity(0.12) : hover.on ? Color.primary.opacity(0.06) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover.on = $0 }
        .help(help)
    }

    private var help: String {
        let what: String = switch report.id {
        case "pnpm": "Cache de metadados e stores de versões antigas; depois roda pnpm store prune."
        case "npm": "Cache de pacotes e logs; pacotes do npx parados há 7+ dias."
        case "node": "Headers do node-gyp e cache do Corepack/nvm."
        case "uv": "Cache do uv e do pip. Ambientes e Pythons instalados ficam."
        case "bun": "Cache de pacotes do Bun."
        case "docker": "Imagens sem uso, contêineres parados e cache de build. Volumes nunca são apagados."
        case "huggingface": "Modelos e datasets baixados (exceto Whisper). São baixados de novo quando usados."
        case "browsers": "Versões antigas dos navegadores do Playwright e Puppeteer; a mais nova de cada fica."
        case "whisper": "Modelos Whisper (Hugging Face e openai-whisper)."
        default: ""
        }
        return "\(what)\n\nNo disco: \(bytes(report.total))"
    }
}

struct AppRowPlaceholder: View {
    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 7).fill(.quaternary).frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 5) {
                Capsule().fill(.quaternary).frame(width: 80, height: 9)
                Capsule().fill(.quaternary).frame(width: 120, height: 7)
            }
            Spacer()
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
    }
}

struct Footer: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var updater: Updater

    var body: some View {
        HStack {
            if store.scanning {
                ProgressView().controlSize(.small)
                Text("Medindo…")
            } else if let last = store.lastScan {
                Text("Atualizado \(last, format: .relative(presentation: .named))")
            }
            Spacer()
            Button { Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless).disabled(store.scanning)
                .keyboardShortcut("r")
                .help("Medir de novo")
            Menu {
                Picker("Conversas antigas", selection: $store.chatDays) {
                    Text("Paradas há 7 dias").tag(7)
                    Text("Paradas há 30 dias").tag(30)
                    Text("Paradas há 90 dias").tag(90)
                }
                Toggle("Abrir ao iniciar sessão", isOn: $store.opensAtLogin)
                Divider()
                Button("Procurar atualizações…") { updater.check() }
                    .disabled(!updater.canCheck)
                Text("Folga \(Updater.version)")
                Divider()
                Button("Sair do Folga") { NSApp.terminate(nil) }.keyboardShortcut("q")
            } label: { Image(systemName: "gearshape") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }
        .font(.caption).foregroundStyle(.secondary)
    }
}

// MARK: - Keep awake

func duration(_ minutes: Int) -> String {
    let h = minutes / 60, m = minutes % 60
    if h == 0 { return "\(m) min" }
    return m == 0 ? "\(h) h" : "\(h)h\(String(format: "%02d", m))"
}

struct AwakeSection: View {
    @EnvironmentObject var awake: KeepAwake

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label {
                    Text("Manter acordado").font(.headline)
                } icon: {
                    Image(systemName: awake.isOn ? "cup.and.saucer.fill" : "cup.and.saucer")
                        .foregroundStyle(awake.isOn ? Color.accentColor : .secondary)
                }
                Spacer()
                Toggle("Manter acordado", isOn: Binding(get: { awake.isOn }, set: { awake.setOn($0) }))
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
            .help("Impede que a tela apague, a proteção de tela entre e a sessão bloqueie.")

            Slider(value: Binding(get: { Double(awake.minutes) }, set: { awake.choose(Int($0.rounded())) }),
                   in: 30...Double(KeepAwake.maxMinutes)) {
                Text("Duração")
            } minimumValueLabel: {
                Text("30min")
            } maximumValueLabel: {
                Text("24h")
            }
            .labelsHidden()
            .controlSize(.small)
            .font(.caption).foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(status(at: context.date))
                        .font(.caption).monospacedDigit()
                        .foregroundStyle(awake.isOn ? .primary : .secondary)
                }
                Spacer()
                Button("+30 min") { awake.addHalfHour() }
                    .controlSize(.small)
                    .disabled(awake.isOn && awake.minutes >= KeepAwake.maxMinutes)
                    .help(awake.isOn ? "Mais 30 minutos" : "Ligar por 30 minutos")
                Button { awake.reset() } label: { Image(systemName: "arrow.counterclockwise") }
                    .controlSize(.small)
                    .help("Zerar: volta para 30 min, contando de agora")
            }
        }
    }

    private func status(at now: Date) -> String {
        guard awake.isOn, let end = awake.endsAt else { return "Por \(duration(awake.minutes))" }
        let left = max(Int(end.timeIntervalSince(now)), 0)
        let clock = String(format: "%d:%02d:%02d", left / 3600, left % 3600 / 60, left % 60)
        return "Até \(end.formatted(date: .omitted, time: .shortened)) · faltam \(clock)"
    }
}

// MARK: - Review

struct ReviewView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button { store.phase = .overview } label: {
                    Image(systemName: "chevron.left").font(.body.weight(.semibold))
                }
                .buttonStyle(.borderless).keyboardShortcut(.cancelAction)
                Text("Revisar limpeza").font(.headline)
                Spacer()
            }

            SelectedApps()

            VStack(spacing: 0) {
                Option(isOn: $store.includeCache,
                       title: "Cache temporário",
                       note: "Os apps recriam quando precisarem.",
                       size: store.cacheTotal - (store.quitRunning ? 0 : store.blockedCache))
                Divider().padding(.leading, 34)
                Option(isOn: $store.includeChats,
                       title: "Conversas paradas há \(store.chatDays)+ dias",
                       note: "Vão para o Lixo. Dá para recuperar.",
                       size: store.oldChatTotal)
            }
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.quaternary.opacity(0.5)))

            if store.includeCache && !store.blockingApps.isEmpty {
                RunningNotice()
            }

            Button {
                store.phase = .confirm
            } label: {
                Text(store.reclaimable > 0 ? "Continuar · \(bytes(store.reclaimable))" : "Nada para limpar")
                    .frame(maxWidth: .infinity)
                    .contentTransition(.numericText())
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .disabled(store.reclaimable == 0)
        }
        .padding(16)
    }
}

/// The AIs picked on the main screen, with what each one will free.
struct SelectedApps: View {
    @EnvironmentObject var store: Store

    var body: some View {
        VStack(spacing: 6) {
            ForEach(store.selectedReports) { r in
                HStack(spacing: 8) {
                    ReportIcon(report: r, size: 18)
                    Text(r.name)
                    Spacer()
                    Text(store.reclaimable(r) > 0 ? bytes(store.reclaimable(r)) : "—").monospacedDigit()
                        .foregroundStyle(store.reclaimable(r) > 0 ? .primary : .tertiary)
                }
                .font(.callout)
            }
        }
        .padding(.horizontal, 4)
    }
}

struct ConfirmView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        let names = ListFormatter.localizedString(byJoining: store.selectedReports.filter { store.reclaimable($0) > 0 }.map(\.name))
        let closing = store.includeCache && store.quitRunning ? store.blockingApps.map(\.name) : []
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 34)).foregroundStyle(.orange)
            VStack(spacing: 4) {
                Text("Limpar \(names)?").font(.headline).multilineTextAlignment(.center)
                Text("Confira antes de continuar.").font(.callout).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                if store.cacheToClean > 0 {
                    Label("\(bytes(store.cacheToClean)) de cache serão apagados", systemImage: "trash")
                }
                if store.chatsToClean > 0 {
                    Label("\(bytes(store.chatsToClean)) de conversas vão para o Lixo", systemImage: "arrow.uturn.backward.circle")
                }
                if store.selectedReports.contains(where: { $0.id == "docker" && store.reclaimable($0) > 0 }) {
                    Label("Docker: imagens e contêineres sem uso saem; volumes ficam", systemImage: "cube.box")
                }
                if !closing.isEmpty {
                    Label("\(ListFormatter.localizedString(byJoining: closing)) \(closing.count > 1 ? "serão fechados" : "será fechado") e reaberto\(closing.count > 1 ? "s" : "")",
                          systemImage: "arrow.clockwise")
                }
            }
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.quaternary.opacity(0.5)))

            HStack(spacing: 10) {
                Button { store.phase = .review } label: { Text("Voltar").frame(maxWidth: .infinity) }
                    .keyboardShortcut(.cancelAction)
                Button(role: .destructive) { Task { await store.clean() } } label: {
                    Text("Limpar agora").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(.red)
            }
            .controlSize(.large)
        }
        .padding(16)
    }
}

struct Option: View {
    @Binding var isOn: Bool
    let title: String
    let note: String
    let size: Int64

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(size > 0 ? bytes(size) : "—").monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.checkbox)
        .padding(.horizontal, 12).padding(.vertical, 10)
    }
}

struct RunningNotice: View {
    @EnvironmentObject var store: Store

    var body: some View {
        let names = ListFormatter.localizedString(byJoining: store.blockingApps.map(\.name))
        let many = store.blockingApps.count > 1
        VStack(alignment: .leading, spacing: 8) {
            Label("\(names) \(many ? "estão abertos" : "está aberto").", systemImage: "exclamationmark.circle")
                .font(.callout.weight(.medium))
            Toggle("Fechar e reabrir para limpar o cache (+\(bytes(store.blockedCache)))", isOn: $store.quitRunning)
                .toggleStyle(.checkbox).font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            if store.quitRunning && store.blockingApps.contains(where: { $0.id == "claude" }) {
                Text("Tarefas em andamento no Claude serão interrompidas.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.orange.opacity(0.12)))
    }
}

// MARK: - Cleaning / Done

struct CleaningView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.large)
            Text("Liberando espaço…").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }
}

struct DoneView: View {
    @EnvironmentObject var store: Store
    let result: Cleaner.Result
    @StateObject private var appeared = Flag()

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44)).foregroundStyle(.green)
                .symbolEffect(.bounce, value: appeared.on)
            Text(result.deleted > 0 || result.trashed == 0
                 ? "\(bytes(result.deleted)) liberados"
                 : "\(bytes(result.trashed)) no Lixo")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
            VStack(spacing: 2) {
                if result.trashed > 0 {
                    Text(result.deleted > 0
                         ? "Mais \(bytes(result.trashed)) de conversas no Lixo."
                         : "Conversas antigas foram para o Lixo.")
                    Text("Esvazie o Lixo para liberar esse espaço.")
                }
                if result.failures > 0 {
                    Text("\(result.failures) itens estavam em uso e ficaram.")
                }
                if let disk = store.disk {
                    Text("Agora: \(bytesShort(disk.available)) disponíveis.")
                }
            }
            .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)

            Button("Concluído") { store.phase = .overview }
                .controlSize(.large).keyboardShortcut(.defaultAction)
                .padding(.top, 6)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .onAppear { appeared.on = true }
    }
}
