import Foundation
import Testing
@testable import FreeTurnKit

let plainWG = """
[Interface]
PrivateKey = cHJpdmF0ZWtleXByaXZhdGVrZXlwcml2YXRla2V5MDA=
Address = 10.13.13.2/32
DNS = 1.1.1.1, 8.8.8.8
MTU = 1420

[Peer]
PublicKey = cHVibGlja2V5cHVibGlja2V5cHVibGlja2V5cHViMDA=
PresharedKey = cHNrcHNrcHNrcHNrcHNrcHNrcHNrcHNrcHNrcHNrMDA=
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = 1.2.3.4:51820
PersistentKeepalive = 25
"""

@Test func wgPlainWireGuard() throws {
    let c = try WGConfig.parse(plainWG)
    #expect(!c.isAmnezia)
    #expect(c.privateKey == "cHJpdmF0ZWtleXByaXZhdGVrZXlwcml2YXRla2V5MDA=")
    #expect(c.addresses == ["10.13.13.2/32"])
    #expect(c.dns == ["1.1.1.1", "8.8.8.8"])
    #expect(c.peers.count == 1)
    #expect(c.peers[0].publicKey == "cHVibGlja2V5cHVibGlja2V5cHVibGlja2V5cHViMDA=")
    #expect(c.peers[0].presharedKey == "cHNrcHNrcHNrcHNrcHNrcHNrcHNrcHNrcHNrcHNrMDA=")
    #expect(c.peers[0].allowedIPs == ["0.0.0.0/0", "::/0"])
    #expect(c.peers[0].persistentKeepalive == 25)
}

@Test func wgAmneziaKeysCollected() throws {
    let c = try WGConfig.parse("""
    [Interface]
    PrivateKey = a
    Address = 10.0.0.2/32
    Jc = 4
    Jmin = 40
    H1 = 12345
    I1 = <b 0xc7000000010>
    HeaderProtectionKey = abc=

    [Peer]
    PublicKey = b
    AllowedIPs = 0.0.0.0/0
    """)
    #expect(c.isAmnezia)
    #expect(c.amnezia["jc"] == "4")
    #expect(c.amnezia["jmin"] == "40")
    #expect(c.amnezia["h1"] == "12345")
    #expect(c.amnezia["i1"] == "<b 0xc7000000010>")
    #expect(c.amnezia["headerprotectionkey"] == "abc=")
    #expect(c.peers[0].presharedKey == nil)
    #expect(c.peers[0].persistentKeepalive == nil)
}

// Конфиги копируют из панелей и мессенджеров: CRLF, комментарии, чужой регистр, лишние пробелы.
@Test func wgMessyRealWorldInput() throws {
    let text = "# сверху\r\n[interface]\r\n; ещё коммент\r\nprivatekey=abc\r\nADDRESS = 10.0.0.2/32 , fd00::2/128  # хвост\r\n\r\n[PEER]\r\nPublicKey   =   pk  ; хвост\r\nallowedips=0.0.0.0/0\r\n"
    let c = try WGConfig.parse(text)
    #expect(c.privateKey == "abc")
    #expect(c.addresses == ["10.0.0.2/32", "fd00::2/128"])
    #expect(c.peers[0].publicKey == "pk")
    #expect(c.peers[0].allowedIPs == ["0.0.0.0/0"])
}

@Test func wgBase64ValueWithEqualsKept() throws {
    let c = try WGConfig.parse("[Interface]\nPrivateKey = abc=\nAddress=10.0.0.2\n[Peer]\nPublicKey = de==\n")
    #expect(c.privateKey == "abc=")
    #expect(c.peers[0].publicKey == "de==")
}

@Test func wgTwoPeers() throws {
    let c = try WGConfig.parse("[Interface]\nPrivateKey=a\nAddress=10.0.0.2\n[Peer]\nPublicKey=p1\nAllowedIPs=10.0.0.0/8\n[Peer]\nPublicKey=p2\nAllowedIPs=192.168.0.0/16\n")
    #expect(c.peers.map(\.publicKey) == ["p1", "p2"])
    #expect(c.peers[1].allowedIPs == ["192.168.0.0/16"])
}

@Test func wgErrors() {
    #expect(throws: WGConfigError.missingInterface) { try WGConfig.parse("[Peer]\nPublicKey=p\n") }
    #expect(throws: WGConfigError.missingInterface) { try WGConfig.parse("") }
    #expect(throws: WGConfigError.missingPrivateKey) { try WGConfig.parse("[Interface]\nAddress=10.0.0.2\n[Peer]\nPublicKey=p\n") }
    #expect(throws: WGConfigError.missingAddress) { try WGConfig.parse("[Interface]\nPrivateKey=a\n[Peer]\nPublicKey=p\n") }
    #expect(throws: WGConfigError.missingPeer) { try WGConfig.parse("[Interface]\nPrivateKey=a\nAddress=10.0.0.2\n") }
    #expect(throws: WGConfigError.missingPublicKey(peer: 1)) {
        try WGConfig.parse("[Interface]\nPrivateKey=a\nAddress=10.0.0.2\n[Peer]\nPublicKey=p\n[Peer]\nAllowedIPs=0.0.0.0/0\n")
    }
}
