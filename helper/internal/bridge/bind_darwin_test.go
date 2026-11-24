package bridge

import (
	"net"
	"testing"

	"golang.org/x/sys/unix"
)

func udpSocket(t *testing.T, family int) int {
	t.Helper()
	fd, err := unix.Socket(family, unix.SOCK_DGRAM, 0)
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
	fd := udpSocket(t, unix.AF_INET)
	setInterfaces(lo.Index, 0)
	t.Cleanup(func() { setInterfaces(0, 0) })
	if !bindToInterface(fd) {
		t.Fatal("bindToInterface = false")
	}
	got, err := unix.GetsockoptInt(fd, unix.IPPROTO_IP, unix.IP_BOUND_IF)
	if err != nil || got != lo.Index {
		t.Fatalf("IP_BOUND_IF = %d, %v; want %d", got, err, lo.Index)
	}
}

func TestBindIPv6(t *testing.T) {
	lo, err := net.InterfaceByName("lo0")
	if err != nil {
		t.Fatal(err)
	}
	fd := udpSocket(t, unix.AF_INET6)
	setInterfaces(0, lo.Index)
	t.Cleanup(func() { setInterfaces(0, 0) })
	if !bindToInterface(fd) {
		t.Fatal("bindToInterface = false")
	}
	got, err := unix.GetsockoptInt(fd, unix.IPPROTO_IPV6, unix.IPV6_BOUND_IF)
	if err != nil || got != lo.Index {
		t.Fatalf("IPV6_BOUND_IF = %d, %v; want %d", got, err, lo.Index)
	}
}

func TestBindZeroIsNoop(t *testing.T) {
	fd := udpSocket(t, unix.AF_INET)
	setInterfaces(0, 0)
	if !bindToInterface(fd) {
		t.Fatal("bindToInterface(0) = false")
	}
	got, _ := unix.GetsockoptInt(fd, unix.IPPROTO_IP, unix.IP_BOUND_IF)
	if got != 0 {
		t.Fatalf("IP_BOUND_IF = %d, want 0", got)
	}
}
