import Foundation

/// One authenticated command in flight, with only the latest unsent value per
/// control retained. A temperature packet also sets brightness, so it must use
/// the latest queued brightness or the state confirmed after the previous send.
struct LightControlPipeline {
    enum Adjustment {
        case power(Bool), brightness(Double), temperature(Double)
        case preset(kelvin: Double, brightness: Double)
    }
    struct Transmission {
        enum Kind { case power, brightness, cct }
        let kind: Kind
        let target: LightStatus
        var payload: Bytes {
            switch kind {
            case .power: return Telink.power(target.on)
            case .brightness: return Telink.brightness(target.brightness)
            case .cct: return Telink.cct(target.kelvin, brightness: target.brightness)
            }
        }
        func matches(_ actual: LightStatus) -> Bool {
            switch kind {
            case .power: return target.on == actual.on
            case .brightness: return abs(target.brightness - actual.brightness) < 1
            case .cct: return abs(target.brightness - actual.brightness) < 1 && abs(target.kelvin - actual.kelvin) < 100
            }
        }
    }
    private(set) var inFlight: Transmission?
    private var power: Bool?
    private var brightness: Double?
    private var kelvin: Double?
    var pending: Bool { inFlight != nil || power != nil || brightness != nil || kelvin != nil }
    var requestedPower: Bool? { power ?? (inFlight?.kind == .power ? inFlight?.target.on : nil) }
    var holdsBrightness: Bool { brightness != nil || inFlight?.kind == .brightness || inFlight?.kind == .cct }
    var holdsKelvin: Bool { kelvin != nil || inFlight?.kind == .cct }

    mutating func enqueue(_ adjustment: Adjustment) {
        switch adjustment {
        case .power(let value): power = value
        case .brightness(let value): brightness = min(100, max(0, value))
        case .temperature(let value): kelvin = min(6500, max(2700, value))
        case .preset(let k, let b): kelvin = min(6500, max(2700, k)); brightness = min(100, max(0, b))
        }
    }
    mutating func takeNext(confirmed: LightStatus) -> Transmission? {
        guard inFlight == nil else { return nil }
        let next: Transmission
        if let on = power {
            power = nil
            next = Transmission(kind: .power, target: LightStatus(on: on, brightness: confirmed.brightness, kelvin: confirmed.kelvin))
        } else if let k = kelvin {
            let b = brightness ?? confirmed.brightness
            kelvin = nil; brightness = nil
            next = Transmission(kind: .cct, target: LightStatus(on: confirmed.on, brightness: b, kelvin: k))
        } else if let b = brightness {
            brightness = nil
            next = Transmission(kind: .brightness, target: LightStatus(on: confirmed.on, brightness: b, kelvin: confirmed.kelvin))
        } else { return nil }
        inFlight = next; return next
    }
    @discardableResult mutating func acknowledge(_ actual: LightStatus) -> Bool {
        guard let inFlight, inFlight.matches(actual) else { return false }
        self.inFlight = nil; return true
    }
    mutating func cancel() { self = Self() }
}
