import Foundation
import Testing
@testable import FreeTurnKit

@Test func formatsBytesRussian() {
    #expect(Formatters.bytes(0) == "0 Б")
    #expect(Formatters.bytes(500) == "500 Б")
    #expect(Formatters.bytes(1536) == "1,5 КБ")
    #expect(Formatters.bytes(1_395_864_371) == "1,3 ГБ")
    #expect(Formatters.bytes(250 * 1024 * 1024) == "250 МБ")
    #expect(Formatters.bytes(-5) == "0 Б")
}

@Test func formatsBytesEnglish() {
    #expect(Formatters.bytes(1536, style: .en) == "1.5 KB")
    #expect(Formatters.rate(4_404_019, style: .en) == "4.2 MB/s")
}

@Test func formatsRate() {
    #expect(Formatters.rate(4_404_019) == "4,2 МБ/с")
    #expect(Formatters.rate(0) == "0 Б/с")
}

@Test func formatsDuration() {
    #expect(Formatters.duration(0) == "00:00")
    #expect(Formatters.duration(134) == "02:14")
    #expect(Formatters.duration(3725) == "1:02:05")
    #expect(Formatters.duration(90_000) == "25:00:00")
    #expect(Formatters.duration(-3) == "00:00")
}

// Путь к приложению попадает в команду с правами администратора: кавычки и пробелы
// в нём не должны ни ломать команду, ни дописывать к ней свою.
@Test func adminScriptQuotesHostilePaths() {
    let dir = #"/Users/x/My Apps/Free'Turn "v2".app/Contents/Resources/daemon"#
    let script = AdminScript.install(daemonDir: dir, uid: 501)
    #expect(script == #"do shell script "'/Users/x/My Apps/Free'\\''Turn \"v2\".app/Contents/Resources/daemon/install-daemon.sh' '/Users/x/My Apps/Free'\\''Turn \"v2\".app/Contents/Resources/daemon' 501" with administrator privileges"#)
}

@Test func adminScriptPlainPath() {
    #expect(AdminScript.install(daemonDir: "/Applications/FreeTurn.app/Contents/Resources/daemon", uid: 501)
        == #"do shell script "'/Applications/FreeTurn.app/Contents/Resources/daemon/install-daemon.sh' '/Applications/FreeTurn.app/Contents/Resources/daemon' 501" with administrator privileges"#)
    #expect(AdminScript.uninstall(daemonDir: "/A/daemon")
        == #"do shell script "'/A/daemon/uninstall-daemon.sh'" with administrator privileges"#)
}
