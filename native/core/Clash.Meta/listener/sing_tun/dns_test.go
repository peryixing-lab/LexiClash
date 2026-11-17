package sing_tun

import (
	"net/netip"
	"testing"
)

func TestWildcardDNSHijackCoversTCPAndUDPDestinations(t *testing.T) {
	h := ListenerHandler{DnsAddrPorts: []netip.AddrPort{netip.MustParseAddrPort("0.0.0.0:53"), netip.MustParseAddrPort("[::]:53")}}
	for _, address := range []string{"172.19.0.2:53", "8.8.8.8:53", "223.5.5.5:53", "[2001:4860:4860::8888]:53"} {
		if !h.ShouldHijackDns(netip.MustParseAddrPort(address)) {
			t.Fatalf("hardcoded DNS escaped: %s", address)
		}
	}
	if h.ShouldHijackDns(netip.MustParseAddrPort("1.1.1.1:443")) {
		t.Fatal("HTTPS must not be mistaken for plaintext DNS")
	}
}
