import AppKit
import CoreBluetooth
import Combine
import ServiceManagement

struct NearbyLight: Identifiable { let id: UUID; let name: String; let rssi: Int; let canPair: Bool }

// CoreBluetooth delegates are delivered on the explicitly selected main queue.
@MainActor final class LightController: NSObject, ObservableObject, @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    @Published var configuration: LightConfiguration?
    @Published var status: LightStatus?
    @Published var connection = "Nenhuma luz conectada"
    @Published var error: String?
    @Published var scanning = false
    @Published var scanCompleted = false
    @Published var connecting = false
    @Published var pairing = false
    @Published var showAdvanced = false
    @Published var ready = false
    @Published var pending = false
    @Published var nearby: [NearbyLight] = []
    @Published var candidates: [LightConfiguration] = []
    @Published var showSetup = false
    @Published var showPreferences = false
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var lastConfirmed: Date?
    @Published var desiredBrightness: Double = 50
    @Published var desiredKelvin: Double = 5600
    var editingBrightness = false
    var editingKelvin = false
    var preview = false
    private(set) var diagnostics: [String: Any] = [:]
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var input: CBCharacteristic?
    private var mesh: Mesh?
    private var sequence: SequenceStore?
    private var timer: Timer?
    private var timeout: DispatchWorkItem?
    private var pendingTimeout: DispatchWorkItem?
    private var ivVerified = false
    private var filterSent = false
    private var rx: Bytes = []
    private var rxType: UInt8?
    private var rxTime = Date.distantPast
    private var queue: [Data] = []
    private var writing = false
    private var requestedScan = false
    private var controls = LightControlPipeline()
    private var commandStatusRequest: DispatchWorkItem?
    private let proxy = CBUUID(string: "1828")
    private let provisioning = CBUUID(string: "1827")
    private var discovered: [UUID: CBPeripheral] = [:]
    private var pairingSession: LightPairing?
    private var pairingName = "amaran 60x S"
    private var switchingToProxy = false
    private var configStage = 0
    private var binding: VendorBinding?
    private var deviceReceiver = DeviceAccessReceiver()
    private var configRetry: DispatchWorkItem?
    private var configAttempts = 0
    private var configMessage: Bytes = []
    private var setupScan = false
    var canControl: Bool { ready && status != nil && !showSetup }

    override init() { super.init() }
    func restore() {
        do {
            if let stored = try CredentialStore.load() { try configure(stored, occupied: [stored.address]); connect() }
        } catch { self.error = "Não foi possível restaurar a configuração. Importe novamente para continuar." }
    }
    func pair(_ id: UUID) {
        guard !connecting, !pairing, let selected = discovered[id],
              let entry = nearby.first(where: { $0.id == id && $0.canPair }) else { return }
        do {
            let session = try LightPairing()
            disconnect(); error = nil; showSetup = true
            pairingSession = session; pairingName = entry.name
            pairing = true; connecting = true; connection = "Conectando à luz…"
            peripheral = selected; selected.delegate = self
            central?.connect(selected)
            armTimeout(45) { [weak self] in self?.fail("O pareamento não foi concluído. Aproxime a luz e tente novamente.") }
        } catch { self.error = error.localizedDescription }
    }
    private func savePairingBeforeCommit(_ session: LightPairing) throws {
        guard let deviceKey = session.deviceKey else { throw LumeError.message("A chave de conexão da luz ainda não foi criada.") }
        let derived = try Mesh(net: session.netKey, app: session.appKey)
        let reserved = try SequenceStore(network: derived.networkID.hex, occupied: [session.address])
        let stored = LightConfiguration(name: pairingName == "Mesh Device" ? "amaran 60x S" : pairingName,
                                        netKey: session.netKey.hex, appKey: session.appKey.hex,
                                        address: session.address, source: reserved.state.source, deviceKey: deviceKey.hex,
                                        needsConfiguration: true, peripheralUUID: peripheral?.identifier.uuidString)
        try CredentialStore.save(stored)
        configuration = stored; mesh = derived; sequence = reserved
    }
    private func finishPairing() {
        guard configuration?.needsConfiguration == true, let peripheral else { fail("Não foi possível recuperar a configuração do pareamento."); return }
        pairingSession = nil; switchingToProxy = true
        connection = "Verificando pareamento…"
        central?.cancelPeripheralConnection(peripheral)
        armTimeout(8) { [weak self] in self?.fail("Reconecte para continuar a configuração da luz.") }
    }
    func configure(_ selected: LightConfiguration, occupied: [UInt16]) throws {
        let selected = try selected.validated(); let derived = try selected.mesh
        let reserved = try SequenceStore(network: derived.networkID.hex, occupied: occupied)
        var stored = selected; stored.source = reserved.state.source
        try CredentialStore.save(stored)
        disconnect()
        configuration = stored; mesh = derived; sequence = reserved; status = nil; lastConfirmed = nil
        candidates = []; error = nil; showSetup = false
    }
    func choose(_ selected: LightConfiguration) {
        do { try configure(selected, occupied: candidates.map(\.address)); connect() }
        catch { self.error = "Não foi possível salvar a conexão. \(error.localizedDescription)" }
    }
    func importFile() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.title = "Importar configuração da luz"; panel.message = "Selecione amaran.db ou uma exportação JSON compatível."
        panel.begin { [weak self] result in
            guard result == .OK, let url = panel.url else { return }
            Task { @MainActor in self?.load(url) }
        }
    }
    func importIPhone() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = true
        panel.allowsMultipleSelection = false; panel.title = "Importar configuração do Sidus Link"
        panel.message = "Escolha uma exportação JSON ou uma pasta de backup local do iPhone. Apenas os dados de iluminação do Sidus Link serão lidos."
        panel.begin { [weak self] result in
            guard result == .OK, let url = panel.url else { return }
            Task { @MainActor in
                var directory: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &directory), directory.boolValue {
                    do {
                        let values = try ConfigurationImport.iphoneBackup(url)
                        self?.candidates = values; self?.showSetup = true; self?.error = nil
                    } catch { self?.error = error.localizedDescription }
                } else { self?.load(url) }
            }
        }
    }
    func load(_ url: URL) {
        do {
            let values = url.pathExtension.lowercased() == "json" ? try ConfigurationImport.json(Data(contentsOf: url)) : try ConfigurationImport.database(url.path)
            guard !values.isEmpty else { throw LumeError.message("Nenhuma luz foi encontrada nesse arquivo.") }
            candidates = values; showSetup = true; error = nil
        } catch { self.error = error.localizedDescription }
    }
    func importDesktop() {
        let files = ConfigurationImport.localDatabases()
        if files.count == 1 { load(files[0]) }
        else if files.count > 1 { importFile() }
        else { error = "Não encontrei uma configuração do amaran Desktop neste Mac. Você pode escolher um arquivo compatível." }
    }
    func connect(pairingSearch: Bool = false) {
        guard !preview else { return }
        setupScan = pairingSearch
        error = nil; requestedScan = true
        if central == nil { central = CBCentralManager(delegate: self, queue: .main) }
        else if central?.state == .poweredOn { scan() }
        else { updateBluetoothState() }
    }
    func scan() {
        guard central?.state == .poweredOn else { return }
        if let peripheral { central?.cancelPeripheralConnection(peripheral); self.peripheral = nil }
        ready = false; status = nil; input = nil; queue = []; writing = false
        nearby = []; discovered = [:]; ivVerified = false; filterSent = false; scanning = true; scanCompleted = false
        connection = configuration == nil || setupScan ? "Buscando luzes próximas…" : "Procurando sua luz…"
        // Use CoreBluetooth's persisted peripheral identity on reconnect. Some
        // Telink proxies don't immediately resume advertising after a disconnect.
        if !setupScan, let text = configuration?.peripheralUUID, let id = UUID(uuidString: text),
           let known = central?.retrievePeripherals(withIdentifiers: [id]).first {
            self.peripheral = known; known.delegate = self; scanning = false; connecting = true
            connection = "Reconectando à sua luz…"; central?.connect(known)
            armTimeout(18) { [weak self] in self?.fail("A luz não respondeu à reconexão. Verifique se ela está ligada e próxima ao Mac.") }
            return
        }
        central?.scanForPeripherals(withServices: [proxy, provisioning], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        armTimeout(12) { [weak self] in
            guard let self else { return }; self.central?.stopScan(); self.scanning = false; self.scanCompleted = true
            self.connection = self.configuration == nil || self.setupScan ? "Busca concluída" : "Luz não encontrada"
            if self.configuration != nil && !self.setupScan { self.error = "Ligue a luz e aproxime o Mac. Se tiver usado BT Reset novamente, faça um novo pareamento em Conexão." }
        }
    }
    func disconnect() {
        controls.cancel(); commandStatusRequest?.cancel()
        editingBrightness = false; editingKelvin = false
        requestedScan = false; central?.stopScan(); timeout?.cancel(); pendingTimeout?.cancel(); timer?.invalidate(); configRetry?.cancel()
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        peripheral = nil; input = nil; queue = []; writing = false; ready = false; scanning = false; pending = false; connecting = false
        ivVerified = false; filterSent = false; rx = []; rxType = nil
        pairing = false; pairingSession = nil; switchingToProxy = false; configStage = 0; binding = nil; deviceReceiver = DeviceAccessReceiver()
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        updateBluetoothState()
        if central.state == .poweredOn && requestedScan { scan() }
    }
    private func updateBluetoothState() {
        switch central?.state {
        case .unauthorized:
            connection = "Permissão de Bluetooth necessária"
            error = "Permita o Bluetooth para o Lume em Ajustes do Sistema → Privacidade e Segurança → Bluetooth."
        case .poweredOff: connection = "Bluetooth desligado"; error = "Ative o Bluetooth do Mac para conectar sua luz."
        case .unsupported: connection = "Bluetooth indisponível"; error = "Este Mac não oferece a conexão Bluetooth necessária."
        case .resetting: connection = "Reiniciando Bluetooth…"
        case .poweredOn: break
        default: connection = "Preparando Bluetooth…"
        }
        if central?.state != .poweredOn {
            ready = false; scanning = false; status = nil; timer?.invalidate()
            controls.cancel(); pending = false; pendingTimeout?.cancel(); commandStatusRequest?.cancel()
        }
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let serviceIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let data = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data] ?? [:]
        let canPair = serviceIDs.contains(provisioning) || data[provisioning] != nil
        discovered[peripheral.identifier] = peripheral
        if !nearby.contains(where: { $0.id == peripheral.identifier }) {
            let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? "Luz Bluetooth · \(peripheral.identifier.uuidString.suffix(4))"
            nearby.append(NearbyLight(id: peripheral.identifier, name: name, rssi: RSSI.intValue, canPair: canPair))
        }
        guard !setupScan, let mesh, let configuration, self.peripheral == nil else { return }
        let identity = data[proxy].map { Bytes($0) } ?? []
        let networkMatches = identity.count == 9 && identity.first == 0 && Array(identity.dropFirst()) == mesh.networkID
        let knownPeer = configuration.peripheralUUID == peripheral.identifier.uuidString && (serviceIDs.contains(proxy) || data[proxy] != nil)
        // Freshly provisioned nodes may advertise Node Identity for a minute.
        // A stored peripheral ID selects that same node; its authenticated beacon
        // must still verify our network before we send any configuration.
        guard networkMatches || knownPeer else { return }
        central.stopScan(); timeout?.cancel(); scanning = false; connecting = true; self.peripheral = peripheral
        peripheral.delegate = self; connection = "Conectando…"; central.connect(peripheral)
        armTimeout(15) { [weak self] in self?.fail("A conexão demorou mais que o esperado. Tente novamente.") }
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard peripheral === self.peripheral else { return }
        connection = pairingSession == nil ? "Verificando conexão…" : "Preparando pareamento…"
        peripheral.discoverServices([pairingSession == nil ? proxy : provisioning])
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard peripheral === self.peripheral else { return }; fail("Não foi possível conectar à luz. Aproxime o Mac e tente novamente.")
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard peripheral === self.peripheral else { return }
        if switchingToProxy || (pairingSession?.stage == .complete && configuration?.needsConfiguration == true) {
            disconnect(); showSetup = true; connection = "Verificando pareamento…"; connect(); return
        }
        disconnect(); status = nil; connection = "Luz desconectada"
        self.error = "A conexão foi interrompida. Clique em Reconectar para tentar novamente."
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard peripheral === self.peripheral else { return }
        let expected = pairingSession == nil ? proxy : provisioning
        guard error == nil, let service = peripheral.services?.first(where: { $0.uuid == expected }) else { fail("A luz não disponibilizou o serviço esperado. Verifique o modo Bluetooth dela."); return }
        let uuids = pairingSession == nil ? [CBUUID(string: "2ADD"), CBUUID(string: "2ADE")] : [CBUUID(string: "2ADB"), CBUUID(string: "2ADC")]
        peripheral.discoverCharacteristics(uuids, for: service)
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard peripheral === self.peripheral else { return }
        diagnostics["service"] = service.uuid.uuidString
        diagnostics["characteristics"] = service.characteristics?.map { ["uuid": $0.uuid.uuidString, "properties": $0.properties.rawValue] as [String: Any] }
        let inUUID = CBUUID(string: pairingSession == nil ? "2ADD" : "2ADB")
        let outUUID = CBUUID(string: pairingSession == nil ? "2ADE" : "2ADC")
        guard error == nil, let input = service.characteristics?.first(where: { $0.uuid == inUUID }),
              let output = service.characteristics?.first(where: { $0.uuid == outUUID }),
              input.properties.contains(.write) || input.properties.contains(.writeWithoutResponse) else {
            fail("Não foi possível preparar o controle da luz."); return
        }
        self.input = input; peripheral.setNotifyValue(true, for: output)
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral === self.peripheral else { return }
        if error != nil { fail("A luz não permitiu receber atualizações.") }
        else if characteristic.isNotifying {
            if let session = pairingSession {
                do { connection = session.progress; try enqueue([3] + session.invite()) }
                catch { fail(error.localizedDescription) }
            } else { connection = "Confirmando identidade da luz…" }
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral === self.peripheral, error == nil, let bytes = characteristic.value.map({ Bytes($0) }), !bytes.isEmpty else { return }
        let sar = bytes[0] >> 6; let type = bytes[0] & 0x3f
        if sar == 0 { rx = []; rxType = nil; receive(bytes) }
        else if sar == 1 { rx = Array(bytes.dropFirst()); rxType = type; rxTime = Date() }
        else {
            guard rxType == type, Date().timeIntervalSince(rxTime) < 8, rx.count + bytes.count <= 512 else { rx = []; rxType = nil; return }
            rx += bytes.dropFirst()
            if sar == 3 { let complete = [type] + rx; rx = []; rxType = nil; receive(complete) }
        }
    }
    private func receive(_ p: Bytes) {
        if let session = pairingSession {
            guard p.first == 3 else { return }
            do {
                let outgoing = try session.receive(Array(p.dropFirst()))
                if outgoing.contains(where: { $0.first == 7 }) { try savePairingBeforeCommit(session) }
                connection = session.progress
                for item in outgoing { try enqueue([3] + item) }
                if session.stage == .done { finishPairing() }
            } catch { fail(error.localizedDescription) }
            return
        }
        guard let mesh, let sequence, let config = configuration else { return }
        if let (networkIV, updating) = mesh.beacon(p) {
            guard !updating else { fail("A luz está atualizando a conexão Bluetooth. Aguarde e reconecte."); return }
            do {
                try sequence.updateIV(networkIV); ivVerified = true
                if !filterSent { filterSent = true; try enqueue(mesh.filter(sequence: sequence.take(), source: sequence.state.source, iv: sequence.state.iv)) }
            } catch { fail("Não foi possível confirmar a configuração Bluetooth.") }; return
        }
        guard ivVerified else { return }
        if p.first == 2,
           let (_, _, _, body) = try? mesh.decodeNetwork(p, iv: sequence.state.iv), body.count == 6,
           Array(body.prefix(4)) == [0, 0, 3, 1] {
            timeout?.cancel(); self.error = nil
            if config.needsConfiguration == true {
                if configStage == 0 { configStage = 1; connection = "Preparando controles da luz…"; issueConfig([0x80, 8, 0]) }
            } else { markReady() }
            return
        }
        if config.needsConfiguration == true { receiveConfig(p); return }
        if p.first == 0, let actual = mesh.status(p, iv: sequence.state.iv, target: config.address) {
            status = actual; lastConfirmed = Date()
            if controls.acknowledge(actual) {
                pendingTimeout?.cancel(); commandStatusRequest?.cancel(); self.error = nil
                sendNextAdjustment()
            }
            pending = controls.pending
            synchronizeControls()
        }
    }
    private func markReady() {
        ready = true; pairing = false; connecting = false; showSetup = false; timeout?.cancel(); configRetry?.cancel(); connection = "Conectada"
        requestStatus()
        timer?.invalidate(); timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.requestStatus() }
        }
    }
    private func issueConfig(_ message: Bytes) {
        configRetry?.cancel(); configMessage = message; configAttempts = 0; transmitConfig()
    }
    private func transmitConfig() {
        guard let mesh, let sequence, let config = configuration, let key = config.deviceKey else { fail("A configuração da conexão está incompleta."); return }
        do {
            let numbers = try (0..<Mesh.devicePacketCount(configMessage.count)).map { _ in try sequence.take() }
            let messages = try mesh.devicePackets(configMessage, deviceKey: Bytes(hex: key), sequences: numbers,
                                                   source: sequence.state.source, target: config.address, iv: sequence.state.iv)
            for message in messages { try enqueue(message) }
            configAttempts += 1
            let retry = DispatchWorkItem { [weak self] in
                guard let self else { return }
                if self.configAttempts < 3 { self.transmitConfig() }
                else { self.fail("A luz não confirmou a configuração. Reconecte para continuar; o pareamento foi salvo.") }
            }
            configRetry = retry; DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: retry)
        } catch { fail(error.localizedDescription) }
    }
    private func receiveConfig(_ pdu: Bytes) {
        guard let mesh, let sequence, var config = configuration, let key = config.deviceKey else { return }
        do {
            guard let result = try deviceReceiver.receive(pdu, mesh: mesh, deviceKey: Bytes(hex: key), iv: sequence.state.iv,
                                                          target: config.address, source: sequence.state.source) else { return }
            if let zero = result.ack {
                try enqueue(mesh.acknowledgement(zero: zero, block: result.block, sequence: sequence.take(), source: sequence.state.source,
                                                target: config.address, iv: sequence.state.iv))
            }
            let access = result.access
            if configStage == 1 && access.first == 2 {
                binding = try VendorBinding.fromComposition(access, primary: config.address)
                configStage = 2; connection = "Habilitando os controles…"
                issueConfig([0, 0, 0, 0] + mesh.appKey)
            } else if configStage == 2 && access.count == 6 && Array(access.prefix(2)) == [0x80, 3] {
                guard access[2] == 0, Array(access.suffix(3)) == [0, 0, 0], let binding else { throw LumeError.message("A luz não aceitou a configuração de controle.") }
                configStage = 3; issueConfig(binding.message)
            } else if configStage == 3 && Array(access.prefix(2)) == [0x80, 0x3e] {
                guard let binding, binding.matches(access) else { throw LumeError.message("A luz não confirmou a habilitação dos controles.") }
                config.needsConfiguration = false; try CredentialStore.save(config)
                configuration = config; configStage = 0; markReady()
            }
        } catch { fail(error.localizedDescription) }
    }
    private func enqueue(_ bytes: Bytes) throws {
        guard let peripheral, let input else { throw LumeError.message("Conecte a luz para continuar.") }
        let writeType: CBCharacteristicWriteType = input.properties.contains(.write) ? .withResponse : .withoutResponse
        let maxChunk = peripheral.maximumWriteValueLength(for: writeType) - 1
        guard maxChunk >= 19, !bytes.isEmpty else { throw LumeError.message("Conexão Bluetooth incompatível.") }
        let type = bytes[0] & 0x3f; let body = Array(bytes.dropFirst())
        if body.count <= maxChunk { queue.append(Data(bytes)) }
        else {
            for start in stride(from: 0, to: body.count, by: maxChunk) {
                let end = min(body.count, start + maxChunk)
                let sar: UInt8 = start == 0 ? 0x40 : (end == body.count ? 0xc0 : 0x80)
                queue.append(Data([sar | type] + body[start..<end]))
            }
        }
        _ = input; drain()
    }
    private func drain() {
        guard !writing, !queue.isEmpty, let peripheral, let input else { return }
        if input.properties.contains(.write) {
            writing = true; peripheral.writeValue(queue.removeFirst(), for: input, type: .withResponse)
        } else {
            while !queue.isEmpty && peripheral.canSendWriteWithoutResponse {
                peripheral.writeValue(queue.removeFirst(), for: input, type: .withoutResponse)
            }
        }
    }
    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        guard peripheral === self.peripheral else { return }; drain()
    }
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral === self.peripheral else { return }; writing = false
        if error != nil { fail("O comando não pôde ser enviado. Reconecte a luz.") } else { drain() }
    }
    private func send(_ payload: Bytes) throws {
        guard ready, ivVerified, let config = configuration, let mesh, let sequence else { throw LumeError.message("A conexão ainda não está pronta.") }
        try enqueue(mesh.packet(payload, sequence: sequence.take(), source: sequence.state.source, target: config.address, iv: sequence.state.iv))
    }
    func requestStatus() {
        guard ready else { return }
        do { try send(Telink.status()) } catch { fail("Não foi possível consultar a luz.") }
    }
    func togglePower() {
        guard canControl, let status else { return }
        setPower(!(controls.requestedPower ?? status.on))
    }
    func setPower(_ on: Bool) {
        submit(.power(on))
    }
    func setBrightness() {
        submit(.brightness(desiredBrightness))
    }
    func setKelvin() {
        submit(.temperature(desiredKelvin))
    }
    func apply(kelvin: Double, brightness: Double) {
        guard canControl else { return }
        desiredKelvin = kelvin; desiredBrightness = brightness
        submit(.preset(kelvin: kelvin, brightness: brightness))
    }
    private func submit(_ adjustment: LightControlPipeline.Adjustment) {
        guard canControl else { return }
        error = nil; controls.enqueue(adjustment); pending = controls.pending
        sendNextAdjustment()
    }
    private func synchronizeControls() {
        guard let status else { return }
        if !editingBrightness && !controls.holdsBrightness { desiredBrightness = status.brightness }
        if !editingKelvin && !controls.holdsKelvin { desiredKelvin = status.kelvin }
    }
    private func sendNextAdjustment() {
        guard let status, let next = controls.takeNext(confirmed: status) else { return }
        do {
            pending = true
            try send(next.payload)
            commandStatusRequest?.cancel()
            let query = DispatchWorkItem { [weak self] in self?.requestStatus() }
            commandStatusRequest = query; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: query)
            pendingTimeout?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.controls.cancel(); self.pending = false; self.commandStatusRequest?.cancel(); self.synchronizeControls()
                self.error = "O ajuste foi enviado, mas a luz ainda não confirmou. Atualize o estado antes de tentar novamente."
            }; pendingTimeout = work; DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
        } catch {
            controls.cancel(); pending = false; pendingTimeout?.cancel(); commandStatusRequest?.cancel()
            synchronizeControls(); self.error = error.localizedDescription
        }
    }
    private func armTimeout(_ seconds: Double, _ callback: @escaping @MainActor () -> Void) {
        timeout?.cancel(); let work = DispatchWorkItem { callback() }; timeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }
    private func fail(_ message: String) { disconnect(); status = nil; connection = "Sem conexão"; error = message }
}
