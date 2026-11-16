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

extension RoutingProfile {
    /// Копия для правки: новые идентификаторы, не встроенная.
    func editableCopy(name: String) -> RoutingProfile {
        RoutingProfile(name: name, defaultAction: defaultAction,
                       rules: rules.map { RoutingRule(kind: $0.kind, value: $0.value, action: $0.action, enabled: $0.enabled) })
    }
}

extension RoutingFile {
    public static func initial() -> RoutingFile {
        RoutingFile(profiles: [Presets.allViaVPN, Presets.russiaDirect], sharedProfileId: Presets.russiaDirect.id)
    }

    /// Файл с диска: встроенные профили берутся из текущей версии приложения, свои сохраняются.
    public func normalized() -> RoutingFile {
        let own = profiles.filter { !$0.builtIn && $0.id != Presets.allViaVPN.id && $0.id != Presets.russiaDirect.id }
        let all = [Presets.allViaVPN, Presets.russiaDirect] + own
        return RoutingFile(profiles: all,
                           sharedProfileId: all.contains { $0.id == sharedProfileId } ? sharedProfileId : Presets.allViaVPN.id)
    }

    public mutating func add(_ profile: RoutingProfile) {
        profiles.append(profile)
    }

    public mutating func remove(id: String) {
        profiles.removeAll { $0.id == id && !$0.builtIn }
        if !profiles.contains(where: { $0.id == sharedProfileId }) { sharedProfileId = Presets.allViaVPN.id }
    }

    @discardableResult
    public mutating func clone(id: String) -> RoutingProfile? {
        guard let source = profiles.first(where: { $0.id == id }) else { return nil }
        let copy = source.editableCopy(name: source.name + " (копия)")
        profiles.append(copy)
        return copy
    }

    public mutating func update(_ profile: RoutingProfile) {
        guard let i = profiles.firstIndex(where: { $0.id == profile.id }), !profiles[i].builtIn else { return }
        profiles[i] = profile
    }
}
