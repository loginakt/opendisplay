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
