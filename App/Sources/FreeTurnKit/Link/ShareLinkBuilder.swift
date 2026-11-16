import Foundation

public struct ShareOptions: Equatable, Sendable {
    /// Имя у получателя; пусто - имя сервера.
    public var name: String
    /// Вложить свою ссылку на звонок: получателю не нужна своя.
    public var includeCallLink: Bool
    /// Вложить свой конфиг WireGuard - для своего же второго устройства.
    public var includeWireGuard: Bool

    public init(name: String = "", includeCallLink: Bool = false, includeWireGuard: Bool = true) {
        self.name = name
        self.includeCallLink = includeCallLink
        self.includeWireGuard = includeWireGuard
    }
}

/// Ссылка freeturn:// на свой сервер - как ShareLinkBuilder у Android, но без выпуска нового
/// пользователя на сервере (для этого нужно управление сервером по SSH).
public enum ShareLinkBuilder {
    public static func build(server: Server, ownClientId: String, options: ShareOptions) -> String {
        let c = server.client
        let o = server.opts
        var link = FreeturnLink()
        link.provider = c.provider
        link.peer = c.serverAddress
        link.transport = c.useUdp ? "udp" : ""
        // Битый ключ не отдаём: получатель всё равно не подключится.
        if o.obfEnabled, ObfProfile.isValidKey(o.obfKey) {
            link.obfProfile = o.obfProfile
            link.obfKey = o.obfKey
            link.obfTimingMs = o.obfTimingMs
        }
        link.n = c.threads
        link.streamsPerCred = c.streamsPerCred
        // Client ID - тот, что пускает сервер (allowlist): из ссылки сервера или своего устройства.
        link.clientId = c.clientId.isEmpty ? ownClientId : c.clientId
        link.dnsMode = c.dnsMode == "auto" ? "" : c.dnsMode
        link.dnsServers = DnsList.normalize(c.customDns)
        link.manualCaptcha = c.manualCaptcha
        let name = options.name.trimmingCharacters(in: .whitespacesAndNewlines)
        link.name = name.isEmpty ? server.name : name
        if options.includeCallLink { link.callLink = c.callLink.trimmingCharacters(in: .whitespacesAndNewlines) }
        if options.includeWireGuard, c.wireGuardActive { link.wgConf = normalizeConf(c.wireGuardConfig) }
        return link.encode()
    }

    /// Срезает комментарии, пустые строки и MTU: короче ссылка, плотнее QR. MTU у получателя - своя константа.
    static func normalizeConf(_ conf: String) -> String {
        conf.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in
                !line.isEmpty && !line.hasPrefix("#") && !line.hasPrefix(";")
                    && !(line.lowercased().hasPrefix("mtu") && line.contains("="))
            }
            .joined(separator: "\n")
    }
}
