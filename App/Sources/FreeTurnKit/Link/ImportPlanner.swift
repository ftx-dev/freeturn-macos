import Foundation

public enum ImportError: Error, Equatable {
    case unknownProvider
    /// TCP-режим для Xray работает только через локальный порт, которого в клиенте нет.
    case tcpModeUnsupported
    case badObf
}

/// Ссылка, проверенная и сверенная с уже сохранёнными серверами - то, что видит панель импорта.
public struct ImportDraft: Equatable, Sendable {
    public var link: FreeturnLink
    public var suggestedName: String
    /// Ссылка на звонок из самой ссылки (её можно заменить своей).
    public var callLink: String
    public var duplicateAddress: Bool
    public var duplicateConf: Bool
    public var needsCallLink: Bool
    public var needsWireGuard: Bool
}

public enum ImportPlanner {
    public static func draft(for link: FreeturnLink, existing: [Server]) throws -> ImportDraft {
        guard Provider.values.contains(link.provider) else { throw ImportError.unknownProvider }
        guard link.mode != "tcp", !link.bond else { throw ImportError.tcpModeUnsupported }
        if !link.obfProfile.isEmpty, link.obfProfile != ObfProfile.none {
            guard ObfProfile.values.contains(link.obfProfile), ObfProfile.isValidKey(link.obfKey) else {
                throw ImportError.badObf
            }
        }

        let conf = link.wgConf.trimmingCharacters(in: .whitespacesAndNewlines)
        let host = link.peer.split(separator: ":").first.map(String.init) ?? link.peer
        return ImportDraft(
            link: link,
            suggestedName: link.name.isEmpty ? host : link.name,
            callLink: link.callLink.trimmingCharacters(in: .whitespacesAndNewlines),
            duplicateAddress: existing.contains {
                $0.client.serverAddress.caseInsensitiveCompare(link.peer) == .orderedSame
            },
            duplicateConf: !conf.isEmpty && existing.contains {
                $0.client.wireGuardConfig.trimmingCharacters(in: .whitespacesAndNewlines) == conf
            },
            needsCallLink: link.provider == Provider.relay,
            needsWireGuard: conf.isEmpty
        )
    }

    public static func makeServer(from draft: ImportDraft, name: String, callLink: String) -> Server {
        let link = draft.link
        let conf = link.wgConf.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        var client = ClientConfig()
        client.serverAddress = link.peer
        client.callLink = callLink.trimmingCharacters(in: .whitespacesAndNewlines)
        client.provider = link.provider
        client.useUdp = link.transport == "udp"
        if link.n > 0 { client.threads = link.n }
        if link.streamsPerCred > 0 { client.streamsPerCred = link.streamsPerCred }
        client.tunnelTransport = conf.isEmpty ? TunnelTransport.none : TunnelTransport.wireguard
        client.wireGuardConfig = conf
        client.clientId = link.clientId.trimmingCharacters(in: .whitespacesAndNewlines)
        if ["auto", "plain", "doh"].contains(link.dnsMode) { client.dnsMode = link.dnsMode }
        client.customDns = DnsList.normalize(link.dnsServers)
        client.manualCaptcha = link.manualCaptcha

        var opts = ServerOpts()
        opts.obfProfile = link.obfProfile.isEmpty ? ObfProfile.none : link.obfProfile
        opts.obfKey = link.obfKey
        opts.obfTimingMs = min(max(link.obfTimingMs, 0), ObfProfile.timingMax)

        return Server(name: trimmedName.isEmpty ? draft.suggestedName : trimmedName, client: client, opts: opts)
    }
}
