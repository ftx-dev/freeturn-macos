// ftctl - служебная утилита разработки: собирает конфиги ядра и движка из ссылки freeturn://,
// чтобы проверить связку вживую без приложения и службы.
import Foundation
import FreeTurnKit

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("ftctl: \(message)\n".utf8))
    exit(1)
}

let usage = """
usage: ftctl gen --link <freeturn://…> --out <dir> [--call-link <url>] [--wg <file>]
                 [--rule <app|domain|domainSuffix|domainKeyword|cidr>=<value>=<vpn|direct|block>]…
                 [--default <vpn|direct>] [--stack <system|gvisor|mixed>]
"""

var args = Array(CommandLine.arguments.dropFirst())
guard args.first == "gen" else { fail(usage) }
args.removeFirst()

var options: [String: String] = [:]
var rules: [RoutingRule] = []
while !args.isEmpty {
    let key = args.removeFirst()
    guard key.hasPrefix("--"), !args.isEmpty else { fail(usage) }
    let value = args.removeFirst()
    if key == "--rule" {
        let parts = value.split(separator: "=", maxSplits: 2).map(String.init)
        guard parts.count == 3, let kind = RuleKind(rawValue: parts[0]),
              let action = RouteAction(rawValue: parts[2]) else { fail("bad --rule \(value)") }
        rules.append(RoutingRule(kind: kind, value: parts[1], action: action))
    } else {
        options[String(key.dropFirst(2))] = value
    }
}
guard let rawLink = options["link"], let out = options["out"] else { fail(usage) }

do {
    let outDir = URL(fileURLWithPath: out)
    let draft = try ImportPlanner.draft(for: FreeturnLink.parse(rawLink), existing: [])
    var server = ImportPlanner.makeServer(from: draft, name: "", callLink: options["call-link"] ?? draft.callLink)
    if let wgFile = options["wg"] {
        server.client.wireGuardConfig = try String(contentsOfFile: wgFile, encoding: .utf8)
        server.client.tunnelTransport = TunnelTransport.wireguard
    }
    guard server.client.wireGuardActive else { fail("в ссылке нет конфига WireGuard - передайте --wg <file>") }
    if draft.needsCallLink, server.client.callLink.isEmpty { fail("для Relay нужна --call-link") }
    guard let net = SystemNetwork.current() else { fail("не найден физический сетевой интерфейс") }

    let store = Store(directory: outDir)
    let port = try PortPicker.freeUDPPort()
    let core = CoreConfig.build(server: server, listenPort: port, ownClientId: try store.ownClientId(),
                                systemDNS: net.dns, advancedCaptcha: false)
    let profile = RoutingProfile(name: "proof", defaultAction: RouteAction(rawValue: options["default"] ?? "vpn") ?? .vpn,
                                 rules: rules)
    let engine = try EngineConfig.build(wg: WGConfig.parse(server.client.wireGuardConfig), corePort: port,
                                        profile: profile, settings: EngineSettings(stack: options["stack"] ?? "mixed"))

    let start = try JSONSerialization.data(withJSONObject: ["cmd": "start", "config": core, "ifIndex": Int(net.ifIndex)])
    try (start + Data("\n".utf8)).write(to: outDir.appendingPathComponent("core-start.jsonl"))
    try Data(engine.utf8).write(to: outDir.appendingPathComponent("engine.json"))
    // В файлах ключи: закрываем от других пользователей.
    for name in ["core-start.jsonl", "engine.json"] {
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: outDir.appendingPathComponent(name).path)
    }
    print("порт ядра: \(port); интерфейс: \(net.ifName) (\(net.ifIndex)); провайдер: \(server.client.provider); туннель: \(try WGConfig.parse(server.client.wireGuardConfig).isAmnezia ? "AmneziaWG" : "WireGuard")")
    print("файлы: \(outDir.path)/core-start.jsonl, \(outDir.path)/engine.json")
} catch {
    fail("\(error)")
}
