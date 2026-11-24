package bridge

import (
	"sync/atomic"

	"golang.org/x/sys/unix"
)

type interfaceIndexes struct {
	ipv4 int
	ipv6 int
}

var boundInterfaces atomic.Pointer[interfaceIndexes]

// setInterfaces привязывает сокеты к физическому интерфейсу их семейства.
func setInterfaces(ipv4, ipv6 int) {
	if ipv6 == 0 {
		ipv6 = ipv4
	}
	boundInterfaces.Store(&interfaceIndexes{ipv4: ipv4, ipv6: ipv6})
}

// bindToInterface уводит сокет мимо utun: привязанный сокет маршрутизируется
// через свой интерфейс, а не через default route туннеля (аналог VpnService.protect).
// Для сокетов, поддерживающих оба семейства, устанавливаем обе опции.
func bindToInterface(fd int) bool {
	indexes := boundInterfaces.Load()
	if indexes == nil || indexes.ipv4 == 0 && indexes.ipv6 == 0 {
		return true
	}
	err6 := unix.SetsockoptInt(fd, unix.IPPROTO_IPV6, unix.IPV6_BOUND_IF, indexes.ipv6)
	err4 := unix.SetsockoptInt(fd, unix.IPPROTO_IP, unix.IP_BOUND_IF, indexes.ipv4)
	return err4 == nil || err6 == nil
}
