import AppKit
import SwiftUI

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem!
    private var popover: NSPopover!
    private let light = LightController()
    private var renderer: NSWindow?
    private var operationTimer: Timer?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--render"), args.count > index + 2 {
            render(path: args[index + 1], state: args[index + 2], appearance: args.count > index + 3 ? args[index + 3] : "light"); return
        }
        if let index = args.firstIndex(of: "--diagnose"), args.count > index + 1 {
            diagnose(path: args[index + 1]); return
        }
        if let index = args.firstIndex(of: "--pair"), args.count > index + 2, let id = UUID(uuidString: args[index + 1]) {
            operate(path: args[index + 2], pair: id, test: false); return
        }
        if let index = args.firstIndex(of: "--verify-control"), args.count > index + 1 {
            operate(path: args[index + 1], pair: nil, test: true); return
        }
        for (argument, kind) in [("--verify-temperature", "temperature"), ("--verify-power", "power")] {
            if let index = args.firstIndex(of: argument), args.count > index + 1 {
                operate(path: args[index + 1], pair: nil, test: true, kind: kind); return
            }
        }
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: "dev.jonatas.lume")
        if running.count > 1 { NSApp.terminate(nil); return }
        NSApp.setActivationPolicy(.accessory)
        AppearanceSettings.shared.apply()
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = Phosphor.image("planet")
            button.image?.isTemplate = true; button.toolTip = "Lume — controle da amaran"
            button.target = self; button.action = #selector(toggle)
        }
        popover = NSPopover(); popover.behavior = .transient
        popover.contentSize = NSSize(width: Panel.width, height: Panel.height)
        popover.contentViewController = NSHostingController(rootView: Panel(light: light))
        light.restore()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.show() }
    }
    @objc private func toggle() { if popover.isShown { popover.performClose(nil) } else { show() } }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if popover != nil { show() }; return true
    }
    private func show() {
        guard let button = item.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
    func applicationWillTerminate(_ notification: Notification) { light.disconnect() }
    /// Development CLI for a selected light. Never chooses an arbitrary device.
    /// Reports only public connection state and light parameters, never mesh keys.
    private func operate(path: String, pair: UUID?, test: Bool, kind: String = "brightness") {
        NSApp.setActivationPolicy(.accessory)
        let began = Date(); var pairingStarted = false; var phase = 0
        var lastProgress = ""; var lastScan = began
        var original: Double?; var target: Double?; var changed = false
        if pair == nil { light.restore() } else { light.connect() }
        operationTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                func value(_ status: LightStatus) -> Double {
                    if kind == "temperature" { return status.kelvin }
                    if kind == "power" { return status.on ? 1 : 0 }
                    return status.brightness
                }
                @MainActor func apply(_ value: Double) {
                    if kind == "temperature" { self.light.desiredKelvin = value; self.light.setKelvin() }
                    else if kind == "power" { self.light.setPower(value > 0) }
                    else { self.light.desiredBrightness = value; self.light.setBrightness() }
                }
                let progress = "\(phase):\(self.light.connection):\(self.light.error ?? "")"
                if progress != lastProgress {
                    lastProgress = progress
                    let data = try? JSONSerialization.data(withJSONObject: ["phase": phase, "state": self.light.connection,
                        "error": self.light.error as Any? ?? NSNull()], options: [.sortedKeys])
                    if let data { try? data.write(to: URL(fileURLWithPath: path + ".progress.json"), options: .atomic) }
                }
                @MainActor func finish(_ failure: String? = nil) {
                    self.operationTimer?.invalidate()
                    var result: [String: Any] = ["mode": pair == nil ? "verify-\(kind)" : "pair", "state": self.light.connection,
                        "confirmed": self.light.ready && self.light.status != nil, "adjustmentConfirmed": changed,
                        "error": failure as Any? ?? self.light.error as Any? ?? NSNull(), "diagnostics": self.light.diagnostics]
                    if let status = self.light.status {
                        result["light"] = ["on": status.on, "brightness": status.brightness, "kelvin": status.kelvin]
                    }
                    if let original { result["originalValue"] = original }
                    if let target { result["testedValue"] = target }
                    result["savedPeripheral"] = self.light.configuration?.peripheralUUID as Any? ?? NSNull()
                    do {
                        let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
                        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
                        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
                        self.light.disconnect(); exit(failure == nil && result["confirmed"] as? Bool == true ? 0 : 1)
                    } catch { self.light.disconnect(); exit(1) }
                }
                if let pair, !pairingStarted,
                   self.light.nearby.contains(where: { $0.id == pair && $0.canPair }) {
                    pairingStarted = true; self.light.pair(pair)
                }
                if pair != nil, !pairingStarted, self.light.scanCompleted, Date().timeIntervalSince(lastScan) > 15 {
                    lastScan = Date(); self.light.connect()
                }
                if self.light.canControl, self.light.error == nil, let status = self.light.status {
                    if !test || (phase == 0 && !status.on && kind != "power") { finish(); return }
                    if phase == 0 {
                        original = value(status)
                        if kind == "temperature" { target = status.kelvin < 6500 ? status.kelvin + 100 : status.kelvin - 100 }
                        else if kind == "power" { target = status.on ? 0 : 1 }
                        else { target = status.brightness >= 5 ? status.brightness - 5 : status.brightness + 5 }
                        apply(target!); phase = 1
                    } else if phase == 1, let target, abs(value(status) - target) < 0.1 {
                        changed = true; apply(original!); phase = 2
                    } else if phase == 2, let original, abs(value(status) - original) < 0.1 {
                        finish(); return
                    }
                }
                if let error = self.light.error, !self.light.pending, (pairingStarted || pair == nil) {
                    // If an adjustment lost its acknowledgement, restore the
                    // explicit original value before reporting the failure.
                    if test, phase == 1, self.light.canControl, let original {
                        apply(original); phase = 2
                    } else { finish(error); return }
                }
                if Date().timeIntervalSince(began) > 80 { finish("Tempo esgotado. A conexão física ainda não foi confirmada.") }
            }
        }
    }
    private func diagnose(path: String) {
        NSApp.setActivationPolicy(.accessory)
        light.connect()
        DispatchQueue.main.asyncAfter(deadline: .now() + 13) {
            let result: [String: Any] = ["state": self.light.connection, "error": self.light.error as Any? ?? NSNull(),
                "devices": self.light.nearby.map { ["id": $0.id.uuidString, "name": $0.name, "readyToPair": $0.canPair, "rssi": $0.rssi] as [String: Any] }]
            do {
                let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
                try data.write(to: URL(fileURLWithPath: path), options: .atomic)
                self.light.disconnect(); exit(0)
            } catch { self.light.disconnect(); exit(1) }
        }
    }
    private func render(path: String, state: String, appearance: String) {
        NSApp.setActivationPolicy(.accessory); light.preview = true
        NSApp.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
        if state != "setup" && state != "search" {
            light.configuration = LightConfiguration(name: "amaran 60x S", netKey: "", appKey: "", address: 2)
            light.ready = state != "offline"; light.connection = state == "offline" ? "Luz desconectada" : "Conectada"
            if state != "offline" {
                light.status = LightStatus(on: true, brightness: 65, kelvin: 4300)
                light.lastConfirmed = Date(); light.desiredBrightness = 65; light.desiredKelvin = 4300
            }
        }
        if state == "error" {
            light.error = "A conexão foi interrompida. Clique em Reconectar para tentar novamente."
            light.ready = false; light.status = nil; light.lastConfirmed = nil; light.connection = "Luz desconectada"
        }
        if state == "pending" { light.pending = true }
        if state == "off" { light.status = LightStatus(on: false, brightness: 65, kelvin: 4300) }
        if state == "preferences" { light.showPreferences = true }
        if state == "search" {
            light.scanCompleted = true
            light.nearby = [NearbyLight(id: UUID(), name: "Mesh Device", rssi: -40, canPair: true)]
        }
        let host = NSHostingView(rootView: Panel(light: light)); host.frame = NSRect(x: 0, y: 0, width: Panel.width, height: Panel.height)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSApp.appearance
        window.contentView = host; window.orderFront(nil); renderer = window
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            host.layoutSubtreeIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { exit(1) }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            guard let data = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
            do { try data.write(to: URL(fileURLWithPath: path)); exit(0) } catch { exit(1) }
        }
    }
}

@main struct LumeApp {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate(); application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
