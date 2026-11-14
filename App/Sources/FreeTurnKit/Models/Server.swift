import Foundation

public enum Provider {
    /// Через TURN-реле звонков; "vk" - wire-значение ядра.
    public static let relay = "vk"
    public static let direct = "direct"
    public static let values = [relay, direct]
}

public enum ObfProfile {
    public static let none = "none"
    public static let values = ["none", "rtpopus", "rtpopus2", "rtpopus3"]
    public static let timingMax = 60

    public static func isValidKey(_ key: String) -> Bool {
        key.count == 64 && key.allSatisfy(\.isHexDigit)
    }

    public static func generateKey() -> String {
        (0..<32).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max)) }.joined()
    }
}

public enum TunnelTransport {
    public static let none = "none"
    public static let wireguard = "wireguard"
}

extension KeyedDecodingContainer {
    /// Как optX у Android: нет ключа или не тот тип - берём значение по умолчанию.
    func value<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback
    }
}

/// Клиентские параметры сервера. Имена ключей совпадают с Android ServerJson.
public struct ClientConfig: Codable, Equatable, Sendable {
    public var serverAddress = ""
    public var callLink = ""
    public var provider = Provider.relay
    public var threads = 12
    public var streamsPerCred = 12
    public var useUdp = false
    public var manualCaptcha = false
    public var debugMode = false
    public var useCarrierDns = true
    public var dnsMode = "auto"
    public var customDns = ""
    public var magicSwitch = false
    public var magicTurn = ""
    public var tunnelTransport = TunnelTransport.none
    public var wireGuardConfig = ""
    public var clientId = ""
    /// Только macOS: профиль маршрутов сервера; nil - общий профиль.
    public var routingProfileId: String?

    public init() {}

    public var wireGuardActive: Bool {
        tunnelTransport == TunnelTransport.wireguard
            && !wireGuardConfig.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ClientConfig()
        serverAddress = c.value(.serverAddress, d.serverAddress)
        callLink = c.value(.callLink, d.callLink)
        let p = c.value(.provider, d.provider)
        provider = Provider.values.contains(p) ? p : Provider.relay
        threads = c.value(.threads, d.threads)
        streamsPerCred = c.value(.streamsPerCred, d.streamsPerCred)
        useUdp = c.value(.useUdp, d.useUdp)
        manualCaptcha = c.value(.manualCaptcha, d.manualCaptcha)
        debugMode = c.value(.debugMode, d.debugMode)
        useCarrierDns = c.value(.useCarrierDns, d.useCarrierDns)
        let mode = c.value(.dnsMode, d.dnsMode)
        dnsMode = ["auto", "plain", "doh"].contains(mode) ? mode : "auto"
        customDns = c.value(.customDns, d.customDns)
        magicSwitch = c.value(.magicSwitch, d.magicSwitch)
        magicTurn = c.value(.magicTurn, d.magicTurn)
        let t = c.value(.tunnelTransport, d.tunnelTransport)
        tunnelTransport = t == TunnelTransport.wireguard ? t : TunnelTransport.none
        wireGuardConfig = c.value(.wireGuardConfig, d.wireGuardConfig)
        clientId = c.value(.clientId, d.clientId)
        routingProfileId = try? c.decodeIfPresent(String.self, forKey: .routingProfileId)
    }
}

/// Серверные опции, которые обязан повторять клиент.
public struct ServerOpts: Codable, Equatable, Sendable {
    public var obfProfile = ObfProfile.none
    public var obfKey = ""
    public var obfTimingMs = 0
    public var proxyMode = "udp"

    public init() {}

    public var obfEnabled: Bool { obfProfile != ObfProfile.none }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let profile = c.value(.obfProfile, ObfProfile.none)
        obfProfile = ObfProfile.values.contains(profile) ? profile : ObfProfile.none
        obfKey = c.value(.obfKey, "")
        obfTimingMs = min(max(c.value(.obfTimingMs, 0), 0), ObfProfile.timingMax)
        proxyMode = c.value(.proxyMode, "udp")
    }
}

public struct Server: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var client: ClientConfig
    public var opts: ServerOpts

    public init(id: String = UUID().uuidString, name: String,
                client: ClientConfig = ClientConfig(), opts: ServerOpts = ServerOpts()) {
        self.id = id
        self.name = name
        self.client = client
        self.opts = opts
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawId = c.value(.id, "")
        id = rawId.isEmpty ? UUID().uuidString : rawId
        name = c.value(.name, "")
        client = c.value(.client, ClientConfig())
        opts = c.value(.opts, ServerOpts())
    }
}

public struct ServersFile: Codable, Equatable, Sendable {
    public var list: [Server]
    public var activeId: String?

    public init(list: [Server] = [], activeId: String? = nil) {
        self.list = list
        self.activeId = activeId
    }

    public var active: Server? { list.first { $0.id == activeId } }
}
