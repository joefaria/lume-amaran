# Light compatibility

Lume 0.3.0 was tested with one **amaran 60x S**. It is not a universal amaran controller yet.

| Model or capability | Status in Lume |
| --- | --- |
| amaran 60x S: direct pairing and reconnect | Verified on real hardware |
| amaran 60x S: emitter power, brightness, CCT | Verified on real hardware |
| Other amaran models | Unverified; adaptation may be possible |
| Fixed-white lights | No dedicated profile; CCT controls need to be hidden |
| RGB/HSI, green/magenta, effects and battery | Not implemented |
| Multiple lights, groups or shared studio scenes | Not implemented; one saved light |
| Apple Silicon, macOS 13+ | Current build target; tested on the development Mac |
| Intel Macs | No build or hardware validation in this release |

## Why other models may be adaptable

The connection and cryptographic layers implement Bluetooth Mesh PB-GATT provisioning and a Mesh Proxy connection. Physical light control uses the amaran/Telink vendor protocol, rather than the standard SIG light models alone. Other public implementations use this protocol for several amaran fixtures:

- [neyako/amaran-hacs supported lights](https://github.com/neyako/amaran-hacs#supported-lights) reports 60x S, 100x, 100x S, Verge Max and other fixtures. Those are **that project's** results, not Lume validation.
- [wesbos/amaran-BLE-control](https://github.com/wesbos/amaran-BLE-control) documents power, brightness, CCT and HSI payloads.

This suggests reuse of Lume's transport for compatible fixtures; it does not establish that pairing, responses, firmware or all controls match on every model. Bluetooth or Sidus Link support alone is not enough to claim compatibility.

## Current assumptions that need changing for broader support

- `Sources/Mesh.swift` clamps white temperature to **2700–6500 K**, the 60x S range. The UI in `Sources/Panel.swift` uses the same range and fixed presets.
- A newly provisioned device advertising the generic name `Mesh Device` is named `amaran 60x S`. That label is a fallback, not model detection.
- `VendorBinding.fromComposition` selects the first vendor model on the primary element and rejects vendor models found only on another element. It does not identify arbitrary fixture capabilities.
- Pairing uses algorithm 0, in-band P-256 public keys and no OOB. Devices that require another provisioning method need additional implementation.
- `LightStatus` and the current decoder cover power, brightness and CCT. Color modes or different status messages need explicit decoding and confirmation.
- The Keychain stores one selected light. More fixtures require a multi-light configuration and UI.

To support another model, add its profile and control limits, verify the vendor model and status format, then exercise pairing, reconnecting and each supported control on real hardware. Keep unsupported models marked experimental until those checks pass.

## Hardware validation record

On 2026-10-15, direct pairing, authenticated status and reconnection in a new process were confirmed with a real 60x S. Tests changed brightness 20% → 15% → 20%, CCT 4500 K → 4600 K → 4500 K, and power on → off → on. Each operation received a matching status from the light. Firmware version was not recorded, so this is not a claim about every firmware release. There are also 65 automated protocol, authentication, provisioning, import and persistence checks; these do not replace hardware validation.
