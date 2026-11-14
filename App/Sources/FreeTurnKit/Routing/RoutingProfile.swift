import Foundation

public enum RouteAction: String, Codable, Sendable, CaseIterable { case vpn, direct, block }

public enum RuleKind: String, Codable, Sendable, CaseIterable {
    case app, domain, domainSuffix, domainKeyword, cidr
}

public struct RoutingRule: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var kind: RuleKind
    /// app - путь к .app или исполняемому файлу; cidr - адрес или подсеть.
    public var value: String
    public var action: RouteAction
    public var enabled: Bool

    public init(id: String = UUID().uuidString, kind: RuleKind, value: String,
                action: RouteAction, enabled: Bool = true) {
        self.id = id
        self.kind = kind
        self.value = value
        self.action = action
        self.enabled = enabled
    }
}

public struct RoutingProfile: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    /// Куда идёт всё, что не попало под правила: .vpn или .direct.
    public var defaultAction: RouteAction
    public var rules: [RoutingRule]
    public var builtIn: Bool

    public init(id: String = UUID().uuidString, name: String, defaultAction: RouteAction,
                rules: [RoutingRule], builtIn: Bool = false) {
        self.id = id
        self.name = name
        self.defaultAction = defaultAction
        self.rules = rules
        self.builtIn = builtIn
    }
}

public struct RoutingFile: Codable, Equatable, Sendable {
    public var profiles: [RoutingProfile]
    /// Профиль для серверов без собственного.
    public var sharedProfileId: String

    public init(profiles: [RoutingProfile], sharedProfileId: String) {
        self.profiles = profiles
        self.sharedProfileId = sharedProfileId
    }

    public func profile(for server: Server) -> RoutingProfile {
        profiles.first { $0.id == server.client.routingProfileId }
            ?? profiles.first { $0.id == sharedProfileId }
            ?? Presets.allViaVPN
    }
}
