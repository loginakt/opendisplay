// USB-only fork of OpenDisplay, GPL-3.0. See USB/README.md.
import AppKit
import SwiftUI
import ScreenCaptureKit
import Darwin

/// No Bonjour, network address, port override, saved WiFi target or automatic connection.
@MainActor
final class USBDisplayController: NSObject, NSApplicationDelegate, ObservableObject {
    @Published var devices: [UsbmuxDevice] = []
    @Published var status = "Connect an iPhone or iPad with a USB data cable."
    @Published var activeID: String?
    private var watcher: UsbmuxDeviceWatcher?
    private var sender: MacSender?
    private var startTask: Task<Void, Never>?
    private var signals: [DispatchSourceSignal] = []
    private let stdio: Bool
    private let outputLock = NSLock()
    private var inputBuffer = Data()

    init(stdio: Bool) { self.stdio = stdio }

    func applicationDidFinishLaunching(_ notification: Notification) {
        watcher = UsbmuxDeviceWatcher { [weak self] devices in
            guard let self else { return }
            self.devices = devices
            if let id = self.activeID, !devices.contains(where: { $0.udid == id }) {
                self.stop()
                self.status = "USB cable disconnected. Connect again to resume."
            }
            self.emit()
        }
        for number in [SIGTERM, SIGINT] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler { [weak self] in self?.quit() }
            source.resume()
            signals.append(source)
        }
        if stdio {
            FileHandle.standardInput.readabilityHandler = { [weak self] handle in
                // POSIX read returns the currently available bytes. Foundation's
                // read(upToCount:) can wait for the requested size on an open pipe.
                var bytes = [UInt8](repeating: 0, count: 16_384)
                let count = Darwin.read(handle.fileDescriptor, &bytes, bytes.count)
                if count < 0 && errno == EINTR { return }
                let data = count > 0 ? Data(bytes.prefix(count)) : Data()
                if data.isEmpty { handle.readabilityHandler = nil }
                Task { @MainActor in self?.consume(data) }
            }
        }
        emit()
    }

    private func consume(_ data: Data) {
        if data.isEmpty { quit(); return } // parent exited or closed its control pipe
        inputBuffer.append(data)
        guard inputBuffer.count <= 16_384 else { quit(); return }
        while let end = inputBuffer.firstIndex(of: 10) {
            let line = inputBuffer[..<end]
            inputBuffer.removeSubrange(...end)
            guard let command = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let action = command["action"] as? String else { continue }
            switch action {
            case "connect":
                guard let id = command["device"] as? String,
                      let modeName = command["mode"] as? String,
                      let mode = CaptureMode(rawValue: modeName) else { continue }
                connect(id: id, mode: mode, touch: command["touch"] as? Bool ?? false)
            case "refresh": watcher?.refresh(); emit()
            case "accessibilityPermission": _ = InputInjector.ensureAccessibilityPermission(); emit()
            case "stop": stop()
            case "permission": CGRequestScreenCaptureAccess(); emit()
            case "quit": quit()
            default: break // host/port/network commands intentionally unsupported
            }
        }
    }

    func connect(id: String, mode: CaptureMode, touch: Bool = false) {
        guard devices.contains(where: { $0.udid == id }) else { return }
        stop()
        guard !NSWorkspace.shared.runningApplications.contains(where: {
            $0.bundleIdentifier == "com.peetzweg.opensidecar.mac"
        }) else {
            status = "Quit standalone OpenDisplay on this Mac, then connect again. Keep OpenDisplay open on the iPhone."
            emit(); return
        }
        guard CGPreflightScreenCaptureAccess() else {
            status = "Screen Recording permission is required. Grant it and restart the app."
            emit(); return
        }
        activeID = id
        let name = devices.first { $0.udid == id }?.name ?? "iPhone / iPad"
        let engine = MacSender(transport: .usb(udid: id, port: 9000), name: name, mode: mode)
        engine.touchEnabled = touch
        sender = engine
        engine.onStatus = { [weak self, weak engine] value in
            guard let self, self.sender === engine else { return }
            self.status = value; self.emit()
        }
        let end: () -> Void = { [weak self, weak engine] in
            guard let self, self.sender === engine else { return }
            self.stop()
        }
        engine.onDisconnected = end
        engine.onPeerSleeping = end
        engine.onPeerClosed = end
        engine.onCaptureStoppedByUser = end
        status = "Connecting over USB…"
        emit()
        startTask = Task { [weak self, weak engine] in
            guard let engine else { return }
            do { try await engine.start() }
            catch {
                guard let self, self.sender === engine else { return }
                self.stop(); self.status = error.localizedDescription; self.emit()
            }
        }
    }

    func stop() {
        startTask?.cancel(); startTask = nil
        sender?.stop(); sender = nil; activeID = nil
        status = "Stopped. USB connection required."
        emit()
    }

    private func emit() {
        guard stdio else { return }
        let message: [String: Any] = [
            "protocol": 1, "transport": "usb", "status": status,
            "activeDevice": activeID ?? "", "screenRecording": CGPreflightScreenCaptureAccess(),
            "devices": devices.map { ["id": $0.udid, "name": $0.name ?? "iPhone / iPad"] }
        ]
        guard var data = try? JSONSerialization.data(withJSONObject: message, options: [.sortedKeys]) else { return }
        data.append(10)
        outputLock.lock(); defer { outputLock.unlock() }
        // A dead parent closes the pipe. SIGPIPE is ignored by main; terminate on failure.
        do { try FileHandle.standardOutput.write(contentsOf: data) }
        catch { quit() }
    }

    func quit() { sender?.stop(); NSApplication.shared.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) { sender?.stop() }
}

struct USBDisplayWindow: View {
    @ObservedObject var controller: USBDisplayController
    @State private var mode = CaptureMode.extend
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("USB Display").font(.title.bold())
            Text("USB only. Wi-Fi streaming and automatic connections are disabled.")
            Text(controller.status).foregroundStyle(.secondary)
            Picker("Display", selection: $mode) {
                Text("Extend").tag(CaptureMode.extend)
                Text("Mirror").tag(CaptureMode.mirror)
            }
            ForEach(controller.devices) { device in
                Button("Connect \(device.name ?? "iPhone / iPad")") {
                    controller.connect(id: device.udid, mode: mode)
                }
            }
            Button("Grant Screen Recording") { CGRequestScreenCaptureAccess() }
            Button("Stop") { controller.stop() }.disabled(controller.activeID == nil)
        }.padding(24).frame(width: 460)
    }
}

@main
struct USBDisplayMain {
    @MainActor static func main() {
        signal(SIGPIPE, SIG_IGN)
        let args = Array(CommandLine.arguments.dropFirst())
        guard args.isEmpty || args == ["--control-stdio"] else {
            fputs("Only --control-stdio is accepted; network transport is unavailable.\n", stderr)
            exit(64)
        }
        let app = NSApplication.shared
        let stdio = args == ["--control-stdio"]
        app.setActivationPolicy(stdio ? .prohibited : .regular)
        let controller = USBDisplayController(stdio: stdio)
        // A hung main queue must not keep capture alive after the host crashes.
        let parent = getppid()
        let parentWatch = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        if stdio {
            parentWatch.schedule(deadline: .now() + 0.5, repeating: 0.5)
            parentWatch.setEventHandler { if getppid() != parent { _exit(0) } }
        }
        parentWatch.resume()
        app.delegate = controller
        var window: NSWindow?
        if !stdio {
            let view = NSHostingView(rootView: USBDisplayWindow(controller: controller))
            let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 508, height: 340),
                                 styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            panel.title = "USB Display (Unofficial)"
            panel.contentView = view; panel.center(); panel.makeKeyAndOrderFront(nil)
            window = panel
            app.activate(ignoringOtherApps: true)
        }
        withExtendedLifetime((controller, window, parentWatch)) { app.run() }
    }
}
