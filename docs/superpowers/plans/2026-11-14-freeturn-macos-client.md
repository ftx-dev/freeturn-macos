# FreeTurn для macOS (этап 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Нативный клиент free-turn-proxy для macOS: системный VPN (WG/AWG) через Relay или Direct, список серверов, импорт `freeturn://`, маршрутизация по приложениям, доменам и подсетям, капча, статистика, логи, строка меню.

**Architecture:** Три процесса. `FreeTurn.app` (SwiftUI) хранит данные и собирает два конфига. `freeturn-core` (Go, без root) — обёртка над публичным пакетом `mobile` ядра, слушает UDP на loopback. `freeturnd` (Go, root, launchd) запускает движок Amnezia Box, который поднимает utun, применяет правила и шлёт WG/AWG в порт ядра.

**Tech Stack:** Swift 6 + SwiftUI через SwiftPM (без Xcode), Swift Testing; Go 1.26; ядро free-turn-proxy v4.1.5; Amnezia Box v1.260910.0 (форк sing-box, база 1.12).

**Spec:** `docs/superpowers/specs/2026-11-14-freeturn-macos-client-design.md`

## Global Constraints

- macOS 14+, только arm64. Xcode нет: сборка `swift build` + скрипт упаковки, подпись ad-hoc.
- Ядро не правится. Используется только пакет `mobile`. Сборка Go всегда с `-ldflags "-checklinkname=0"`.
- Конфиг ядра: `tunnel.mode: "none"`, `proxy.mode: "udp"`, `proxy.listen: "127.0.0.1:<порт>"`, `vk.platform: "desktop"`, `routes: false`. Декодер ядра строгий: лишних полей быть не должно.
- MTU туннеля — константа `1280`.
- Режима локального порта, TCP-режима, ARQ, bond, подписок, SOCKS5-раздачи, проверки обновлений нет.
- Движок гаснет, когда закрывается сокет клиента; ядро выходит, когда закрывается stdin.
- `freeturnd` не запускает ничего из пользовательских каталогов и не принимает от клиента пути к файлам.
- Секреты (ключ обфускации, конфиг WG, ссылка на звонок, IP) не попадают в лог при приватном режиме.
- Файлы данных: `~/Library/Application Support/FreeTurn/`, права 0600.
- Идентификаторы: bundle id `dev.freeturn.macos`, служба `dev.freeturn.daemon`, сокет `/var/run/freeturnd.sock`, каталог службы `/var/db/freeturnd`, бинарники службы `/Library/PrivilegedHelperTools/dev.freeturn/`.
- Интерфейс на русском и английском (`ru.lproj`, `en.lproj`, по умолчанию `ru`).
- Лицензия GPL-3.0.
- Тесты Swift запускаются только через `make test-app` (нужны пути к `Testing.framework` из Command Line Tools).
- Коммиты локальные, без push. Первый коммит в `main`, дальше ветка `stage-1`.

## Review Focus

1. WG-конфиг «из жизни»: CRLF, комментарии `#` и `;`, ключи в любом регистре, пробелы вокруг `=`, несколько адресов через запятую — должен разобраться (тест в Task 5).
2. Ссылка `freeturn://` с пробелами и переводами строк вокруг, схемой в верхнем регистре, с хвостовыми `=` — должна разобраться (тест в Task 4).
3. Путь к приложению с пробелами, скобками, точками и кириллицей в правиле — регулярное выражение обязано быть экранировано (тест в Task 7).
4. Битый `servers.json` — список серверов не затирается, пользователь видит ошибку (тест в Task 3).
5. Сеть пропала совсем или сменилась во время подключения — без падения и без привязки к «нулевому» интерфейсу; переподключение после возврата сети (тест в Task 10).

---

## Структура файлов

```
Makefile                         цели: deps engine helper app test test-go test-app run
scripts/bundle-app.sh            собирает build/FreeTurn.app, ad-hoc подпись
scripts/install-daemon.sh        ставит службу (запускается с правами администратора)
scripts/uninstall-daemon.sh
third_party/free-turn-proxy      git submodule, тег v4.1.5
third_party/amnezia-box          git submodule, коммит 1672448
helper/go.mod                    модуль freeturn-macos/helper, replace на third_party ядра
helper/cmd/freeturn-core/main.go
helper/cmd/freeturnd/main.go
helper/internal/bridge/          протокол stdin/stdout, привязка сокетов
helper/internal/daemon/          сокет, запуск движка, проверка конфига
App/Package.swift                цели: FreeTurnKit, FreeTurn (app), ftctl, FreeTurnKitTests
App/Sources/FreeTurnKit/         вся логика без UI
App/Sources/FreeTurn/            SwiftUI
App/Sources/ftctl/main.swift     служебная утилита для пробы вживую
App/Tests/FreeTurnKitTests/
```

---

### Task 1: Каркас репозитория и сборка движка

**Files:**
- Create: `.gitignore`, `LICENSE`, `Makefile`, `helper/go.mod`, `App/Package.swift`
- Create: `App/Sources/FreeTurnKit/Version.swift`, `App/Tests/FreeTurnKitTests/SmokeTests.swift`

**Interfaces:**
- Produces: `make deps`, `make engine` → `build/amnezia-box`; `make test-app`; `make test-go`; `public enum AppInfo { static let coreVersion = "v4.1.5" }`.

- [ ] **Step 1:** `git init -b main`; добавить submodule ядра (`https://github.com/hackdiaz-dev/free-turn-proxy`, checkout `v4.1.5`) и движка (`https://github.com/amnezia-vpn/amnezia-box`, checkout `1672448`). `.gitignore`: `build/`, `.build/`, `App/.build/`, `.DS_Store`.
- [ ] **Step 2:** `Makefile`:
  - `engine`: `cd third_party/amnezia-box && go build -trimpath -ldflags "-s -w" -tags "with_gvisor,with_wireguard,with_awg" -o ../../build/amnezia-box ./cmd/sing-box`
  - `helper`: `cd helper && go build -trimpath -ldflags "-checklinkname=0 -s -w -X github.com/samosvalishe/free-turn-proxy/mobile.version=v4.1.5" -o ../build/ ./cmd/...`
  - `test-go`: `cd helper && go test -ldflags=-checklinkname=0 ./...`
  - `test-app`: `cd App && swift test -Xswiftc -F$(F) -Xlinker -F$(F) -Xlinker -rpath -Xlinker $(F) -Xlinker -rpath -Xlinker $(L)`, где `F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks`, `L=/Library/Developer/CommandLineTools/Library/Developer/usr/lib`
  - `test`: `test-go test-app`; `app`: `engine helper` + `scripts/bundle-app.sh`; `run`: `open build/FreeTurn.app`.
- [ ] **Step 3:** `helper/go.mod`: `module freeturn-macos/helper`, `go 1.26.11`, `require github.com/samosvalishe/free-turn-proxy v0.0.0`, `replace github.com/samosvalishe/free-turn-proxy => ../third_party/free-turn-proxy`.
- [ ] **Step 4:** `App/Package.swift`: tools 6.0, `platforms: [.macOS(.v14)]`, `defaultLocalization: "ru"`, цели `FreeTurnKit` (library), `FreeTurnKitTests`. Тест `@Test func coreVersionPinned() { #expect(AppInfo.coreVersion == "v4.1.5") }`.
- [ ] **Step 5:** Run `make engine && build/amnezia-box version` — ожидается строка `Tags: with_gvisor,with_wireguard,with_awg`. Run `make test-app` — 1 тест прошёл.
- [ ] **Step 6:** Commit `chore: scaffold repo, pin core and engine` в `main`; затем `git switch -c stage-1`.

---

### Task 2: freeturn-core — мост к ядру

**Files:**
- Create: `helper/cmd/freeturn-core/main.go`, `helper/internal/bridge/bridge.go`, `helper/internal/bridge/bind_darwin.go`
- Test: `helper/internal/bridge/bridge_test.go`, `helper/internal/bridge/bind_darwin_test.go`

**Interfaces:**
- Produces: бинарник `build/freeturn-core -state-dir <dir>`. Протокол — одна строка JSON на сообщение.
  - Команды (stdin): `{"cmd":"start","config":"<JSON ядра строкой>","ifIndex":14}`, `{"cmd":"stop"}`, `{"cmd":"reconnect","ifIndex":14,"dns":"1.1.1.1,8.8.8.8"}`, `{"cmd":"wake"}`, `{"cmd":"args","config":"<JSON>"}`.
  - События (stdout): `{"ev":"hello","version":"v4.1.5"}` при запуске; `{"ev":"state","state":"idle|connecting|connected|captcha|error","streams":0,"total":0,"err":""}`; `{"ev":"log","level":"debug|info|warn|error","msg":"","ts":0}`; `{"ev":"captcha","url":"","manual":false}`; `{"ev":"stats","tx":0,"rx":0,"txRate":0,"rxRate":0}` раз в секунду, пока сессия жива; `{"ev":"args","args":""}`; `{"ev":"error","cmd":"start","err":""}`.
  - EOF на stdin: `mobile.Stop()` и выход с кодом 0.
- Go: `func Run(in io.Reader, out io.Writer, stateDir string) error`; `func bindToInterface(fd int, ifIndex int) bool`; `func SetInterface(ifIndex int)`.

- [ ] **Step 1: тесты** (`bridge_test.go`, гоняют `Run` через `io.Pipe`):
  - `TestHello`: первая строка вывода — `ev=hello`, `version` непустой.
  - `TestStartBadConfig`: `start` с `config:"{}"` → событие `ev=error, cmd=start`, `err` непустой.
  - `TestStartStopDirect`: `start` с валидным конфигом (`provider:"direct"`, `peer:"127.0.0.1:1"`, `clientId` 32 hex, `proxy.listen:"127.0.0.1:0"`), затем `stop` → в выводе есть `state=connecting`, после `stop` — `state=idle`.
  - `TestEOFExits`: закрыть stdin → `Run` вернулся за ≤ 6 с.
  - `TestArgs`: `args` с тем же конфигом → `ev=args`, строка содержит `-provider direct`.
- [ ] **Step 2: тест привязки** (`bind_darwin_test.go`): `TestBindIPv4` — UDP4-сокет, `bindToInterface(fd, lo0)` → `true`, `getsockopt(IPPROTO_IP, IP_BOUND_IF)` равен индексу `lo0`. `TestBindZeroIsNoop` — `ifIndex 0` → `true`, опция осталась `0`.
- [ ] **Step 3:** Run `make test-go` — FAIL (пакета нет).
- [ ] **Step 4: реализация.** `Run` один раз вызывает `mobile.SetStateDir`, `mobile.SetLogBuffer(false)`, `mobile.SetEventSink`, `mobile.SetProtect`. Протектор берёт индекс из `atomic.Int32` и зовёт `bindToInterface`. `bindToInterface` ставит `IPV6_BOUND_IF` и `IP_BOUND_IF`; успех, если прошла хотя бы одна. Запись в `out` — под мьютексом (события приходят из горутин). `reconnect`: `SetInterface`, `mobile.SetDNSServers(dns)` при непустом `dns`, `mobile.Reconnect()`. Тикер `stats` читает `mobile.GetState()`.
- [ ] **Step 5:** Run `make test-go` — PASS. Run `make helper` — появился `build/freeturn-core`.
- [ ] **Step 6:** Commit `feat(helper): freeturn-core bridge over core mobile API`.

---

### Task 3: Kit — модели и хранилище

**Files:**
- Create: `App/Sources/FreeTurnKit/Models/Server.swift`, `Models/AppSettings.swift`, `Storage/Store.swift`
- Test: `App/Tests/FreeTurnKitTests/ServerCodingTests.swift`, `StoreTests.swift`

**Interfaces:**
- Produces (все `public`, `Codable`, `Equatable`, `Sendable`):
  - `struct ClientConfig`: `serverAddress=""`, `callLink=""`, `provider="vk"`, `threads=12`, `streamsPerCred=12`, `useUdp=false`, `manualCaptcha=false`, `debugMode=false`, `useCarrierDns=true`, `dnsMode="auto"`, `customDns=""`, `magicSwitch=false`, `magicTurn=""`, `tunnelTransport="none"`, `wireGuardConfig=""`, `clientId=""`, `routingProfileId: String? = nil`; `var wireGuardActive: Bool`.
  - `struct ServerOpts`: `obfProfile="none"`, `obfKey=""`, `obfTimingMs=0`, `proxyMode="udp"`; `var obfEnabled: Bool`.
  - `struct Server: Identifiable`: `id` (UUID-строка), `name`, `client`, `opts`.
  - `struct ServersFile`: `list: [Server]`, `activeId: String?`; `var active: Server?`.
  - `struct AppSettings`: `theme="system"`, `language="system"`, `privacyMode=false`, `advancedCaptcha=false`, `autoConnect=false`, `launchAtLogin=false`, `debugScreen=false`, `tunStack="mixed"`, `captchaTarget="window"` (или `"browser"`), `wasConnected=false`.
  - `enum Provider { static let relay = "vk", direct = "direct" }`, `enum ObfProfile { static let values = ["none","rtpopus","rtpopus2","rtpopus3"]; static func isValidKey(_:) -> Bool }` (64 hex).
  - `final class Store`: `init(directory: URL)`, `func load<T: Decodable>(_ type: T.Type, from name: String, default: T) throws -> T`, `func save<T: Encodable>(_ value: T, to name: String) throws`, `func ownClientId() throws -> String`.
- Имена ключей JSON совпадают с Android `ServerJson` (`serverAddress`, `callLink`, `wireGuardConfig`, `obfProfile`, …); неизвестные ключи игнорируются, отсутствующие берут значения по умолчанию.

- [ ] **Step 1: тесты.**
  - `decodesAndroidShape`: JSON сервера в виде Android (с блоками `ssh`, `kcp`, `localPort`, `proxyListen`) декодируется; `client.serverAddress == "1.2.3.4:56000"`, `opts.obfProfile == "rtpopus3"`.
  - `missingFieldsUseDefaults`: `{"id":"a","name":"n"}` → `client.threads == 12`, `client.provider == "vk"`, `opts.proxyMode == "udp"`.
  - `unknownProviderFallsBackToRelay`: `provider:"xyz"` → `"vk"`.
  - `saveSetsMode0600`: после `save` права файла `0o600`.
  - `saveIsAtomic`: после `save` во временном каталоге нет файлов с суффиксом `.tmp`.
  - `corruptFileThrowsAndIsKept` (Review Focus 4): в `servers.json` лежит `{"list":[`, `load` бросает `StoreError.corrupt`, содержимое файла не изменилось.
  - `missingFileReturnsDefault`.
  - `ownClientIdIsStable32Hex`: два вызова дают одну строку из 32 hex.
- [ ] **Step 2:** Run `make test-app` — FAIL.
- [ ] **Step 3: реализация.** Декодеры через `decodeIfPresent ?? default`. `save`: запись во временный файл рядом, `chmod 0600`, `replaceItemAt`.
- [ ] **Step 4:** Run `make test-app` — PASS.
- [ ] **Step 5:** Commit `feat(kit): server models and file store`.

---

### Task 4: Kit — ссылка freeturn:// и импорт

**Files:**
- Create: `App/Sources/FreeTurnKit/Link/FreeturnLink.swift`, `Link/ImportPlanner.swift`, `Link/DnsList.swift`
- Test: `App/Tests/FreeTurnKitTests/FreeturnLinkTests.swift`, `ImportPlannerTests.swift`

**Interfaces:**
- Consumes: `Server`, `ClientConfig`, `ServerOpts`, `ObfProfile`, `Provider` (Task 3).
- Produces:
  - `struct FreeturnLink: Equatable`: `provider`, `peer`, `transport`, `mode`, `bond`, `obfProfile`, `obfKey`, `obfTimingMs`, `n`, `streamsPerCred`, `clientId`, `dnsMode`, `dnsServers`, `manualCaptcha`, `name`, `callLink`, `wgConf`. Ключи JSON: `provider peer transport mode bond obf key timing n spc cid dns dnss mcap name vk wg`.
  - `static func parse(_ raw: String) throws -> FreeturnLink`; `static func looksLikeLink(_ raw: String) -> Bool`.
  - `enum LinkError: Error { invalidScheme, emptyPayload, badEncoding, unsupportedVersion, missingProvider, missingPeer }`.
  - `enum ImportError: Error { unknownProvider, tcpModeUnsupported, badObf }`.
  - `struct ImportDraft { link; suggestedName; callLink; duplicateAddress: Bool; duplicateConf: Bool; needsCallLink: Bool; needsWireGuard: Bool }`.
  - `enum ImportPlanner { static func draft(for link: FreeturnLink, existing: [Server]) throws -> ImportDraft; static func makeServer(from draft: ImportDraft, name: String, callLink: String) -> Server }`.
  - `enum DnsList { static func normalize(_ raw: String) -> String; static func hasInvalidTokens(_ raw: String) -> Bool }` — разделители `, ; пробел`, токен `^[0-9a-zA-Z.:_-]+$`.

- [ ] **Step 1: тесты ссылки.**
  - `goldenMinimal`: `freeturn://eyJ2IjoxLCJwcm92aWRlciI6InZrIiwicGVlciI6IjEuMi4zLjQ6NTYwMDAifQ` → `provider == "vk"`, `peer == "1.2.3.4:56000"`, `wgConf == ""`.
  - `allFields`: payload `{"v":1,"provider":"direct","peer":"5.6.7.8:56001","transport":"udp","obf":"rtpopus3","key":"<64 hex>","timing":20,"n":8,"spc":6,"cid":"<32 hex>","dns":"doh","dnss":"1.1.1.1,8.8.8.8","mcap":true,"name":"RU","vk":"https://vk.ru/call/join/x","wg":"[Interface]\nPrivateKey = a\n"}` → каждое поле равно ожидаемому.
  - `unknownFieldsIgnored`: лишний ключ `zzz` не мешает.
  - `tolerantInput` (Review Focus 2): `"  FREETURN://<payload>==\n"` разбирается как `goldenMinimal`.
  - `errors`: `http://x` → `.invalidScheme`; `freeturn://` → `.emptyPayload`; `freeturn://!!!` → `.badEncoding`; payload `not json` → `.badEncoding`; `v:2` → `.unsupportedVersion`; без `provider` → `.missingProvider`; без `peer` → `.missingPeer`.
- [ ] **Step 2: тесты импорта.**
  - `tcpModeRejected`: `mode:"tcp"` → `ImportError.tcpModeUnsupported`.
  - `unknownProviderRejected`; `badObfKeyRejected` (профиль `rtpopus3`, ключ из 10 символов → `.badObf`).
  - `relayWithoutCallLinkNeedsOne`: `needsCallLink == true`; для `direct` — `false`.
  - `linkWithoutWgNeedsWireGuard`: `needsWireGuard == true`.
  - `duplicateAddressDetectedCaseInsensitive`; `duplicateConfDetectedAfterTrim`.
  - `suggestedNameFallsBackToHost`: без `name` → `"1.2.3.4"`.
  - `makeServerMapsFields`: `n:0` → `threads == 12`; `timing:999` → `obfTimingMs == 60`; `transport:"udp"` → `useUdp == true`; непустой `wg` → `tunnelTransport == "wireguard"`; `dnss:"1.1.1.1; bad!token 8.8.8.8"` → `customDns == "1.1.1.1,8.8.8.8"`.
- [ ] **Step 3:** Run `make test-app` — FAIL.
- [ ] **Step 4: реализация.** Разбор: trim пробелов и переводов строк, схема без учёта регистра, срезать хвостовые `=`, base64url без padding. Кодировать ссылку в этом этапе не нужно.
- [ ] **Step 5:** Run `make test-app` — PASS.
- [ ] **Step 6:** Commit `feat(kit): freeturn:// link parsing and import planning`.

---

### Task 5: Kit — разбор WG-конфига

**Files:**
- Create: `App/Sources/FreeTurnKit/Tunnel/WGConfig.swift`
- Test: `App/Tests/FreeTurnKitTests/WGConfigTests.swift`

**Interfaces:**
- Produces:
  - `struct WGConfig: Equatable`: `privateKey: String`, `addresses: [String]`, `dns: [String]`, `amnezia: [String: String]` (ключи в нижнем регистре), `peers: [Peer]`; `var isAmnezia: Bool { !amnezia.isEmpty }`.
  - `struct Peer: Equatable`: `publicKey`, `presharedKey: String?`, `allowedIPs: [String]`, `persistentKeepalive: Int?`.
  - `static func parse(_ text: String) throws -> WGConfig`.
  - `enum WGConfigError: Error, Equatable { missingInterface, missingPrivateKey, missingPeer, missingPublicKey(peer: Int), missingAddress }`.
- Ключи Amnezia: `jc jmin jmax s1 s2 s3 s4 h1 h2 h3 h4 i1 i2 i3 i4 i5 headerprotectionkey contentpaddingaddition rekeyaftertime rekeytimeout rejectaftertime keepalivetimeout maxhandshakeattempts randomtrailers disablecookies`. `MTU` и `Endpoint` читаются и отбрасываются.

- [ ] **Step 1: тесты.**
  - `plainWireGuard`: обычный конфиг → `isAmnezia == false`, один peer, `allowedIPs == ["0.0.0.0/0", "::/0"]`, `persistentKeepalive == 25`.
  - `amneziaKeysCollected`: с `Jc = 4`, `H1 = 12345`, `I1 = <b 0x…>` → `amnezia["jc"] == "4"`, `amnezia["i1"]` сохранён дословно.
  - `messyRealWorldInput` (Review Focus 1): CRLF, строки `# коммент` и `; коммент`, `privatekey=abc`, `ADDRESS = 10.0.0.2/32 , fd00::2/128`, хвостовой комментарий после значения → `addresses == ["10.0.0.2/32", "fd00::2/128"]`, `privateKey == "abc"`.
  - `base64ValueWithEqualsKept`: `PrivateKey = abc=` → `"abc="`.
  - `twoPeers`.
  - `errors`: без `[Interface]`, без `PrivateKey`, без `[Peer]`, peer без `PublicKey`, без `Address` — соответствующие ошибки.
- [ ] **Step 2:** Run `make test-app` — FAIL.
- [ ] **Step 3: реализация.** Строка делится по первому `=`; комментарий срезается по ` #` и ` ;` и в начале строки.
- [ ] **Step 4:** Run `make test-app` — PASS.
- [ ] **Step 5:** Commit `feat(kit): wg-quick config parser with AmneziaWG keys`.

---

### Task 6: Kit — конфиг ядра

**Files:**
- Create: `App/Sources/FreeTurnKit/Core/CoreConfig.swift`
- Test: `App/Tests/FreeTurnKitTests/CoreConfigTests.swift`

**Interfaces:**
- Consumes: `Server`, `DnsList`.
- Produces: `enum CoreConfig { static func build(server: Server, listenPort: Int, ownClientId: String, systemDNS: [String], advancedCaptcha: Bool) -> String }`.

- [ ] **Step 1: тесты** (результат парсится в словарь).
  - `fixedFields`: `tunnel == {"mode":"none","config":"","mtu":1280}`, `proxy == {"mode":"udp","listen":"127.0.0.1:41000"}`, `vk.platform == "desktop"`, `routes == false`, `subUrl == ""`, ключа `kcp` нет, ключа `proxy.bond` нет.
  - `topLevelKeysExact`: набор ключей равен `peer clientId subUrl provider routes turn proxy vk obf dns log tunnel`.
  - `directUsesOneThread`: `provider:"direct"` → `turn.n == 1`.
  - `relayThreadsAndLink`: `threads:10`, `callLink:"L"` → `turn.n == 10`, `vk.links == ["L"]`.
  - `transport`: `useUdp` → `"udp"`, иначе `"tcp"`.
  - `magicTurn`: включён → `turn.host` равен обрезанному значению; выключен → `""`.
  - `obfOff`: профиль `none` → `obf == {"profile":"none","key":"","timingMs":0}` даже при заданных ключе и пейсинге.
  - `clientIdFallsBackToOwn`.
  - `dnsPriority`: `customDns` задан → он; иначе при `useCarrierDns` → `systemDNS`; иначе `[]`.
  - `advancedCaptchaOffWhenManual`: `manualCaptcha && advancedCaptcha` → `vk.advancedCaptcha == false`; `vk.autoCaptcha == true` всегда.
- [ ] **Step 2:** Run `make test-app` — FAIL.
- [ ] **Step 3: реализация** через `JSONSerialization` со словарём.
- [ ] **Step 4:** Run `make test-app` — PASS.
- [ ] **Step 5: проверка ядром.** Тест Go `helper/internal/bridge/fixture_test.go` `TestSwiftFixtureAccepted`: файл `helper/internal/bridge/testdata/core-config.json` (положить вывод `CoreConfig.build` для сервера `direct`) проходит `mobile.ValidateConfig` с пустым результатом. Run `make test-go` — PASS.
- [ ] **Step 6:** Commit `feat(kit): core config builder`.

---

### Task 7: Kit — маршрутизация и конфиг движка

**Files:**
- Create: `App/Sources/FreeTurnKit/Routing/RoutingProfile.swift`, `Routing/Presets.swift`, `Routing/EngineConfig.swift`
- Test: `App/Tests/FreeTurnKitTests/EngineConfigTests.swift`, `RoutingProfileTests.swift`

**Interfaces:**
- Consumes: `WGConfig`.
- Produces:
  - `enum RouteAction: String, Codable { case vpn, direct, block }`.
  - `enum RuleKind: String, Codable { case app, domain, domainSuffix, domainKeyword, cidr }`.
  - `struct RoutingRule: Codable, Identifiable, Equatable { id; kind; value; action; enabled = true }`.
  - `struct RoutingProfile: Codable, Identifiable, Equatable { id; name; defaultAction: RouteAction (.vpn или .direct); rules: [RoutingRule]; builtIn = false }`.
  - `struct RoutingFile: Codable { profiles: [RoutingProfile]; sharedProfileId: String }`; `func profile(for server: Server) -> RoutingProfile`.
  - `enum Presets { static let allViaVPN: RoutingProfile; static let russiaDirect: RoutingProfile }`.
  - `struct EngineSettings { stack = "mixed"; vpnDNS: String? = nil; debug = false }`.
  - `enum EngineConfig { static func build(wg: WGConfig, corePort: Int, profile: RoutingProfile, settings: EngineSettings) throws -> String }`.
  - `enum EngineConfigError: Error { invalidRule(id: String) }`.
- Форма конфига (проверена `amnezia-box check`):
  - `log: {level}`; `inbounds: [{type:"tun", tag:"tun-in", address:["172.19.0.1/30"] (+ "fdfe:dcba:9876::1/126", если у WG есть IPv6-адрес), mtu:1280, auto_route:true, stack}]`; при `AllowedIPs` без `0.0.0.0/0` — `route_address` из них.
  - `endpoints: [{type: "awg" | "wireguard", tag:"vpn", address, private_key, mtu:1280, <ключи amnezia>, peers:[{address:"127.0.0.1", port:<corePort>, public_key, pre_shared_key?, allowed_ips, persistent_keepalive_interval?}]}]`. Для `awg` ключ общего секрета называется `preshared_key`, числовые `jc jmin jmax s1..s4` — числа, остальные — строки, `random_trailers`/`disable_cookies` — bool, имена в snake_case (`header_protection_key`, …).
  - `outbounds: [{type:"direct", tag:"direct"}]`.
  - `dns: {servers:[{type:"udp", tag:"vpn-dns", server:<vpnDNS ?? первый DNS из WG ?? "1.1.1.1">, detour:"vpn"}, {type:"local", tag:"local-dns"}], rules:[…], final}`.
  - `route: {auto_detect_interface:true, default_domain_resolver:"local-dns", final, rules:[{action:"sniff"}, {protocol:"dns", action:"hijack-dns"}, {ip_is_private:true, outbound:"direct"}, …пользовательские по порядку]}`.
  - Правило `app`: значение с суффиксом `.app` → `process_path_regex: ["^" + экранированный путь + "/"]`; иначе `process_path`. `block` → `action:"reject"`. `final`: `vpn` или `direct` по `defaultAction`. DNS: доменные правила с действием `direct` идут в `local-dns`, с `vpn` — в `vpn-dns`; `dns.final` — `vpn-dns` при `defaultAction == .vpn`, иначе `local-dns`.

- [ ] **Step 1: тесты.**
  - `wireguardEndpoint`: обычный WG → `endpoints[0].type == "wireguard"`, `peers[0].address == "127.0.0.1"`, `peers[0].port == 41000`, `mtu == 1280`, `pre_shared_key` на месте.
  - `awgEndpoint`: с `Jc=4`, `H1=1`, `HeaderProtectionKey=k`, `RandomTrailers=true` → `type == "awg"`, `jc == 4` (число), `h1 == "1"`, `header_protection_key == "k"`, `random_trailers == true`, общий секрет под `preshared_key`.
  - `baseRulesFirst`: первые три правила — sniff, hijack-dns, private → direct.
  - `ruleKinds`: `domain` → `domain`, `domainSuffix` → `domain_suffix`, `domainKeyword` → `domain_keyword`, `cidr` → `ip_cidr`; порядок сохранён; выключенные пропущены.
  - `blockIsReject`.
  - `appBundleRegexEscaped` (Review Focus 3): `/Applications/Яндекс Музыка (beta).app` → `process_path_regex == ["^/Applications/Яндекс Музыка \\(beta\\)\\.app/"]`.
  - `appExecutablePath`: `/usr/bin/curl` → `process_path`.
  - `defaultDirectMode`: `route.final == "direct"`, `dns.final == "local-dns"`.
  - `dnsRulesFollowDomainRules`.
  - `ipv6OnlyWhenConfigured`.
  - `partialAllowedIPsBecomeRouteAddress`: `AllowedIPs = 10.0.0.0/8` → `inbounds[0].route_address == ["10.0.0.0/8"]`.
  - `emptyRuleValueThrows`; `badCidrThrows` → `invalidRule`.
  - `russiaDirectPresetNonEmptyAndDirect`: все правила пресета с действием `direct`, домены среди них: `vk.com`, `yandex.ru`, `gosuslugi.ru`, `sberbank.ru`, `ozon.ru`, `wildberries.ru`.
  - `engineAcceptsGeneratedConfig`: если существует `../build/amnezia-box`, сгенерированные конфиги WG и AWG проходят `amnezia-box check -c` с кодом 0; иначе тест пропускается.
- [ ] **Step 2:** Run `make test-app` — FAIL.
- [ ] **Step 3: реализация.** Пресет `russiaDirect` — доменные суффиксы российских сервисов (банки, маркетплейсы, госуслуги, Яндекс, VK, операторы, `.ru`-зона через `domainSuffix "ru"` и `"рф"`), `defaultAction: .vpn`.
- [ ] **Step 4:** Run `make engine && make test-app` — PASS, тест `engineAcceptsGeneratedConfig` не пропущен.
- [ ] **Step 5:** Commit `feat(kit): routing profiles and engine config builder`.

---

### Task 8: Проба вживую — ворота перед службой и интерфейсом

**Files:**
- Create: `App/Sources/ftctl/main.swift`, `App/Sources/FreeTurnKit/System/SystemNetwork.swift`
- Modify: `App/Package.swift` (цель `ftctl`), `Makefile` (цель `ftctl`)
- Create: `docs/proof-run.md` (журнал результата)

**Interfaces:**
- Produces:
  - `struct NetworkSnapshot: Equatable { ifName: String; ifIndex: Int32; dns: [String] }`; `enum SystemNetwork { static func current() -> NetworkSnapshot? }` — интерфейс маршрута по умолчанию, кроме `utun*` и `lo*`; DNS из `SCDynamicStore` (`State:/Network/Global/DNS`).
  - `ftctl gen --link <freeturn://…> [--call-link <url>] [--wg <file>] --out <dir>` пишет `core-start.jsonl` (готовая команда `start`), `engine.json`; печатает выбранный порт и интерфейс.

- [ ] **Step 1:** Реализовать `SystemNetwork.current()` и `ftctl gen`. Run `swift run ftctl gen …` на ссылке пользователя — два файла созданы, `build/amnezia-box check -c engine.json` возвращает 0.
- [ ] **Step 2: прогон** (нужны ссылка пользователя и `sudo`; команды с `sudo` запускает пользователь):
  1. `(cat out/core-start.jsonl; cat) | build/freeturn-core -state-dir /tmp/ft-core` — дождаться `state=connected`.
  2. `sudo build/amnezia-box run -c out/engine.json` — дождаться `sing-box started`.
- [ ] **Step 3: чек-лист**, результаты записать в `docs/proof-run.md`:
  - [ ] `curl https://ifconfig.me` показывает IP сервера.
  - [ ] В логе ядра нет лавины переподключений: сокеты ядра идут мимо туннеля.
  - [ ] С правилом `app` для `/usr/bin/curl` → `direct`: `curl` показывает домашний IP, браузер — IP сервера.
  - [ ] С правилом `domainSuffix ifconfig.me` → `direct`: домашний IP.
  - [ ] Конфиг AWG (если есть сервер с Amnezia): рукопожатие проходит.
  - [ ] Ctrl-C движка: интернет возвращается сразу, utun исчез.
- [ ] **Step 4: решение.** Все пункты, кроме AWG, обязательны. Не работает туннель или обход петли — остановиться и вернуться к пользователю с запасным путём из спеки (обычный sing-box, только WireGuard). Не работает только AWG — зафиксировать ограничение в `docs/proof-run.md` и продолжить.
- [ ] **Step 5:** Commit `feat: ftctl and live proof run`.

---

### Task 9: freeturnd — служба и установка

**Files:**
- Create: `helper/cmd/freeturnd/main.go`, `helper/internal/daemon/server.go`, `daemon/sanitize.go`, `daemon/engine.go`
- Create: `scripts/install-daemon.sh`, `scripts/uninstall-daemon.sh`
- Test: `helper/internal/daemon/server_test.go`, `sanitize_test.go`, `testdata/fake-engine.sh`

**Interfaces:**
- Produces:
  - `freeturnd -socket /var/run/freeturnd.sock -owner-uid <uid> -engine /Library/PrivilegedHelperTools/dev.freeturn/amnezia-box -state-dir /var/db/freeturnd`.
  - Протокол сокета, строки JSON. Запросы: `{"cmd":"start","config":"<JSON движка строкой>"}`, `{"cmd":"stop"}`, `{"cmd":"status"}`. Ответы: `{"ok":true}`, `{"ok":false,"err":"…"}`, для `status` — `{"ok":true,"running":false,"version":"1"}`. Асинхронно: `{"ev":"log","line":"…"}`, `{"ev":"exit","code":1,"tail":"…последние 20 строк"}`.
  - `const ProtocolVersion = "1"`.
  - Go: `func Sanitize(raw []byte) ([]byte, error)`; `type Config struct{ Socket, Engine, StateDir string; OwnerUID int }`; `func Serve(ctx context.Context, cfg Config) error`.
- Правила: один клиент одновременно, второму — `{"ok":false,"err":"busy"}`. Закрытие соединения останавливает движок (SIGTERM, через 5 с SIGKILL). `start` отвечает `ok` после строки `sing-box started` в выводе движка или ошибкой через 20 с либо при раннем выходе. Сокет: владелец `owner-uid`, права `0600`; дополнительно uid собеседника проверяется через `LOCAL_PEERCRED`. Движок запускается как `<engine> run -c <state-dir>/config.json -D <state-dir>`, конфиг пишется с правами `0600`.
- `Sanitize`: верхние ключи только `log dns inbounds endpoints outbounds route`; `log` заменяется на `{"level": <debug|info|warn|error, иначе info>, "timestamp": true}`; при обходе всего дерева ключ, равный `path` или `output` либо оканчивающийся на `_path`, приводит к ошибке; тип входа только `tun`; тип выхода только `direct`; тип точки только `wireguard` или `awg`.

- [ ] **Step 1: тесты `sanitize_test.go`.** `TestAcceptsGeneratedShape` (на `testdata/engine.json` — положить туда вывод `EngineConfig.build` из Task 7 для обычного WG); `TestRejectsUnknownTopLevel` (`experimental`); `TestLogIsRewritten` (вход с `log.output:"/etc/passwd"` → на выходе ключа `output` нет, уровень сохранён); `TestRejectsPathKeys` (`certificate_path` в глубине); `TestRejectsForeignInbound` (`type:"mixed"`); `TestRejectsForeignOutbound` (`type:"socks"`); `TestRejectsBadJSON`.
- [ ] **Step 2: тесты `server_test.go`** (временный сокет, `OwnerUID = os.Getuid()`, движок — `fake-engine.sh`: печатает `sing-box started`, затем `sleep 600`; вариант `FAIL=1` выходит с кодом 3).
  - `TestStatusIdle`; `TestStartStop` (после `start` `running:true`, после `stop` процесс движка исчез).
  - `TestCloseKillsEngine`: закрыть соединение → за ≤ 6 с процесс движка исчез.
  - `TestEngineEarlyExit`: `FAIL=1` → ответ `ok:false`, `err` содержит хвост вывода.
  - `TestSecondClientBusy`.
  - `TestSocketMode0600`.
  - `TestStartRejectsUnsanitary`: конфиг с `experimental` → `ok:false`, движок не запускался.
  - `TestExitEvent`: движок убит снаружи → клиент получает `ev=exit`.
- [ ] **Step 3:** Run `make test-go` — FAIL.
- [ ] **Step 4: реализация** по интерфейсам выше.
- [ ] **Step 5:** Run `make test-go` — PASS.
- [ ] **Step 6: скрипты.** `install-daemon.sh <путь к каталогу с freeturnd и amnezia-box> <uid>`: требует root; создаёт `/Library/PrivilegedHelperTools/dev.freeturn/` (root:wheel, 755), копирует оба бинарника (root:wheel, 755), создаёт `/var/db/freeturnd` (700), пишет `/Library/LaunchDaemons/dev.freeturn.daemon.plist` (`RunAtLoad`, `KeepAlive`, аргументы из интерфейса), `launchctl bootout` старой и `launchctl bootstrap system` новой. `uninstall-daemon.sh`: bootout, удалить plist, каталог бинарников, `/var/db/freeturnd`, сокет. Оба с `set -euo pipefail`, uid проверяется как число.
- [ ] **Step 7:** Run `bash -n scripts/*.sh` — без ошибок. Commit `feat(helper): freeturnd root service with config sanitizing`.

---

### Task 10: Kit — управление подключением

**Files:**
- Create: `App/Sources/FreeTurnKit/Connection/CoreProcess.swift`, `Connection/DaemonClient.swift`, `Connection/ConnectionController.swift`, `Connection/NetworkWatcher.swift`, `Connection/Events.swift`
- Test: `App/Tests/FreeTurnKitTests/ConnectionControllerTests.swift`, `EventsTests.swift`

**Interfaces:**
- Consumes: `CoreConfig`, `EngineConfig`, `WGConfig`, `RoutingProfile`, `SystemNetwork`, `NetworkSnapshot`, протоколы Task 2 и Task 9.
- Produces:
  - `enum CoreEvent: Equatable { hello(version), state(phase: CorePhase, streams: Int, total: Int, err: String), log(level, msg, ts: Date), captcha(url: String, manual: Bool), stats(tx: Int64, rx: Int64, txRate: Int64, rxRate: Int64), args(String), error(cmd: String, err: String), exited }`; `enum CorePhase: String { idle, connecting, connected, captcha, error }`; `static func decode(line: String) -> CoreEvent?`.
  - `protocol CoreControlling: AnyObject { var events: AsyncStream<CoreEvent> { get }; func launch() throws; func send(_ cmd: CoreCommand); func terminate() }`; `enum CoreCommand { start(config: String, ifIndex: Int32), stop, reconnect(ifIndex: Int32, dns: [String]), wake, args(config: String) }`; `func encoded() -> String`.
  - `protocol EngineControlling: AnyObject { var events: AsyncStream<EngineEvent> { get }; func status() async throws -> DaemonStatus; func start(config: String) async throws; func stop() async; func close() }`; `enum EngineEvent { log(String), exited(code: Int, tail: String) }`; `struct DaemonStatus { running: Bool; version: String }`; `enum DaemonError: Error { notInstalled, busy, versionMismatch(String), failed(String) }`.
  - `final class CoreProcess: CoreControlling` (дочерний процесс `freeturn-core`), `final class DaemonClient: EngineControlling` (unix-сокет).
  - `protocol NetworkWatching { var changes: AsyncStream<NetworkSnapshot?> { get }; func current() -> NetworkSnapshot? }`.
  - `struct TrafficStats: Equatable { tx, rx, txRate, rxRate: Int64 }`.
  - `struct LogLine: Identifiable, Equatable { id: Int; date: Date; level: LogLevel; source: LogSource; text: String }`; `enum LogLevel: String { debug, info, warn, error }`; `enum LogSource: String { core, engine, app }` (файл `Connection/Events.swift`).
  - `enum ConnectionState: Equatable { off, starting, connecting(streams: Int, total: Int), captcha(url: String, manual: Bool), connected(streams: Int, total: Int), failed(String), stopping }`.
  - `@MainActor @Observable final class ConnectionController`: `init(core: () -> CoreControlling, engine: () -> EngineControlling, network: NetworkWatching, portPicker: () -> Int)`; `private(set) var state`, `stats: TrafficStats`, `connectedSince: Date?`, `captcha: (url: String, manual: Bool)?`; `func connect(server: Server, profile: RoutingProfile, settings: AppSettings, ownClientId: String)`, `func disconnect()`, `func systemDidWake(sleptSeconds: TimeInterval)`; `var onLog: ((LogLine) -> Void)?`.
- Порядок запуска: проверить службу (`status`, сверка `version` с `"1"`) → выбрать свободный UDP-порт → запустить ядро и отправить `start` → при первом `state=connected` запустить движок → `connected`. До первого `connected` системная сеть не трогается. Остановка: движок, затем ядро. Ошибка ядра, выход ядра, `ev=exit` движка или ошибка `start` движка → остановить всё и перейти в `failed(<причина>)`, без автоповтора.
- Сеть: `nil` (сети нет) — ничего не слать; новый снимок с другим `ifIndex` или DNS — `reconnect`. Пробуждение: `sleptSeconds >= 60` → `wake`.

- [ ] **Step 1: тесты `EventsTests`.** Каждая строка протокола Task 2 декодируется в свой `CoreEvent`; мусорная строка → `nil`; `CoreCommand.start(config: "{\"a\":1}", ifIndex: 14).encoded()` — валидный JSON с `cmd == "start"`, `config == "{\"a\":1}"`, `ifIndex == 14`.
- [ ] **Step 2: тесты `ConnectionControllerTests`** (подставные `FakeCore`, `FakeEngine`, `FakeNetwork`).
  - `engineStartsOnlyAfterFirstConnected`: после `connect` движок не запущен; после события `state=connected` у `FakeEngine` один `start`, состояние `connected`.
  - `engineConfigTargetsPickedPort`: в конфиге, ушедшем движку, `peers[0].port` равен порту из `portPicker`, тот же порт в `proxy.listen` конфига ядра.
  - `disconnectStopsEngineThenCore`: порядок вызовов `engine.stop`, `core.stop`.
  - `coreErrorTearsDownEverything`: `state=error, err="boom"` → движок остановлен, состояние `failed("boom")`.
  - `coreStartErrorFails`: `error(cmd:"start", err:"address already in use")` → `failed`, движок не запускался.
  - `engineExitTearsDownCore`.
  - `daemonNotInstalledFailsBeforeCoreLaunch`: `status` бросает `.notInstalled` → ядро не запускалось.
  - `daemonVersionMismatchFails`.
  - `captchaEventSurfaces`: `captcha(url:"http://localhost:8765/x", manual:true)` → `state == .captcha(…)`; `captcha(url:"")` → `captcha == nil`.
  - `networkChangeSendsReconnect`: новый снимок с другим `ifIndex` → ядру ушёл `reconnect` с новым индексом и DNS.
  - `networkLossThenReturn` (Review Focus 5): `nil` → команд нет, состояние прежнее; затем снимок → один `reconnect`.
  - `sameNetworkNoReconnect`.
  - `wakeAfterLongSleepOnly`: 30 с → нет `wake`; 90 с → есть.
  - `serverWithoutWireGuardFails`: `failed` с текстом про отсутствие конфига WireGuard, ничего не запущено.
  - `relayWithoutCallLinkFails`.
  - `statsUpdate`; `connectedSinceSetOnceAndClearedOnDisconnect`.
- [ ] **Step 3:** Run `make test-app` — FAIL.
- [ ] **Step 4: реализация.** `CoreProcess` ищет бинарник в `Bundle.main` (`Contents/Helpers/freeturn-core`), `-state-dir` — `Application Support/FreeTurn/core-state`. `DaemonClient` — `NWConnection` или POSIX-сокет к `/var/run/freeturnd.sock`; отсутствие сокета → `.notInstalled`. `NetworkWatcher` — `NWPathMonitor` + `SystemNetwork.current()`, дебаунс 1 с.
- [ ] **Step 5:** Run `make test-app` — PASS.
- [ ] **Step 6:** Commit `feat(kit): connection controller, core process and daemon client`.

---

### Task 11: Приложение — каркас, Главная, строка меню, упаковка, установка службы

**Files:**
- Create: `App/Sources/FreeTurn/FreeTurnApp.swift`, `AppModel.swift`, `Views/RootView.swift`, `Views/HomeView.swift`, `Views/ConnectButton.swift`, `Views/MenuBarView.swift`, `Views/DaemonInstallView.swift`, `Services/DaemonInstaller.swift`
- Create: `App/Sources/FreeTurn/Resources/ru.lproj/Localizable.strings`, `en.lproj/Localizable.strings`, `Resources/Info.plist.in`, `Resources/AppIcon.icns`
- Create: `scripts/bundle-app.sh`
- Modify: `App/Package.swift` (цель `FreeTurn`, ресурсы)
- Test: `App/Tests/FreeTurnKitTests/FormattersTests.swift`; Create: `App/Sources/FreeTurnKit/Util/Formatters.swift`

**Interfaces:**
- Consumes: `ConnectionController`, `Store`, `ServersFile`, `RoutingFile`, `AppSettings`.
- Produces:
  - `@MainActor @Observable final class AppModel`: `servers: ServersFile`, `routing: RoutingFile`, `settings: AppSettings`, `connection: ConnectionController`, `loadError: String?`; `func toggleConnection()`, `func setActive(_ id: String)`, `func persist()`.
  - `enum DaemonInstaller { static func install() async throws; static func uninstall() async throws }` — `osascript` c `do shell script … with administrator privileges`, скрипты и бинарники берутся из `Contents/Resources/daemon/` бандла, пути экранируются через `quoted form of`.
  - `enum Formatters { static func bytes(_: Int64) -> String; static func rate(_: Int64) -> String; static func duration(_: TimeInterval) -> String }`.
  - `build/FreeTurn.app`: `Contents/MacOS/FreeTurn`, `Contents/Helpers/freeturn-core`, `Contents/Resources/daemon/{freeturnd,amnezia-box,install-daemon.sh,uninstall-daemon.sh}`, ресурсный бандл SwiftPM, `Info.plist` с `CFBundleIdentifier dev.freeturn.macos`, `CFBundleURLTypes` для схемы `freeturn`, `LSMinimumSystemVersion 14.0`.

- [ ] **Step 1: тесты `FormattersTests`.** `bytes(0) == "0 Б"`, `bytes(1536) == "1,5 КБ"`, `bytes(1_395_864_371) == "1,3 ГБ"`, `rate(4_404_019) == "4,2 МБ/с"`, `duration(134) == "02:14"`, `duration(3725) == "1:02:05"`. Run `make test-app` — FAIL, реализовать, PASS.
- [ ] **Step 2: окно.** `NavigationSplitView` с разделами Главная, Серверы, Маршруты, Логи, Настройки (последние четыре — заглушки до своих задач). Главная по эскизу спеки: кнопка-круг с состояниями (выключено, подключение, капча, подключено, ошибка), строка «сервер · провайдер · N/M потоков» (потоки скрыты для Direct), скорость, трафик, время сессии, активный профиль маршрутов, текст ошибки под кнопкой. Нет серверов — пустое состояние с кнопкой «Добавить сервер».
- [ ] **Step 3: строка меню.** `MenuBarExtra` со стилем `.menu`: состояние, подключить или отключить, список серверов с отметкой активного, скорость, «Открыть FreeTurn», «Выйти». Иконка SF Symbol меняется по состоянию: выключено, подключение, подключено, капча, ошибка. Закрытие окна не завершает приложение; «Выйти» отключает и завершает.
- [ ] **Step 4: служба.** Если `status` бросает `.notInstalled` или `.versionMismatch`, вместо подключения показывается `DaemonInstallView` с объяснением и кнопкой «Установить» (вызывает `DaemonInstaller.install()`).
- [ ] **Step 5: упаковка.** `scripts/bundle-app.sh`: `swift build -c release --package-path App --product FreeTurn`, собрать структуру бандла, `codesign --force --deep --sign - build/FreeTurn.app`.
- [ ] **Step 6: проверка.** Run `make app && make run`. Ожидается: окно открывается, иконка в строке меню есть, без серверов видно пустое состояние, `codesign -dv build/FreeTurn.app` показывает `Signature=adhoc`, `plutil -p build/FreeTurn.app/Contents/Info.plist` содержит схему `freeturn`.
- [ ] **Step 7:** Commit `feat(app): app shell, home screen, menu bar, bundling and daemon install`.

---

### Task 12: Серверы и импорт

**Files:**
- Create: `App/Sources/FreeTurn/Views/Servers/ServersView.swift`, `ServerDetailView.swift`, `AddServerView.swift`, `ImportSheet.swift`
- Create: `App/Sources/FreeTurnKit/Link/QRDecoder.swift`
- Modify: `App/Sources/FreeTurn/FreeTurnApp.swift` (обработка `onOpenURL`), `AppModel.swift`
- Test: `App/Tests/FreeTurnKitTests/QRDecoderTests.swift`, `ServersFileTests.swift`

**Interfaces:**
- Consumes: `FreeturnLink`, `ImportPlanner`, `ImportDraft`, `WGConfig`, `DnsList`, `ObfProfile`.
- Produces:
  - `enum QRDecoder { static func decode(_ image: CGImage) -> [String] }` (Vision).
  - `extension ServersFile { mutating func add(_ s: Server, activate: Bool); mutating func remove(id: String); mutating func clone(id: String) -> Server?; mutating func rename(id: String, to: String) }`.
  - `AppModel.offerImport(_ raw: String)` — открывает `ImportSheet` или панель ошибки.

- [ ] **Step 1: тесты.** `QRDecoderTests.decodesGeneratedQR`: QR, сгенерированный `CIFilter.qrCodeGenerator` из строки `freeturn://abc`, декодируется в `["freeturn://abc"]`; `noQRReturnsEmpty`. `ServersFileTests`: `addActivates`; `removeActiveSelectsFirstRemaining`; `removeLastClearsActive`; `cloneCopiesWithNewIdAndSuffixedName` (имя `"RU (копия)"`); `renameTrimsAndKeepsOldOnEmpty`.
- [ ] **Step 2:** Run `make test-app` — FAIL, реализовать, PASS.
- [ ] **Step 3: список.** Строка сервера: имя, адрес (скрыт при приватном режиме), значок провайдера, отметка активного; контекстное меню: сделать активным, переименовать, клонировать, удалить (с подтверждением «Сервер и все его настройки будут удалены из приложения»). Менять активный сервер и его параметры при живом подключении нельзя — подсказка «Остановите подключение».
- [ ] **Step 4: добавление.** Поле «Вставьте ссылку» с кнопкой «Вставить» (если в буфере нет `freeturn://` — «В буфере обмена нет ссылки freeturn://»); «QR-код» — файл картинки, картинка из буфера, снимок области экрана через `/usr/sbin/screencapture -i -c`; «Ручная настройка» — создаёт пустой сервер с именем «Новый сервер».
- [ ] **Step 5: панель импорта.** Имя, тип доступа (WireGuard, AmneziaWG или «нет конфига»), адрес, значок обфускации; поле «Ссылка на звонок» при `needsCallLink` (подпись «Ссылка пришла вместе с доступом — можно заменить своей», если она была в ссылке); предупреждения о дубле адреса и дубле конфига; кнопка «Импортировать» неактивна без ссылки на звонок для Relay. Ошибки `LinkError` и `ImportError` — панель «Ошибка импорта» с причиной; для `tcpModeUnsupported` — «Этот сервер работает в TCP-режиме для Xray, клиент для macOS его не поддерживает».
- [ ] **Step 6: карточка сервера.** Секции: Подключение (адрес `host:port`, провайдер Relay или Direct, ссылка на звонок — только для Relay), Производительность (потоки 1…24, потоков на аккаунт 1…24 — только Relay), Обфускация (профиль, ключ 64 hex с проверкой и кнопкой «Сгенерировать», пейсинг 0…60 шагом 5), DNS (режим авто, plain, DoH; ручной список с предупреждением о некорректных адресах; «DNS текущей сети»), Дополнительно — только Relay (транспорт TCP или UDP, ручная капча, запасной TURN-узел), Туннель (текст конфига, «Загрузить из файла», определённый тип WG или AWG, ошибка разбора), Маршруты (выбор профиля или «общий»). Сервер без конфига WG показывает плашку «Добавьте конфиг WireGuard, чтобы подключиться».
- [ ] **Step 7: проверка.** Run `make app && make run`; затем `open "freeturn://eyJ2IjoxLCJwcm92aWRlciI6InZrIiwicGVlciI6IjEuMi4zLjQ6NTYwMDAifQ"`. Ожидается: открывается панель импорта с адресом `1.2.3.4:56000` и требованием ссылки на звонок; после импорта сервер в списке и активен; после перезапуска приложения он на месте.
- [ ] **Step 8:** Commit `feat(app): servers list, editing and link/QR import`.

---

### Task 13: Маршруты

**Files:**
- Create: `App/Sources/FreeTurn/Views/Routing/RoutingView.swift`, `RuleEditorView.swift`, `AppPickerView.swift`
- Create: `App/Sources/FreeTurnKit/Routing/InstalledApps.swift`, `Routing/ProfileTransfer.swift`
- Test: `App/Tests/FreeTurnKitTests/ProfileTransferTests.swift`, `RoutingFileTests.swift`

**Interfaces:**
- Consumes: `RoutingProfile`, `RoutingRule`, `RoutingFile`, `Presets`, `EngineConfig`.
- Produces:
  - `struct AppEntry: Identifiable, Hashable { id: String /* путь */; name: String; isRunning: Bool }`; `enum InstalledApps { static func list() -> [AppEntry] }` — `/Applications`, `~/Applications`, `/System/Applications` плюс запущенные через `NSWorkspace`.
  - `enum ProfileTransfer { static func export(_ p: RoutingProfile) throws -> Data; static func importProfile(_ data: Data) throws -> RoutingProfile }` — JSON с полями `format: "freeturn-routing"`, `version: 1`, `profile`.
  - `extension RoutingFile { static func initial() -> RoutingFile; mutating func add(_:); mutating func remove(id:); mutating func clone(id:) -> RoutingProfile? }`.

- [ ] **Step 1: тесты.** `exportImportRoundTrip`; `importRejectsWrongFormat`; `importRejectsNewerVersion`; `importAssignsFreshIdsAndClearsBuiltIn`; `initialHasBothPresetsAndSharedIsAllViaVPN`; `builtInProfileCannotBeRemoved`; `removingSharedFallsBackToAllViaVPN`; `profileForServerPrefersOwnThenShared`.
- [ ] **Step 2:** Run `make test-app` — FAIL, реализовать, PASS.
- [ ] **Step 3: экран.** Слева профили (встроенные помечены, их можно клонировать, но не менять), справа: имя, переключатель режима («Всё через VPN, кроме выбранного» / «Только выбранное через VPN»), таблица правил с перетаскиванием порядка, включением и действием (через VPN, напрямую, блокировать), кнопки «Добавить правило», «Импорт», «Экспорт», «Сделать общим». Редактор правила: тип (приложение, домен, суффикс домена, ключевое слово, подсеть), значение с проверкой на лету через пробную сборку `EngineConfig`. Выбор приложения — список с поиском, запущенные сверху. Тип туннеля (system, gvisor, mixed) — внизу экрана, пишет в `settings.tunStack`. Плашка «Изменения применятся при следующем подключении» с кнопкой «Переподключить», если подключение активно.
- [ ] **Step 4: проверка.** Run `make app && make run`: создать профиль, добавить правило для Safari → напрямую и `domainSuffix ifconfig.me` → напрямую, экспортировать, удалить, импортировать — правила на месте.
- [ ] **Step 5:** Commit `feat(app): routing profiles and rules editor`.

---

### Task 14: Капча

Изменено 2026-11-14 по просьбе пользователя: ручная капча — в отдельном окне поверх остальных, с настройкой «окно или браузер» (`AppSettings.captchaTarget`, уже добавлено).

**Files:**
- Create: `App/Sources/FreeTurnKit/Captcha/CaptchaURL.swift`, `Captcha/CaptchaPresenter.swift`
- Create: `App/Sources/FreeTurn/Views/Captcha/CaptchaWindowController.swift`, `CaptchaWebView.swift`, `Services/AutoCaptchaHost.swift`
- Modify: `AppModel.swift`, `Views/HomeView.swift`, `Views/MenuBarView.swift`, `Views/SettingsView.swift`
- Test: `App/Tests/FreeTurnKitTests/CaptchaURLTests.swift`, `CaptchaPresenterTests.swift`

**Interfaces:**
- Consumes: `ConnectionController.captcha`, `AppSettings.captchaTarget`.
- Produces:
  - `enum CaptchaURL { static func isLocal(_ url: String) -> Bool }` — схема `http`, хост `127.0.0.1` или `localhost`, порт `8765`, без userinfo.
  - `enum CaptchaAction: Equatable { showWindow(String), openBrowser(String), loadHidden(String), dismiss, none }`.
  - `struct CaptchaPresenter { mutating func action(for captcha: (url: String, manual: Bool)?, target: String) -> CaptchaAction; mutating func userClosedWindow(); func reopenAction(target: String) -> CaptchaAction }` — чистая логика без UI: что делать при каждом событии капчи.
  - `@MainActor final class CaptchaWindowController { func show(url: String, onUserClose: @escaping () -> Void); func close() }` — `NSPanel` 460×640, уровень `.floating`, заголовок «Проверка на робота».
  - `@MainActor final class AutoCaptchaHost { func show(url: String); func clear() }` — невидимый `WKWebView`.

- [ ] **Step 1: тесты `CaptchaURLTests`.** `isLocal`: `http://127.0.0.1:8765/a` и `http://localhost:8765/` → `true`; `https://localhost:8765/`, `http://localhost:8766/`, `http://evil.com:8765/`, `http://user@localhost:8765/`, `http://localhost.evil.com:8765/`, пустая строка, `file:///etc/passwd` → `false`.
- [ ] **Step 2: тесты `CaptchaPresenterTests`.**
  - `manualInWindowMode`: событие `(local, manual: true)`, `target "window"` → `.showWindow(url)`.
  - `manualInBrowserMode`: `target "browser"` → `.openBrowser(url)`.
  - `sameUrlIsNotShownTwice`: повтор того же события → `.none` (ядро шлёт состояние не один раз).
  - `newUrlReplacesOld`: другой адрес → снова `.showWindow`.
  - `clearedCaptchaDismisses`: `nil` или пустой адрес после показа → `.dismiss`; без показа → `.none`.
  - `autoCaptchaLoadsHidden`: `manual: false` → `.loadHidden(url)`, в обоих режимах.
  - `nonLocalUrlNeverShown`: `http://evil.com:8765/x` → `.none` в любом режиме (внешний адрес не открываем ни в окне, ни в браузере).
  - `reopenAfterUserClose`: после `userClosedWindow()` повтор того же события → `.none`, а `reopenAction` → `.showWindow(url)`; в режиме браузера → `.openBrowser(url)`; без активной капчи → `.none`.
- [ ] **Step 3:** Run `make test-app` — FAIL, реализовать, PASS.
- [ ] **Step 4: WebView.** Общая фабрика: `WKWebsiteDataStore.nonPersistent()`, JavaScript включён, навигация и новые окна разрешены только для `CaptchaURL.isLocal`, прочее отменяется. Окно: подпись «Пройдите проверку для продолжения», полоса загрузки, WebView.
- [ ] **Step 5: поведение.** `AppModel` на каждое изменение `connection.captcha` спрашивает `CaptchaPresenter` и выполняет действие: `showWindow` — окно поверх остальных и активация приложения; `openBrowser` — `NSWorkspace.shared.open`; `loadHidden` — `AutoCaptchaHost.show`, статус «CAPTCHA решается…»; `dismiss` — закрыть окно и `AutoCaptchaHost.clear()`. Отключение всегда даёт `dismiss`. Пока капча активна, на Главной и в строке меню статус «Нужна проверка CAPTCHA» и кнопка «Пройти проверку» (`reopenAction`). В настройках — «Открывать капчу: в окне приложения / в браузере».
- [ ] **Step 6: проверка.** Run `make app`. Проверка на живой ссылке на звонок с включённой «Ручной капчей» — в Task 17.
- [ ] **Step 7:** Commit `feat(app): captcha window, browser mode and background solver`.

---

### Task 15: Логи и приватный режим

**Files:**
- Create: `App/Sources/FreeTurnKit/Logs/LogStore.swift`, `Logs/Redactor.swift`, `Logs/LogFile.swift`
- Create: `App/Sources/FreeTurn/Views/LogsView.swift`
- Modify: `AppModel.swift` (подключить `connection.onLog`)
- Test: `App/Tests/FreeTurnKitTests/RedactorTests.swift`, `LogStoreTests.swift`, `LogFileTests.swift`

**Interfaces:**
- Consumes: `LogLine`, `LogLevel`, `LogSource`, `ConnectionController.onLog` (Task 10).
- Produces:
  - `enum Redactor { static func redact(_ text: String, secrets: [String]) -> String }` — заменяет IPv4 на `x.x.x.x`, IPv6 на `x:x`, `:<порт>` после адреса на `:•`, ссылки `https://vk.…/call/join/…` и любые строки из `secrets` на `•••`, 64-hex и 32-hex последовательности на `•••`.
  - `@MainActor @Observable final class LogStore { private(set) var lines: [LogLine]; init(capacity: Int = 5000); func append(level:source:text:); func clear() }`.
  - `final class LogFile { init(directory: URL, maxBytes: Int = 1_000_000); func append(_ line: String); func export(to: URL) throws; func clear() }` — при превышении `maxBytes` текущий файл переименовывается в `session.1.log`, пишется новый.

- [ ] **Step 1: тесты.** `RedactorTests`: IPv4 с портом; IPv6; ссылка на звонок; ключ 64 hex; client id 32 hex; строка из `secrets`; обычный текст без изменений; время `12:34:56` не тронуто. `LogStoreTests`: `capacityEvictsOldest`; `clearEmpties`. `LogFileTests`: `rotatesAtLimit` (после записи 1,2 МБ существуют оба файла, текущий меньше лимита); `exportConcatenatesOldThenNew`; `filesAre0600`.
- [ ] **Step 2:** Run `make test-app` — FAIL, реализовать, PASS.
- [ ] **Step 3: экран.** Моноширинный список с автопрокруткой, фильтр по уровню и источнику, поиск, кнопки «Копировать», «Очистить», «Сохранить в файл». Строки проходят `Redactor` на входе, если включён приватный режим; строка запуска «Команда: …» редактируется всегда для ссылок и ключей. Экранный лог чистится при новом подключении, файл — нет.
- [ ] **Step 4:** Run `make app && make run` — раздел «Логи» показывает строки приложения при запуске.
- [ ] **Step 5:** Commit `feat(app): logs with rotation and privacy redaction`.

---

### Task 16: Настройки, автозапуск, автоподключение, пинг, локализация

**Files:**
- Create: `App/Sources/FreeTurn/Views/SettingsView.swift`, `Views/DebugView.swift`, `Services/LoginItem.swift`, `Services/SleepWatcher.swift`
- Create: `App/Sources/FreeTurnKit/Util/PingMeter.swift`
- Modify: `AppModel.swift`, `Views/HomeView.swift`, оба `Localizable.strings`
- Test: `App/Tests/FreeTurnKitTests/LocalizationTests.swift`, `AutoConnectTests.swift`

**Interfaces:**
- Produces:
  - `enum PingMeter { static func measure(timeout: TimeInterval = 3) async -> Int? }` — время HTTP-запроса `https://www.gstatic.com/generate_204` в мс.
  - `enum LoginItem { static var isEnabled: Bool { get }; static func set(_ on: Bool) throws }` — `SMAppService.mainApp`.
  - `final class SleepWatcher { init(onWake: @escaping (TimeInterval) -> Void) }` — `NSWorkspace.willSleepNotification` и `didWakeNotification`.
  - `enum AutoConnect { static func shouldConnect(settings: AppSettings, hasActiveServer: Bool) -> Bool }` — `autoConnect && wasConnected && hasActiveServer`.
  - `AppModel.resetAll()`.

- [ ] **Step 1: тесты.** `AutoConnectTests`: четыре сочетания флагов, истина только когда все три истинны. `LocalizationTests.sameKeysInBothLanguages`: множества ключей `ru.lproj/Localizable.strings` и `en.lproj/Localizable.strings` равны; `noEmptyValues`.
- [ ] **Step 2:** Run `make test-app` — FAIL, реализовать, PASS.
- [ ] **Step 3: экран настроек.** Секции: Интерфейс (тема системная, светлая, тёмная; язык как в системе, русский, English — применяется после перезапуска; приватный режим), Подключение (запускать при входе, подключаться при запуске, «Продвинутое решение CAPTCHA» — недоступно при ручной капче у активного сервера), Служба (состояние, версия, «Переустановить», «Удалить»), Отладка (подробные логи; экран отладки: версии приложения, ядра и движка, состояние ядра, команда запуска с редактированием секретов), Сброс («Сбросить все настройки» с подтверждением: отключение, удаление файлов данных, перезапуск).
- [ ] **Step 4: поведение.** `wasConnected` ставится в `true` при успешном подключении и в `false` при ручном отключении и при `failed`. При запуске `AutoConnect.shouldConnect` → `connect`. `SleepWatcher` передаёт длительность сна в `connection.systemDidWake`. Пинг на Главной: измеряется при переходе в `connected` и по клику, «— мс» при `nil`.
- [ ] **Step 5: проверка.** Run `make app && make run`: переключение темы меняет окно сразу; после смены языка и перезапуска интерфейс на английском; «Сбросить» возвращает пустое состояние.
- [ ] **Step 6:** Commit `feat(app): settings, login item, auto-connect, ping and localization`.

---

### Task 17: Финальная проверка вживую и README

**Files:**
- Create: `README.md`
- Modify: `docs/proof-run.md` (раздел «Приёмка»)

- [ ] **Step 1:** Run `make test` — все тесты Go и Swift проходят. Run `make app`.
- [ ] **Step 2: приёмка на живом сервере** (участвует пользователь: ссылка, пароль администратора), результаты в `docs/proof-run.md`:
  - [ ] Установка службы из приложения по паролю; после неё `status` отвечает.
  - [ ] Импорт ссылки кликом по `freeturn://` и из QR.
  - [ ] Relay: подключение, счётчик потоков, скорость и трафик идут, пинг показан.
  - [ ] Direct: подключение без ссылки на звонок.
  - [ ] Правило по приложению и правило по домену работают; «Только выбранное через VPN» работает.
  - [ ] Ручная капча: окно появляется поверх остальных и закрывается само; в режиме «в браузере» открывается браузер.
  - [ ] Правило по приложению (не проверено на пробе): `nscurl` идёт напрямую, `curl` — через VPN.
  - [ ] Смена Wi-Fi и сон на 2 минуты: подключение восстанавливается без ручных действий.
  - [ ] `kill -9` приложения: интернет не пропадает, utun исчезает за ≤ 6 с.
  - [ ] Приватный режим: в логах и в интерфейсе нет IP, ключей и ссылки на звонок.
  - [ ] Выход через строку меню отключает VPN.
- [ ] **Step 3:** `README.md`: что это, требования (macOS 14+, Apple Silicon, Go 1.26, Command Line Tools), сборка (`git submodule update --init`, `make app`), установка службы, известные ограничения из спеки, лицензия.
- [ ] **Step 4:** Commit `docs: README and acceptance run`.
