public enum Presets {
    public static let allViaVPN = RoutingProfile(
        id: "builtin-all", name: "Всё через VPN", defaultAction: .vpn, rules: [], builtIn: true)

    /// Аналог списка исключений Android (DefaultBypassApps), но по доменам:
    /// российские сервисы часто недоступны с зарубежного IP.
    public static let russiaDirect = RoutingProfile(
        id: "builtin-ru", name: "Российские сервисы напрямую", defaultAction: .vpn,
        rules: russianSuffixes.map {
            RoutingRule(id: "builtin-ru-\($0)", kind: .domainSuffix, value: $0, action: .direct)
        },
        builtIn: true)

    // Зоны и сервисы вне .ru. "xn--p1ai" - это .рф: в трафике домен виден в punycode.
    static let russianSuffixes = [
        "ru", "su", "xn--p1ai",
        "vk.com", "vk.me", "vk-cdn.net", "userapi.com", "vkuser.net", "mycdn.me", "okcdn.ru", "ok.ru",
        "yandex.ru", "yandex.net", "yandex.com", "yastatic.net", "ya.ru", "kinopoisk.ru",
        "mail.ru", "imgsmail.ru", "rutube.ru", "dzen.ru",
        "gosuslugi.ru", "mos.ru", "nalog.ru", "rzd.ru",
        "sberbank.ru", "sber.ru", "tbank.ru", "tinkoff.ru", "alfabank.ru", "vtb.ru", "nspk.ru",
        "ozon.ru", "ozone.ru", "wildberries.ru", "wb.ru", "wbbasket.ru", "avito.ru", "avito.st",
        "megamarket.ru", "samokat.ru", "2gis.ru", "2gis.com", "hh.ru", "cian.ru",
        "mts.ru", "megafon.ru", "beeline.ru", "tele2.ru", "t2.ru",
    ]
}
