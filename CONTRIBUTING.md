# Contributing to Lume

Lume is a small native macOS menu bar app. Keep pairing, authenticated state reporting and persistent sequence counters intact when changing the Bluetooth code.

## Build and test

On an Apple Silicon Mac with Command Line Tools and Node installed:

```sh
zsh test.sh
zsh build.sh
```

Tests use published or synthetic cryptographic vectors and a simulated peer. They do not access Bluetooth or the macOS Keychain. The build produces `dist/Lume-macOS.zip`. See [README.md](README.md) for prerequisites and [COMPATIBILITY.md](COMPATIBILITY.md) for current limits.

## Report a light model

Open an issue with its exact model, firmware version if available, macOS version, Lume version, and which operations were actually confirmed: pairing, reconnecting, power, brightness and white temperature. State whether you used direct pairing or imported an existing network.

Do not attach mesh configuration exports, application databases, iPhone backups, Keychain contents, network/application/device keys or the contents of `.build/`. Remove device identifiers from logs. Pairing changes the light's Bluetooth network, so test with your own light and account for existing controllers before resetting it.

A report from another controller is useful context, but a model only moves to Lume's verified list after a real Lume test. When adding support, include the model's documented CCT limits and capabilities, handle unsupported controls in the UI, and add meaningful protocol vectors where behavior differs.

## Scope

Support for model profiles, fixed-white fixtures, color fixtures and multiple lights can be added separately. Avoid enabling untested features globally. This project is independent and is not affiliated with or endorsed by amaran or Aputure.

Contributions are made under the repository's MIT license. Preserve upstream notices in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
