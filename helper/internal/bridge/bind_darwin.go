package bridge

import (
	"sync/atomic"

	"golang.org/x/sys/unix"
)

// Индекс физического интерфейса; 0 - не привязывать.
var boundIf atomic.Int32

// SetInterface задаёт интерфейс, к которому привязываются исходящие сокеты ядра.
func SetInterface(ifIndex int) { boundIf.Store(int32(ifIndex)) }

// bindToInterface уводит сокет мимо utun: привязанный сокет маршрутизируется
// через свой интерфейс, а не через default route туннеля (аналог VpnService.protect).
// Семейство сокета здесь неизвестно, поэтому ставим обе опции - хватит одной.
func bindToInterface(fd int, ifIndex int) bool {
	if ifIndex == 0 {
		return true
	}
	err6 := unix.SetsockoptInt(fd, unix.IPPROTO_IPV6, unix.IPV6_BOUND_IF, ifIndex)
	err4 := unix.SetsockoptInt(fd, unix.IPPROTO_IP, unix.IP_BOUND_IF, ifIndex)
	return err4 == nil || err6 == nil
}
