# USB-only OpenDisplay fork

This unofficial GPL-3.0 fork supplies the bundled display engine for CablePanel
(the personal fork of Vorssaint). It is based on upstream commit
45bae1fb95439785e710cad281ad7cdc7082e272.

## Security boundary

The Mac engine accepts only a manually selected, physically attached Apple USB
device. `Usbmux.device` rejects Network-paired devices. The only connection
constructor in the compiled sender transport is the Unix-domain socket
`/var/run/usbmuxd`; there is no host/port option, Bonjour browser, Wi-Fi fallback,
UDP cursor socket, remote updater or auto-connect. Cable removal ends the session.
Touch input is off by default. Its coordinates and scroll magnitudes are bounded.

The fork's iOS receiver binds **127.0.0.1:9000**, rejects non-loopback peers,
prohibits Wi-Fi/cellular/Ethernet interfaces, publishes no Bonjour service and
starts no UDP listener. Cursor information uses the existing USB byte stream.
The receiver rejects frames larger than 32 MiB. The iOS identity is separate from
the App Store build and it does not fetch the upstream force-update manifest.

The official App Store receiver can work with the USB sender, but it still has
its own network listener. For the complete USB-only boundary, install this fork's
iOS receiver, or switch off iPhone Wi-Fi in Settings while using the existing app over USB. Never
interpret a USB connection to the official receiver as proof that its Wi-Fi
listener is off.

No cryptographic peer pairing is added. The trusted physical device and local
usbmuxd daemon remain part of the trust boundary. Private CoreGraphics virtual
display APIs and upstream capture threading remain compatibility risks.
Android and Linux sources are retained as upstream reference code; CablePanel
does not build or bundle them. They are outside this USB-only Apple product.

## Build and verify

```sh
./tools/build-usb-engine.sh
python3 tools/test-usb-engine.py
xcodegen generate
xcodebuild -project OpenSidecar.xcodeproj -scheme OpenSidecarMac \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
xcodebuild -project OpenSidecar.xcodeproj -scheme OpenSidecariOS \
  -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build
```

Run `build/USBDisplayEngine --control-stdio` only from a controller that keeps
stdin open. It emits JSON state lines and accepts `connect`, `stop`, `permission`
and `quit`. EOF stops capture and exits. `connect` requires a currently attached
USB UDID, mode `extend` or `mirror`, and optional `touch: true`.

The simulator and automated tests do not demonstrate screen capture on a real
iPhone. A real USB session, both display modes, rotation, unplug during capture,
and host termination must be checked on hardware before treating this as ready
for daily use. Preserve the upstream license and attribution.

The existing App Store receiver is supported without Developer Mode. Disabling
Local Network permission does not itself block incoming TCP (Apple TN3179);
keep iPhone Wi-Fi off in Settings for the USB-only campus setup. The sender
cannot remotely enforce or inspect that setting in the unmodified phone app.
