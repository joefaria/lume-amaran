import SwiftUI
import ServiceManagement

private let amber = Color(red: 0.94, green: 0.61, blue: 0.22)

struct Panel: View {
    @ObservedObject var light: LightController
    var quit: () -> Void = { NSApplication.shared.terminate(nil) }
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().padding(.horizontal, 20)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if light.configuration == nil || light.showSetup { setup }
                    else { controls }
                    if let error = light.error {
                        HStack(alignment: .top, spacing: 9) {
                            Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                            Text(error).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                    }
                }.padding(20)
            }.scrollIndicators(.hidden)
            Divider().padding(.horizontal, 20)
            footer
        }
        .frame(width: 360, height: 574)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(amber)
        .sheet(isPresented: $light.showPreferences) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Preferências").font(.headline)
                Toggle("Abrir ao iniciar sessão", isOn: $light.launchAtLogin)
                    .onChange(of: light.launchAtLogin) { value in
                        do {
                            if value { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                        } catch {
                            light.launchAtLogin = SMAppService.mainApp.status == .enabled
                            light.error = "Não foi possível alterar a inicialização automática. Verifique Ajustes do Sistema → Geral → Itens de Início."
                        }
                    }
                Text("O Lume se conecta ao abrir, mas não altera os ajustes da luz automaticamente.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Concluído") { light.showPreferences = false }.buttonStyle(.borderedProminent).frame(maxWidth: .infinity, alignment: .trailing)
            }.padding(24).frame(width: 330)
        }
    }
    private var header: some View {
        HStack(spacing: 11) {
            Image(systemName: "sun.max.fill").font(.system(size: 19, weight: .medium))
                .foregroundStyle(amber).frame(width: 36, height: 36)
                .background(amber.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 2) {
                Text("Lume").font(.system(size: 16, weight: .semibold))
                Text("Controle da iluminação").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Button { light.showPreferences = true } label: { Image(systemName: "gearshape").font(.system(size: 15)) }
                .buttonStyle(.plain).foregroundStyle(.secondary).padding(6).help("Preferências")
                .accessibilityLabel("Preferências")
        }.padding(.horizontal, 20).padding(.vertical, 16)
    }
    private var controls: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(light.configuration?.name ?? "amaran 60x S").font(.system(size: 19, weight: .semibold)).lineLimit(2)
                    HStack(spacing: 5) {
                        Circle().fill(light.ready ? Color.green : Color.secondary.opacity(0.5)).frame(width: 5, height: 5)
                        Text(light.connection).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button { light.togglePower() } label: {
                    Image(systemName: "power").font(.system(size: 20, weight: .medium))
                        .frame(width: 46, height: 46)
                        .foregroundStyle(light.status?.on == true ? Color.white : Color.secondary)
                        .background(light.status?.on == true ? amber : Color.primary.opacity(0.05), in: Circle())
                }.buttonStyle(.plain).disabled(!light.canControl)
                    .help(light.status?.on == true ? "Apagar luz" : "Acender luz")
                    .accessibilityLabel(light.status?.on == true ? "Apagar luz" : "Acender luz")
            }
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 13) {
                    HStack(alignment: .firstTextBaseline) {
                        Label("Intensidade", systemImage: "sun.max").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                        Spacer()
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(light.status == nil ? "—" : String(format: "%.0f", light.desiredBrightness)).font(.system(size: 30, weight: .medium, design: .rounded)).monospacedDigit()
                            Text("%").font(.system(size: 13)).foregroundStyle(.secondary)
                        }
                    }
                    Slider(value: $light.desiredBrightness, in: 0...100, onEditingChanged: { editing in
                        if !editing { light.desiredBrightness = light.desiredBrightness.rounded(); light.setBrightness() }
                    }).disabled(!light.canControl || light.status?.on != true)
                        .accessibilityLabel("Intensidade").accessibilityValue("\(Int(light.desiredBrightness)) por cento")
                    HStack {
                        Text("Suave"); Spacer(); Text("Intensa")
                    }.font(.system(size: 10)).foregroundStyle(.tertiary)
                }.padding(16)
                Divider().padding(.horizontal, 16)
                VStack(alignment: .leading, spacing: 13) {
                    HStack(alignment: .firstTextBaseline) {
                        Label("Temperatura", systemImage: "thermometer.medium").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                        Spacer()
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(light.status == nil ? "—" : String(format: "%.0f", light.desiredKelvin)).font(.system(size: 24, weight: .medium, design: .rounded)).monospacedDigit()
                            Text("K").font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                    }
                    Slider(value: $light.desiredKelvin, in: 2700...6500, onEditingChanged: { editing in
                        if !editing { light.desiredKelvin = (light.desiredKelvin / 100).rounded() * 100; light.setKelvin() }
                    }).tint(Color(red: 0.72, green: 0.64, blue: 0.5)).disabled(!light.canControl || light.status?.on != true)
                        .accessibilityLabel("Temperatura de cor").accessibilityValue("\(Int(light.desiredKelvin)) kelvin")
                    HStack(spacing: 5) {
                        Circle().fill(Color(red: 1, green: 0.69, blue: 0.36)).frame(width: 6, height: 6)
                        Text("Quente · 2700 K"); Spacer(); Text("6500 K · Fria")
                        Circle().fill(Color(red: 0.66, green: 0.81, blue: 0.99)).frame(width: 6, height: 6)
                    }.font(.system(size: 10)).foregroundStyle(.tertiary)
                }.padding(16)
            }.background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 18))

            VStack(alignment: .leading, spacing: 10) {
                Text("AJUSTES RÁPIDOS").font(.system(size: 9, weight: .semibold)).tracking(1.3).foregroundStyle(.tertiary)
                HStack(spacing: 8) {
                    preset("Aconchego", symbol: "moon", kelvin: 3200, brightness: 25)
                    preset("Trabalho", symbol: "desktopcomputer", kelvin: 4300, brightness: 50)
                    preset("Gravação", symbol: "video", kelvin: 5600, brightness: 75)
                }
            }
            HStack(spacing: 6) {
                if light.pending { ProgressView().controlSize(.mini); Text("Aguardando confirmação…") }
                else if light.ready && light.status != nil {
                    Image(systemName: light.error == nil ? "checkmark.circle" : "clock")
                    Text(light.error == nil ? "Estado confirmado pela luz" : "Último estado recebido")
                }
                else if light.ready { ProgressView().controlSize(.mini); Text("Consultando estado da luz…") }
                else { Image(systemName: "bolt.slash"); Text("Conecte para ajustar sua luz") }
            }.font(.system(size: 10)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
        }
    }
    private func preset(_ title: String, symbol: String, kelvin: Double, brightness: Double) -> some View {
        Button { light.apply(kelvin: kelvin, brightness: brightness) } label: {
            VStack(spacing: 7) {
                Image(systemName: symbol).font(.system(size: 16, weight: .regular)).foregroundStyle(amber)
                Text(title).font(.system(size: 10, weight: .medium))
            }.frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).disabled(!light.canControl || light.status?.on != true)
            .help("\(Int(brightness))% · \(Int(kelvin)) K")
            .accessibilityLabel("\(title), \(Int(brightness)) por cento, \(Int(kelvin)) kelvin")
    }
    private var setup: some View {
        VStack(alignment: .leading, spacing: 16) {
            if light.pairing || light.connecting {
                VStack(alignment: .leading, spacing: 18) {
                    ProgressView().controlSize(.large).tint(amber)
                    Text("Conectando sua luz").font(.system(size: 23, weight: .semibold))
                    Text(light.connection).font(.system(size: 13)).foregroundStyle(.secondary)
                    Text("Mantenha a luz ligada e próxima ao Mac. Os ajustes de iluminação não serão alterados durante o pareamento.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
                    Button("Cancelar") { light.disconnect(); light.connection = "Conexão cancelada" }.buttonStyle(.bordered)
                }.padding(.vertical, 24)
            } else if !light.candidates.isEmpty {
                Text("Escolha sua luz").font(.system(size: 22, weight: .semibold))
                Text("Selecione a amaran 60x S que deseja controlar.").font(.system(size: 12)).foregroundStyle(.secondary)
                ForEach(light.candidates) { item in
                    Button { light.choose(item) } label: {
                        HStack { Image(systemName: "lightbulb").foregroundStyle(amber); Text(item.name); Spacer(); Image(systemName: "chevron.right").font(.caption) }
                            .padding(14).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain)
                }
            } else {
                ZStack {
                    Circle().fill(amber.opacity(0.08)).frame(width: 68, height: 68)
                    Image(systemName: "lightbulb.max").font(.system(size: 30, weight: .light)).foregroundStyle(amber)
                }.padding(.top, 4)
                Text("Conecte sua amaran").font(.system(size: 23, weight: .semibold)).tracking(-0.5)
                Text("Brilho e temperatura de cor,\nsempre à mão na barra de menus.")
                    .font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(3)
                VStack(alignment: .leading, spacing: 12) {
                    Label("Ligue a luz e aproxime o Mac.", systemImage: "1.circle")
                    Label("Busque e selecione a sua amaran.", systemImage: "2.circle")
                    Label("Conecte e faça seus ajustes.", systemImage: "3.circle")
                }.font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 5)
                Button { light.connect(pairingSearch: true) } label: {
                    Text(light.scanning ? "Buscando luzes…" : "Buscar minha amaran").frame(maxWidth: .infinity).padding(.vertical, 4)
                }.buttonStyle(.borderedProminent).controlSize(.large).tint(amber).foregroundStyle(.black)
                    .disabled(light.scanning)
                if !light.nearby.isEmpty {
                    ForEach(light.nearby.sorted(by: { $0.canPair && !$1.canPair })) { entry in
                        Button { light.pair(entry.id) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "lightbulb").foregroundStyle(amber)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.name).font(.system(size: 12, weight: .medium)).lineLimit(2)
                                    Text(entry.canPair ? "Pronta para parear" : "Já pareada · use BT Reset na luz").font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 2)
                                if entry.canPair { Image(systemName: "chevron.right").font(.system(size: 10)) }
                            }.padding(12).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain).disabled(!entry.canPair)
                    }
                } else if light.scanCompleted {
                    Text("Nenhuma luz detectada nesta busca. Ligue a luz e aproxime o Mac para tentar novamente.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                Text("Sem celular. Sem outro aplicativo.").font(.system(size: 11, weight: .semibold))
                Text("Se a luz guardar um vínculo antigo, use BT Reset nela e aguarde Success antes de buscar. Isso remove o pareamento anterior.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                Button(light.showAdvanced ? "Ocultar outras opções" : "Já tenho uma configuração…") { light.showAdvanced.toggle() }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
                if light.showAdvanced {
                    HStack {
                        Button("Sidus Link / arquivo…") { light.importIPhone() }
                        Spacer()
                        Button("amaran Desktop…") { light.importDesktop() }
                    }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            if light.configuration != nil { Button("Voltar ao controle") { light.showSetup = false }.buttonStyle(.plain).font(.caption) }
        }
    }
    private var footer: some View {
        HStack {
            if light.configuration != nil {
                Button { light.showSetup.toggle() } label: { Label("Conexão", systemImage: "antenna.radiowaves.left.and.right") }
                    .disabled(light.pending)
                Spacer()
                Button(light.ready ? "Atualizar" : "Reconectar") { if light.ready { light.requestStatus() } else { light.connect() } }
                    .disabled(light.scanning || light.connecting || light.pending)
                Divider().frame(height: 10).padding(.horizontal, 4)
            } else { Spacer() }
            Button("Sair", action: quit)
        }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.vertical, 13)
    }
}
