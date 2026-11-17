import XCTest
import Network

final class USBOnlyTransportTests: XCTestCase {
    func testReceiverBindsOnlyLoopback() {
        let params = USBOnlyTransport.receiverParameters(port: 9000)
        XCTAssertEqual(params.requiredLocalEndpoint, .hostPort(host: .ipv4(.loopback), port: 9000))
        XCTAssertTrue(params.prohibitedInterfaceTypes?.contains(.wifi) ?? false)
        XCTAssertTrue(params.prohibitedInterfaceTypes?.contains(.cellular) ?? false)
        XCTAssertTrue(params.prohibitedInterfaceTypes?.contains(.wiredEthernet) ?? false)
    }
    func testListenerActuallyStartsAndAcceptsUSBLoopback() throws {
        // Construct the real listener, not just a parameters object. Passing on:
        // together with requiredLocalEndpoint throws EINVAL on macOS/iOS.
        let listener = try NWListener(using: USBOnlyTransport.receiverParameters(port: 0))
        let ready = expectation(description: "loopback listener ready")
        let accepted = expectation(description: "loopback connection accepted")
        let queue = DispatchQueue(label: "usb-listener-test")
        listener.stateUpdateHandler = { state in
            if case .ready = state { ready.fulfill() }
        }
        listener.newConnectionHandler = { connection in
            XCTAssertTrue(USBOnlyTransport.accepts(connection.endpoint))
            accepted.fulfill()
            connection.cancel()
        }
        listener.start(queue: queue)
        defer { listener.cancel() }
        wait(for: [ready], timeout: 5)
        let port = try XCTUnwrap(listener.port)
        let client = NWConnection(host: .ipv4(.loopback), port: port, using: .tcp)
        client.start(queue: queue)
        defer { client.cancel() }
        wait(for: [accepted], timeout: 5)
        XCTAssertNil(listener.service)
    }
    func testRejectsLANAddressesAndServiceEndpoints() {
        XCTAssertTrue(USBOnlyTransport.accepts(.hostPort(host: .ipv4(.loopback), port: 9000)))
        XCTAssertTrue(USBOnlyTransport.accepts(.hostPort(host: .ipv6(.loopback), port: 9000)))
        for address in ["192.168.1.2", "10.0.0.2", "169.254.1.2", "fe80::1", "localhost", "receiver.local"] {
            XCTAssertFalse(USBOnlyTransport.accepts(.hostPort(host: NWEndpoint.Host(address), port: 9000)))
        }
        XCTAssertFalse(USBOnlyTransport.accepts(.service(name: "phone", type: "_opensidecar._tcp", domain: "local.", interface: nil)))
    }
    func testUsbmuxRejectsNetworkPairedDevices() {
        var props: [String: Any] = ["ConnectionType": "Network", "DeviceID": 42, "SerialNumber": "test-device"]
        XCTAssertNil(Usbmux.device(fromProperties: props))
        props["ConnectionType"] = "USB"
        XCTAssertEqual(Usbmux.device(fromProperties: props)?.udid, "test-device")
        props.removeValue(forKey: "ConnectionType")
        XCTAssertNil(Usbmux.device(fromProperties: props))
    }
}
