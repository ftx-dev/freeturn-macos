package bridge

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"strings"
	"testing"
	"time"

	"github.com/pion/dtls/v3"
	"github.com/pion/dtls/v3/pkg/crypto/selfsign"
	"github.com/samosvalishe/free-turn-proxy/mobile"
)

type harness struct {
	t    *testing.T
	in   *io.PipeWriter
	evs  chan map[string]any
	done chan error
}

func start(t *testing.T) *harness {
	t.Helper()
	inR, inW := io.Pipe()
	outR, outW := io.Pipe()
	h := &harness{t: t, in: inW, evs: make(chan map[string]any, 256), done: make(chan error, 1)}
	go func() { h.done <- Run(inR, outW, t.TempDir()); outW.Close() }()
	go func() {
		sc := bufio.NewScanner(outR)
		sc.Buffer(make([]byte, 1<<20), 1<<20)
		for sc.Scan() {
			var m map[string]any
			if err := json.Unmarshal(sc.Bytes(), &m); err != nil {
				t.Errorf("not JSON: %q", sc.Text())
				continue
			}
			h.evs <- m
		}
		close(h.evs)
	}()
	t.Cleanup(func() { inW.Close(); <-h.done })
	return h
}

func (h *harness) send(v any) {
	h.t.Helper()
	b, _ := json.Marshal(v)
	if _, err := h.in.Write(append(b, '\n')); err != nil {
		h.t.Fatal(err)
	}
}

// wait возвращает первое событие, для которого match истинно.
func (h *harness) wait(what string, match func(map[string]any) bool) map[string]any {
	h.t.Helper()
	deadline := time.After(10 * time.Second)
	for {
		select {
		case ev, ok := <-h.evs:
			if !ok {
				h.t.Fatalf("stream closed while waiting for %s", what)
			}
			if match(ev) {
				return ev
			}
		case <-deadline:
			h.t.Fatalf("timeout waiting for %s", what)
		}
	}
}

func ev(name string) func(map[string]any) bool {
	return func(m map[string]any) bool { return m["ev"] == name }
}

func state(s string) func(map[string]any) bool {
	return func(m map[string]any) bool { return m["ev"] == "state" && m["state"] == s }
}

// directConfig - валидный конфиг ядра без сети: direct на закрытый локальный порт.
func directConfig(t *testing.T, peer string) string {
	t.Helper()
	pc, err := net.ListenPacket("udp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	port := pc.LocalAddr().(*net.UDPAddr).Port
	pc.Close()

	var cfg map[string]any
	if err := json.Unmarshal([]byte(mobile.DefaultConfigJSON()), &cfg); err != nil {
		t.Fatal(err)
	}
	cfg["peer"] = peer
	cfg["provider"] = "direct"
	cfg["clientId"] = "0123456789abcdef0123456789abcdef"
	cfg["proxy"].(map[string]any)["listen"] = fmt.Sprintf("127.0.0.1:%d", port)
	b, _ := json.Marshal(cfg)
	return string(b)
}

func TestHello(t *testing.T) {
	h := start(t)
	first := <-h.evs
	if first["ev"] != "hello" || first["version"] == "" {
		t.Fatalf("first event = %v", first)
	}
}

func TestStartBadConfig(t *testing.T) {
	h := start(t)
	h.send(map[string]any{"cmd": "start", "config": "{}"})
	e := h.wait("start error", ev("error"))
	if e["cmd"] != "start" || e["err"] == "" {
		t.Fatalf("error event = %v", e)
	}
}

func TestStartStopDirect(t *testing.T) {
	h := start(t)
	h.send(map[string]any{"cmd": "start", "config": directConfig(t, "127.0.0.1:1"), "ifIndex": 0})
	h.wait("connecting", state("connecting"))
	h.send(map[string]any{"cmd": "stop"})
	h.wait("idle", state("idle"))
}

func TestConnectDirectToIPv6Server(t *testing.T) {
	lo, err := net.InterfaceByName("lo0")
	if err != nil {
		t.Fatal(err)
	}
	cert, err := selfsign.GenerateSelfSigned()
	if err != nil {
		t.Fatal(err)
	}
	listener, err := dtls.ListenWithOptions("udp6", &net.UDPAddr{IP: net.IPv6loopback},
		dtls.WithCertificates(cert),
		dtls.WithExtendedMasterSecret(dtls.RequireExtendedMasterSecret),
		dtls.WithCipherSuites(dtls.TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256))
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	go func() {
		conn, err := listener.Accept()
		if err != nil {
			return
		}
		defer conn.Close()
		var clientID [258]byte
		if _, err := conn.Read(clientID[:]); err != nil {
			t.Errorf("read client ID over DTLS: %v", err)
			return
		}
		// Сервер подтверждает получение Client ID одним байтом ACK.
		if _, err := conn.Write([]byte{0x06}); err != nil {
			t.Errorf("acknowledge client ID: %v", err)
			return
		}
		<-t.Context().Done()
	}()

	h := start(t)
	h.send(map[string]any{"cmd": "start", "config": directConfig(t, listener.Addr().String()), "ifIndex6": lo.Index})
	h.wait("connected to the IPv6 endpoint", state("connected"))
}

func TestEOFExits(t *testing.T) {
	h := start(t)
	h.send(map[string]any{"cmd": "start", "config": directConfig(t, "127.0.0.1:1"), "ifIndex": 0})
	h.wait("connecting", state("connecting"))
	h.in.Close()
	select {
	case err := <-h.done:
		h.done <- err
		if err != nil {
			t.Fatalf("Run = %v", err)
		}
	case <-time.After(6 * time.Second):
		t.Fatal("Run did not return after stdin EOF")
	}
	if s := mobile.GetState().State; s != mobile.StateIdle {
		t.Fatalf("core state after EOF = %q", s)
	}
}

func TestArgs(t *testing.T) {
	h := start(t)
	h.send(map[string]any{"cmd": "args", "config": directConfig(t, "127.0.0.1:1")})
	e := h.wait("args", ev("args"))
	if !strings.Contains(e["args"].(string), "-provider direct") {
		t.Fatalf("args = %v", e["args"])
	}
}
