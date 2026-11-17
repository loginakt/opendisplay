// GPL-3.0. USB-only transport policy for this fork.
import Network

/// This policy is unconditional: preferences and command-line flags cannot relax it.
enum USBOnlyTransport {
    static let maximumFrameLength = 32 * 1024 * 1024

    static func receiverParameters(port: UInt16) -> NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        let parameters = NWParameters(tls: nil, tcp: tcp)
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: port)!)
        parameters.prohibitedInterfaceTypes = [.wifi, .cellular, .wiredEthernet]
        parameters.allowLocalEndpointReuse = true
        parameters.serviceClass = .interactiveVideo
        return parameters
    }

    static func accepts(_ endpoint: NWEndpoint) -> Bool {
        guard case .hostPort(let host, _) = endpoint else { return false }
        switch host {
        case .ipv4(let address): return address == .loopback
        case .ipv6(let address): return address == .loopback
        default: return false
        }
    }
}
