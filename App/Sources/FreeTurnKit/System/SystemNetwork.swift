import Foundation
import SystemConfiguration

public struct NetworkSnapshot: Equatable, Sendable {
    public var ifName: String
    public var ifIndex: Int32
    public var ifIndex6: Int32?
    public var dns: [String]

    public init(ifName: String, ifIndex: Int32, ifIndex6: Int32? = nil, dns: [String]) {
        self.ifName = ifName
        self.ifIndex = ifIndex
        self.ifIndex6 = ifIndex6
        self.dns = dns
    }
}

/// Физическая сеть машины: к её интерфейсу привязываются сокеты ядра, её DNS оно использует.
public enum SystemNetwork {
    public static func current() -> NetworkSnapshot? {
        let store = SCDynamicStoreCreate(nil, "FreeTurn" as CFString, nil, nil)
        func value(_ key: String) -> [String: Any]? {
            SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any]
        }
        let primary4 = value("State:/Network/Global/IPv4")?["PrimaryInterface"] as? String
        let primary6 = value("State:/Network/Global/IPv6")?["PrimaryInterface"] as? String
        let dns = value("State:/Network/Global/DNS")?["ServerAddresses"] as? [String] ?? []
        return snapshot(primaryInterface: primary4, ipv6Interface: primary6, dns: dns) { Int32(if_nametoindex($0)) }
    }

    /// nil - сети нет или default route держит чужой туннель: привязываться не к чему.
    static func snapshot(primaryInterface: String?, ipv6Interface: String? = nil, dns: [String],
                         indexOf: (String) -> Int32) -> NetworkSnapshot? {
        func physical(_ name: String?) -> (name: String, index: Int32)? {
            guard let name, !name.isEmpty, !name.hasPrefix("utun"), !name.hasPrefix("lo") else { return nil }
            let index = indexOf(name)
            return index > 0 ? (name, index) : nil
        }

        let ipv6 = physical(ipv6Interface)
        guard let primary = physical(primaryInterface) ?? ipv6 else { return nil }
        let ipv6Index = ipv6.flatMap { $0.index == primary.index ? nil : $0.index }
        return NetworkSnapshot(ifName: primary.name, ifIndex: primary.index, ifIndex6: ipv6Index, dns: dns)
    }
}

public enum PortPicker {
    /// Свободный UDP-порт на loopback для ядра. Между выбором и стартом порт могут занять -
    /// тогда ядро вернёт ошибку старта, и подключение завершится с ней.
    public static func freeUDPPort() throws -> Int {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { p in
                bind(fd, p, len) == 0 && getsockname(fd, p, &len) == 0
            }
        }
        guard bound else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        return Int(in_port_t(bigEndian: addr.sin_port))
    }
}
