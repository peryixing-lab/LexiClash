package tunnel

import (
	"context"
	"encoding/binary"
	"net/netip"
	"strings"
	"testing"

	C "github.com/metacubex/mihomo/constant"
	R "github.com/metacubex/mihomo/rules"
)

type privacyTestProxy struct {
	C.Proxy
	name  string
	kind  C.AdapterType
	udp   bool
	child C.Proxy
}

func (p *privacyTestProxy) Name() string                     { return p.name }
func (p *privacyTestProxy) Type() C.AdapterType              { return p.kind }
func (p *privacyTestProxy) SupportUDP() bool                 { return p.udp }
func (p *privacyTestProxy) Unwrap(*C.Metadata, bool) C.Proxy { return p.child }

func withPrivacy(t *testing.T, p *PrivacyPolicy) {
	t.Helper()
	previous := privacyPolicy.Load()
	UpdatePrivacyPolicy(p)
	t.Cleanup(func() { UpdatePrivacyPolicy(previous) })
}

func TestPrivacySTUNBlocksArbitraryPortsAndEstablishedSessions(t *testing.T) {
	withPrivacy(t, &PrivacyPolicy{BlockSTUN: true})
	packet := make([]byte, 20)
	packet[1] = 1
	binary.BigEndian.PutUint32(packet[4:8], 0x2112a442)
	metadata := &C.Metadata{NetWork: C.UDP, DstIP: netip.MustParseAddr("192.0.2.1")}
	for _, port := range []uint16{3478, 19302, 443, 54321} {
		metadata.DstPort = port
		if !privacyBlocksPacket(metadata, packet) {
			t.Fatalf("STUN escaped on port %d", port)
		}
	}
	for _, payload := range [][]byte{packet[:19], []byte("ordinary UDP payload"), {0xc0, 0, 0, 0, 0x21, 0x12, 0xa4, 0x42}} {
		if privacyBlocksPacket(metadata, payload) {
			t.Fatal("ordinary or truncated UDP was blocked as STUN")
		}
	}
	UpdatePrivacyPolicy(&PrivacyPolicy{})
	if privacyBlocksPacket(metadata, packet) {
		t.Fatal("turning protection off did not affect existing flows")
	}
}

func TestPrivacyIPv6AndIPv4MappedAddresses(t *testing.T) {
	withPrivacy(t, &PrivacyPolicy{BlockIPv6: true})
	for _, address := range []string{"2001:db8::1", "fdfe:dcba:9876::2"} {
		if !privacyBlocksPacket(&C.Metadata{DstIP: netip.MustParseAddr(address)}, nil) {
			t.Fatal("IPv6 escaped")
		}
	}
	if privacyBlocksPacket(&C.Metadata{DstIP: netip.MustParseAddr("::ffff:192.0.2.1")}, nil) {
		t.Fatal("IPv4 mapped address blocked")
	}
}

func TestPrivacyRejectRuleAppliesInGlobalMode(t *testing.T) {
	previousProxies, previousMode := proxies, mode
	t.Cleanup(func() { proxies, mode = previousProxies, previousMode })
	reject := &privacyTestProxy{name: "REJECT", kind: C.Reject, udp: true}
	proxies = map[string]C.Proxy{"REJECT": reject, "GLOBAL": &privacyTestProxy{name: "DIRECT", kind: C.Direct, udp: true}}
	mode = Global
	rule, err := R.ParseRule("DST-PORT", "3478", "REJECT", nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	withPrivacy(t, &PrivacyPolicy{Rules: []C.Rule{rule}})
	proxy, _, err := resolveMetadata(&C.Metadata{NetWork: C.TCP, DstIP: netip.MustParseAddr("192.0.2.1"), DstPort: 3478})
	if err != nil || proxy.Name() != "REJECT" {
		t.Fatal("global mode bypassed the reject guard", err)
	}
}

func TestUnsupportedUDPDoesNotFallThroughToDirect(t *testing.T) {
	previousProxies, previousRules := proxies, rules
	t.Cleanup(func() { proxies, rules = previousProxies, previousRules })
	proxies = map[string]C.Proxy{
		"REJECT":   &privacyTestProxy{name: "REJECT", kind: C.Reject, udp: true},
		"DIRECT":   &privacyTestProxy{name: "DIRECT", kind: C.Direct, udp: true},
		"TCP-only": &privacyTestProxy{name: "TCP-only", kind: C.Http},
	}
	first, _ := R.ParseRule("MATCH", "", "TCP-only", nil, nil)
	second, _ := R.ParseRule("MATCH", "", "DIRECT", nil, nil)
	rules = []C.Rule{first, second}
	metadata := &C.Metadata{NetWork: C.UDP, DstIP: netip.MustParseAddr("192.0.2.1"), DstPort: 19302}
	proxy, _, err := match(metadata, C.RuleMatchHelper{})
	if err != nil || proxy.Name() != "REJECT" {
		t.Fatal("unsupported UDP fell through to DIRECT", err)
	}
	metadata.NetWork = C.TCP
	proxy, _, err = match(metadata, C.RuleMatchHelper{})
	if err != nil || proxy.Name() != "TCP-only" {
		t.Fatal("TCP-only chains stopped accepting TCP", err)
	}
}

func TestDNSPolicyRefusesDirectAdapterBeforeOpeningSocket(t *testing.T) {
	withPrivacy(t, &PrivacyPolicy{BlockDirectDNS: true})
	dialer := NewDNSDialer(nil, &privacyTestProxy{name: "DIRECT", kind: C.Direct, udp: true}, "DIRECT")
	_, err := dialer.DialContext(context.Background(), "tcp", "192.0.2.1:443")
	if err == nil || !strings.Contains(err.Error(), "privacy policy") {
		t.Fatal("DNS dialer allowed direct egress", err)
	}
	group := &privacyTestProxy{name: "Group", kind: C.Selector, child: &privacyTestProxy{name: "DIRECT", kind: C.Direct}}
	if !privacyRejectsDNSProxy(group, &C.Metadata{}) {
		t.Fatal("nested group hid a direct DNS adapter")
	}
	missing := NewDNSDialer(nil, nil, "missing-dns-proxy")
	if _, err := missing.DialContext(context.Background(), "tcp", "192.0.2.1:443"); err == nil {
		t.Fatal("unknown DNS proxy fell back to a physical interface")
	}
}
