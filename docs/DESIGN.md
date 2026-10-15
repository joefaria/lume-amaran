# Lume 0.3 · Glass instrument panel

The creator requested an Apple-like native utility, a futuristic spaceflight identity, Phosphor icons, light/dark modes and a glass app icon. Visual references emphasized smoked glass, amber accents and restrained instrument scales.

## Decisions

- The main panel contains fixture identity, authenticated connection state, emitter power and two instrument surfaces: brightness and white temperature.
- Fixed presets, reconnect/refresh, connection setup, settings and quit remain accessible through the options menu. No features were removed from the protocol layer.
- SF system typography, semantic macOS foreground/background colors, native sliders, native menus and keyboard/accessibility labels.
- Native `glassEffect` on macOS 26+, with translucent material on macOS 13–15. Reduce Transparency and Increase Contrast use an opaque, outlined surface.
- Appearance follows macOS by default. Optional Claro/Escuro overrides are local to Lume and never change system preferences. This is an explicit customization beyond HIG's recommendation to generally follow the system.
- The menu bar uses a separate Phosphor planet SVG as an 18pt monochrome template. It uses system tinting rather than the full-color app icon.
- The app icon is original orbital glass/light artwork generated with the built-in image generation tool and packaged as a multi-resolution native icns. It is flattened artwork; it is not a layered Icon Composer asset.
- Decorative ruler ticks do not receive accessibility focus. Meaningful labels, numeric values, disabled state, errors and pending-command feedback remain available. No custom drag interaction or decorative animation replaces native controls.

## Sources

- [Apple HIG: menu bar extras](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar#Menu-bar-extras)
- [Apple HIG: Dark Mode](https://developer.apple.com/design/human-interface-guidelines/dark-mode)
- [Apple HIG: app icons](https://developer.apple.com/design/human-interface-guidelines/app-icons)
- [Phosphor Icons](https://github.com/phosphor-icons/core), bundled at the commit recorded in Resources/Phosphor/README.md. Original MIT notices are preserved.

Native app screenshots are used for final appearance review because offscreen bitmap capture does not faithfully reproduce the macOS glass compositor. The 65 protocol tests validate the unchanged transport, not the appearance.

## 0.3.1 · Temperature ambience

A soft, asymmetrical radial gradient sits above the root material and below all controls. Its palette interpolates amber (2700 K), warm neutral (4500 K), and pale blue (6500 K). This is an interface palette, not a calibrated spectral simulation. It uses confirmed `LightStatus.kelvin` and is visible only when the selected fixture is connected and reports its emitter on. Setup/settings, disconnected and off states stay neutral. Reduced transparency or increased contrast suppress the decoration; reduced motion suppresses the 450 ms transitions. No Bluetooth behavior changes.

## 0.3.2 · Continuous slider interaction

Ordinary brightness and temperature changes no longer disable the controls or replace the connection label with a spinner/Aplicando message. Authenticated confirmation remains internal. A bounded pipeline sends one command at a time, merging the latest unsent value for each control. CCT packets preserve the latest requested brightness. Slider gestures protect their displayed values from status polling and older acknowledgements until released. Real send failures/timeouts are still reported; disconnects cancel queued changes. The background gradient remains based on confirmed light state.

24 additional regression checks cover delayed/out-of-order confirmation, mixed brightness/CCT changes, bursts, rapid power changes, presets and cancellation. The total suite contains 89 checks.
