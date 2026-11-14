import Foundation
import Testing
@testable import FreeTurnKit

@Test func decodesEveryCoreEvent() {
    #expect(CoreEvent.decode(line: #"{"ev":"hello","version":"v4.1.5","streams":0}"#) == .hello(version: "v4.1.5"))
    #expect(CoreEvent.decode(line: #"{"ev":"state","state":"connected","streams":3,"total":12,"err":""}"#)
        == .state(phase: .connected, streams: 3, total: 12, err: ""))
    #expect(CoreEvent.decode(line: #"{"ev":"state","state":"error","streams":0,"total":12,"err":"boom"}"#)
        == .state(phase: .error, streams: 0, total: 12, err: "boom"))
    #expect(CoreEvent.decode(line: #"{"ev":"log","level":"warn","msg":"m","ts":1700000000500}"#)
        == .log(level: .warn, msg: "m", date: Date(timeIntervalSince1970: 1_700_000_000.5)))
    #expect(CoreEvent.decode(line: #"{"ev":"stats","tx":10,"rx":20,"txRate":1,"rxRate":2}"#)
        == .stats(TrafficStats(tx: 10, rx: 20, txRate: 1, rxRate: 2)))
    #expect(CoreEvent.decode(line: #"{"ev":"args","args":"-peer x"}"#) == .args("-peer x"))
    #expect(CoreEvent.decode(line: #"{"ev":"error","cmd":"start","err":"bad"}"#) == .error(cmd: "start", err: "bad"))
}

// Go пишет & в JSON escape-последовательностью: адрес капчи обязан прийти раскодированным.
@Test func captchaUrlIsJsonDecoded() {
    let bs = "\\"
    let line = #"{"ev":"captcha","url":"http://localhost:8765/c?a=1"# + bs + #"u0026b=2","manual":true}"#
    #expect(CoreEvent.decode(line: line) == .captcha(url: "http://localhost:8765/c?a=1&b=2", manual: true))
    #expect(CoreEvent.decode(line: #"{"ev":"captcha","url":"","manual":false}"#) == .captcha(url: "", manual: false))
}

@Test func garbageLinesDecodeToNil() {
    #expect(CoreEvent.decode(line: "") == nil)
    #expect(CoreEvent.decode(line: "panic: something") == nil)
    #expect(CoreEvent.decode(line: #"{"ev":"mystery"}"#) == nil)
    #expect(CoreEvent.decode(line: #"{"ev":"state","state":"weird"}"#) == nil)
    #expect(CoreEvent.decode(line: "[1,2]") == nil)
}

private func parsed(_ command: CoreCommand) -> [String: Any] {
    let line = command.encoded()
    #expect(!line.contains("\n"))
    return try! JSONSerialization.jsonObject(with: Data(line.utf8)) as! [String: Any]
}

@Test func encodesCommands() {
    let start = parsed(.start(config: #"{"a":1}"#, ifIndex: 14))
    #expect(start["cmd"] as? String == "start")
    #expect(start["config"] as? String == #"{"a":1}"#)
    #expect(start["ifIndex"] as? Int == 14)
    #expect(parsed(.stop)["cmd"] as? String == "stop")
    #expect(parsed(.wake)["cmd"] as? String == "wake")
    let re = parsed(.reconnect(ifIndex: 7, dns: ["1.1.1.1", "8.8.8.8"]))
    #expect(re["cmd"] as? String == "reconnect")
    #expect(re["ifIndex"] as? Int == 7)
    #expect(re["dns"] as? String == "1.1.1.1,8.8.8.8")
    #expect(parsed(.args(config: "{}"))["cmd"] as? String == "args")
}
