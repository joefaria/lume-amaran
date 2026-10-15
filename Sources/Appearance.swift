import AppKit
import Combine

/// Local app preference only. System appearance remains the default.
@MainActor final class AppearanceSettings: ObservableObject {
    static let shared = AppearanceSettings()
    @Published private(set) var mode = UserDefaults.standard.string(forKey: "appearance") ?? "system"
    func select(_ value: String) {
        guard ["system", "light", "dark"].contains(value) else { return }
        mode = value; UserDefaults.standard.set(value, forKey: "appearance"); apply()
    }
    func apply() {
        if mode == "light" { NSApp.appearance = NSAppearance(named: .aqua) }
        else if mode == "dark" { NSApp.appearance = NSAppearance(named: .darkAqua) }
        else { NSApp.appearance = nil }
    }
}
