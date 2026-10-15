import SwiftUI
import ServiceManagement

private let signal = Color(nsColor: .systemOrange)

struct Panel: View {
    static let width: CGFloat = 336
    static let height: CGFloat = 396
    @ObservedObject var light: LightController
    @ObservedObject private var appearance = AppearanceSettings.shared
    var quit: () -> Void = { NSApplication.shared.terminate(nil) }
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var scheme
    private var adjusting: Bool { light.canControl && light.status?.on == true }
    private var ambientVisible: Bool {
        light.ready && light.status?.on == true && !light.showSetup && !light.showPreferences
            && !reduceTransparency && contrast != .increased
    }
    private var ambientKelvin: Double { light.status?.kelvin ?? 4500 }
    /// An interface palette, not a calibrated simulation of the emitted spectrum.
    private var ambientColor: Color {
        let k = min(6500, max(2700, ambientKelvin))
        let warm = (1.0, 0.40, 0.08), neutral = (1.0, 0.79, 0.49), cool = (0.48, 0.72, 1.0)
        let a = k <= 4500 ? warm : neutral, b = k <= 4500 ? neutral : cool
        let t = k <= 4500 ? (k - 2700) / 1800 : (k - 4500) / 2000
        return Color(red: a.0 + (b.0 - a.0) * t, green: a.1 + (b.1 - a.1) * t, blue: a.2 + (b.2 - a.2) * t)
    }
    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if light.showPreferences { preferences }
                    else if light.configuration == nil || light.showSetup { setup }
                    else { controls }
                    if let error = light.error {
                        HStack(alignment: .top, spacing: 8) {
                            PhosphorIcon(name: "warning-circle").foregroundStyle(signal)
                            Text(error).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(signal.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                            .accessibilityElement(children: .combine)
                    }
                }.padding(.horizontal, 16).padding(.bottom, 16)
            }.scrollIndicators(.hidden)
        }
        .frame(width: Self.width, height: Self.height)
        .background {
            ZStack {
                if reduceTransparency { Color(nsColor: .windowBackgroundColor) }
                else { Rectangle().fill(.regularMaterial) }
                ZStack {
                    RadialGradient(colors: [ambientColor.opacity(scheme == .dark ? 0.68 : 0.40), .clear],
                                   center: UnitPoint(x: 0.08, y: 0.78), startRadius: 6, endRadius: 310)
                    RadialGradient(colors: [ambientColor.opacity(scheme == .dark ? 0.24 : 0.12), .clear],
                                   center: UnitPoint(x: 1, y: 0.16), startRadius: 0, endRadius: 220)
                }
                .opacity(ambientVisible ? 1 : 0)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: ambientVisible)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: ambientKelvin)
            }.clipped().allowsHitTesting(false).accessibilityHidden(true)
        }
        .preferredColorScheme(light.preview ? nil : appearance.mode == "dark" ? .dark : appearance.mode == "light" ? .light : nil)
    }
    private var header: some View {
        HStack(spacing: 8) {
            if light.showPreferences || (light.showSetup && light.configuration != nil) {
                Button {
                    light.showPreferences = false; light.showSetup = false
                } label: { PhosphorIcon(name: "caret-left", size: 15).frame(width: 24, height: 24) }
                    .buttonStyle(.plain).help("Voltar").accessibilityLabel("Voltar")
            } else { PhosphorIcon(name: "planet", size: 18).foregroundStyle(.secondary) }
            Text(light.showPreferences ? "Ajustes" : "Lume").font(.system(size: 13, weight: .semibold))
            Spacer()
            options
        }.padding(.horizontal, 16).padding(.vertical, 12)
    }
    private var options: some View {
        Menu {
            Button { light.showPreferences = true } label: {
                Label { Text("Ajustes…") } icon: { PhosphorIcon(name: "gear-six") }
            }.keyboardShortcut(",")
            Button { light.showPreferences = false; light.showSetup = true } label: {
                Label { Text("Conectar luz…") } icon: { PhosphorIcon(name: "bluetooth") }
            }.disabled(light.pending || light.pairing || light.connecting)
            Button { if light.ready { light.requestStatus() } else { light.connect() } } label: {
                Label { Text(light.ready ? "Atualizar estado" : "Reconectar") } icon: { PhosphorIcon(name: "arrow-clockwise") }
            }.disabled(light.configuration == nil || light.scanning || light.connecting || light.pending)
            Divider()
            Menu("Ajustes rápidos") {
                Button("Aconchego · 25% · 3200 K") { light.apply(kelvin: 3200, brightness: 25) }
                Button("Trabalho · 50% · 4300 K") { light.apply(kelvin: 4300, brightness: 50) }
                Button("Gravação · 75% · 5600 K") { light.apply(kelvin: 5600, brightness: 75) }
            }.disabled(!adjusting)
            Divider()
            Button("Sair do Lume", action: quit).keyboardShortcut("q")
        } label: {
            PhosphorIcon(name: "dots-three", size: 20).frame(width: 26, height: 24).contentShape(Rectangle())
        }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help("Opções do Lume").accessibilityLabel("Opções do Lume")
    }
    private var controls: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(light.configuration?.name ?? "amaran").font(.system(size: 15, weight: .semibold)).lineLimit(2)
                    HStack(spacing: 6) {
                        if light.connecting { ProgressView().controlSize(.mini) }
                        else { Circle().fill(light.ready ? Color.green : Color.secondary).frame(width: 5, height: 5) }
                        Text(light.connection)
                            .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).help(light.connection)
                    }.accessibilityElement(children: .combine)
                }
                Spacer(minLength: 4)
                Button { light.togglePower() } label: {
                    PhosphorIcon(name: "power", size: 21)
                        .foregroundStyle(light.status?.on == true ? signal : Color.secondary)
                        .frame(width: 42, height: 42).contentShape(Circle())
                }.buttonStyle(.plain).modifier(InstrumentGlass(radius: 21)).disabled(!light.canControl)
                    .help(light.status?.on == true ? "Apagar luz" : "Acender luz")
                    .accessibilityLabel(light.status?.on == true ? "Apagar luz" : "Acender luz")
                    .accessibilityValue(light.status?.on == true ? "Acesa" : "Apagada")
            }.padding(.horizontal, 3).padding(.bottom, 1)
            instrument(name: "Intensidade", icon: "sun", value: light.status == nil ? "—" : String(format: "%.0f", light.desiredBrightness), unit: "%") {
                Slider(value: $light.desiredBrightness, in: 0...100, onEditingChanged: { editing in
                    light.editingBrightness = editing
                    if !editing { light.desiredBrightness = light.desiredBrightness.rounded(); light.setBrightness() }
                }).tint(signal).disabled(!adjusting)
                    .accessibilityLabel("Intensidade").accessibilityValue("\(Int(light.desiredBrightness)) por cento")
                scale(left: "0", right: "100%", warm: false)
            }
            instrument(name: "Temperatura", icon: "thermometer", value: light.status == nil ? "—" : String(format: "%.0f", light.desiredKelvin), unit: "K") {
                Slider(value: $light.desiredKelvin, in: 2700...6500, onEditingChanged: { editing in
                    light.editingKelvin = editing
                    if !editing { light.desiredKelvin = (light.desiredKelvin / 100).rounded() * 100; light.setKelvin() }
                }).tint(signal).disabled(!adjusting)
                    .accessibilityLabel("Temperatura de cor").accessibilityValue("\(Int(light.desiredKelvin)) kelvin")
                scale(left: "2700 K", right: "6500 K", warm: true)
            }
            if !light.ready && !light.connecting {
                Button("Reconectar") { light.connect() }.buttonStyle(.bordered).controlSize(.small)
                    .disabled(light.scanning || light.pending)
            }
        }
    }
    private func instrument<Content: View>(name: String, icon: String, value: String, unit: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 9) {
            HStack(spacing: 7) {
                PhosphorIcon(name: icon, size: 16).foregroundStyle(.secondary)
                Text(name).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value).font(.system(size: 25, weight: .medium, design: .rounded)).monospacedDigit()
                    Text(unit).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                }.accessibilityElement(children: .combine)
            }
            content()
        }.padding(15).modifier(InstrumentGlass())
    }
    private func scale(left: String, right: String, warm: Bool) -> some View {
        VStack(spacing: 5) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(0..<21) { i in
                    Rectangle().fill(Color.primary.opacity(i % 5 == 0 ? 0.27 : 0.12))
                        .frame(width: 1, height: i % 5 == 0 ? 5 : 3)
                    if i < 20 { Spacer(minLength: 0) }
                }
            }.accessibilityHidden(true)
            HStack {
                if warm { Circle().fill(Color(nsColor: .systemOrange)).frame(width: 4, height: 4).accessibilityHidden(true) }
                Text(left); Spacer(); Text(right)
                if warm { Circle().fill(Color(nsColor: .systemBlue)).frame(width: 4, height: 4).accessibilityHidden(true) }
            }.font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit()
        }
    }
    private var preferences: some View {
        VStack(alignment: .leading, spacing: 20) {
            Toggle("Abrir ao iniciar sessão", isOn: $light.launchAtLogin)
                .toggleStyle(.switch).controlSize(.small)
                .onChange(of: light.launchAtLogin) { value in
                    do { if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                    catch {
                        light.launchAtLogin = SMAppService.mainApp.status == .enabled
                        light.error = "Verifique Ajustes do Sistema → Geral → Itens de Início."
                    }
                }
            Divider()
            VStack(alignment: .leading, spacing: 5) {
                Text("Aparência").font(.system(size: 12, weight: .medium))
                Picker("Aparência", selection: Binding(get: { appearance.mode }, set: { appearance.select($0) })) {
                    Text("Sistema").tag("system")
                    Text("Claro").tag("light")
                    Text("Escuro").tag("dark")
                }.pickerStyle(.segmented).labelsHidden()
                Text("Sistema acompanha a aparência do macOS.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Divider()
            Link("Código e comunidade", destination: URL(string: "https://github.com/joefaria/lume-amaran")!)
                .font(.system(size: 12))
            Text("Lume \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }.padding(15).modifier(InstrumentGlass())
    }
    private var setup: some View {
        VStack(alignment: .leading, spacing: 16) {
            if light.pairing || light.connecting {
                ProgressView().controlSize(.small)
                Text("Conectando sua luz").font(.system(size: 17, weight: .semibold))
                Text(light.connection).font(.system(size: 12)).foregroundStyle(.secondary)
                Text("Mantenha a luz ligada e perto do Mac.").font(.system(size: 12)).foregroundStyle(.secondary)
                Button("Cancelar") { light.disconnect(); light.connection = "Conexão cancelada" }.buttonStyle(.bordered)
            } else if !light.candidates.isEmpty {
                Text("Escolha sua luz").font(.system(size: 17, weight: .semibold))
                ForEach(light.candidates) { item in
                    Button { light.choose(item) } label: {
                        HStack { PhosphorIcon(name: "sun"); Text(item.name); Spacer() }.padding(12)
                    }.buttonStyle(.plain).modifier(InstrumentGlass(radius: 12))
                }
            } else {
                Text("Sua luz, ao alcance.").font(.system(size: 20, weight: .semibold))
                Text("Ligue a amaran e aproxime o Mac.").font(.system(size: 12)).foregroundStyle(.secondary)
                Button { light.connect(pairingSearch: true) } label: {
                    HStack { if light.scanning { ProgressView().controlSize(.mini) }; Text(light.scanning ? "Buscando…" : "Buscar luz") }
                        .frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).controlSize(.large).tint(signal).disabled(light.scanning)
                ForEach(light.nearby.sorted(by: { $0.canPair && !$1.canPair })) { entry in
                    Button { light.pair(entry.id) } label: {
                        HStack(spacing: 10) {
                            PhosphorIcon(name: "bluetooth")
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.name).font(.system(size: 12, weight: .medium))
                                Text(entry.canPair ? "Pronta para parear" : "Já pareada · requer BT Reset")
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }; Spacer(minLength: 0)
                        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain).modifier(InstrumentGlass(radius: 12)).disabled(!entry.canPair)
                }
                if light.scanCompleted && light.nearby.isEmpty {
                    Text("Nenhuma luz encontrada. Verifique se ela está ligada e tente novamente.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Text("Já pareou em outro app? Use BT Reset na luz e aguarde Success. Isso remove o vínculo anterior.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                DisclosureGroup("Importar conexão existente", isExpanded: $light.showAdvanced) {
                    VStack(alignment: .leading, spacing: 12) {
                        Button("Sidus Link / arquivo…") { light.importIPhone() }
                        Button("amaran Desktop…") { light.importDesktop() }
                    }.padding(.top, 10).font(.system(size: 12))
                }.font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
    }
}
