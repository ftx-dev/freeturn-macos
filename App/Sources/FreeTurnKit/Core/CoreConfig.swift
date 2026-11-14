import Foundation

/// Конфиг ядра для `mobile.Start`. Зеркало `config.ClientJSON`: декодер ядра строгий
/// (DisallowUnknownFields), поэтому имена и набор ключей менять только вместе с ядром.
public enum CoreConfig {
    /// WG идёт поверх TURN: дефолтные 1420 фрагментируются, 1280 живёт везде.
    public static let tunnelMTU = 1280
    static let defaultThreads = 12

    public static func build(server: Server, listenPort: Int, ownClientId: String,
                             systemDNS: [String], advancedCaptcha: Bool) -> String {
        let c = server.client
        let o = server.opts
        let direct = c.provider == Provider.direct

        let manualDNS = DnsList.normalize(c.customDns)
        let dnsServers: [String] =
            !manualDNS.isEmpty ? manualDNS.split(separator: ",").map(String.init)
            : c.useCarrierDns ? systemDNS
            : []

        let config: [String: Any] = [
            "peer": c.serverAddress,
            "clientId": c.clientId.isEmpty ? ownClientId : c.clientId,
            "subUrl": "",
            "provider": c.provider,
            // Мимо туннеля сокеты ядра уводит привязка к интерфейсу, а не маршруты.
            "routes": false,
            "turn": [
                "n": direct ? 1 : (c.threads > 0 ? c.threads : defaultThreads),
                "transport": c.useUdp ? "udp" : "tcp",
                "host": c.magicSwitch ? c.magicTurn.trimmingCharacters(in: .whitespaces) : "",
                "port": "",
            ],
            // Локальный порт - для WG/AWG внутри движка; своего туннеля ядро не поднимает.
            "proxy": ["mode": "udp", "listen": "127.0.0.1:\(listenPort)"],
            "vk": [
                "links": [c.callLink],
                "streamsPerCred": c.streamsPerCred > 0 ? c.streamsPerCred : defaultThreads,
                "manualCaptcha": c.manualCaptcha,
                "autoCaptcha": true,
                "advancedCaptcha": advancedCaptcha && !c.manualCaptcha,
                "platform": "desktop",
            ],
            "obf": [
                "profile": o.obfEnabled ? o.obfProfile : ObfProfile.none,
                "key": o.obfEnabled ? o.obfKey : "",
                // Без профиля ядро отвергает ненулевой пейсинг.
                "timingMs": o.obfEnabled ? o.obfTimingMs : 0,
            ],
            "dns": ["mode": c.dnsMode, "servers": dnsServers],
            "log": ["debug": c.debugMode],
            "tunnel": ["mode": "none", "config": "", "mtu": tunnelMTU],
        ]
        let data = try! JSONSerialization.data(withJSONObject: config, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }
}
