package main

import (
	"net"
	"net/netip"
	"strings"
)

// Only outbound sockets need the physical network. In particular, both TUN
// subnets must keep normal routing for the system stack's local TCP forwarder.
func needsPhysicalBinding(network, address string) bool {
	host, _, err := net.SplitHostPort(address)
	if err != nil {
		return true
	}
	ip, err := netip.ParseAddr(host)
	if err != nil {
		return true
	}
	if ip.IsLoopback() || ip.IsLinkLocalUnicast() {
		return false
	}
	if ip.IsUnspecified() {
		return strings.HasPrefix(network, "udp")
	}
	if netip.MustParsePrefix("172.19.0.0/30").Contains(ip) || netip.MustParsePrefix("fdfe:dcba:9876::/126").Contains(ip) {
		return false
	}
	return true
}
