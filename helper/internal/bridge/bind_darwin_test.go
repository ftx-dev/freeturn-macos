package bridge

import (
	"net"
	"testing"

	"golang.org/x/sys/unix"
)

func udp4Socket(t *testing.T) int {
	t.Helper()
	fd, err := unix.Socket(unix.AF_INET, unix.SOCK_DGRAM, 0)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { unix.Close(fd) })
	return fd
}

func TestBindIPv4(t *testing.T) {
	lo, err := net.InterfaceByName("lo0")
	if err != nil {
		t.Fatal(err)
	}
	fd := udp4Socket(t)
	if !bindToInterface(fd, lo.Index) {
		t.Fatal("bindToInterface = false")
	}
	got, err := unix.GetsockoptInt(fd, unix.IPPROTO_IP, unix.IP_BOUND_IF)
	if err != nil || got != lo.Index {
		t.Fatalf("IP_BOUND_IF = %d, %v; want %d", got, err, lo.Index)
	}
}

func TestBindZeroIsNoop(t *testing.T) {
	fd := udp4Socket(t)
	if !bindToInterface(fd, 0) {
		t.Fatal("bindToInterface(0) = false")
	}
	got, _ := unix.GetsockoptInt(fd, unix.IPPROTO_IP, unix.IP_BOUND_IF)
	if got != 0 {
		t.Fatalf("IP_BOUND_IF = %d, want 0", got)
	}
}
