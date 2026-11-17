package tunnel

import (
	"encoding/binary"
	"sync/atomic"

	C "github.com/metacubex/mihomo/constant"
)

type PrivacyPolicy struct {
	Rules          []C.Rule
	BlockSTUN      bool
	BlockIPv6      bool
	BlockDirectDNS bool
}

var privacyPolicy atomic.Pointer[PrivacyPolicy]

func UpdatePrivacyPolicy(policy *PrivacyPolicy) { privacyPolicy.Store(policy) }

func privacyRejectsDNSProxy(proxy C.ProxyAdapter, metadata *C.Metadata) bool {
	p := privacyPolicy.Load()
	if p == nil || !p.BlockDirectDNS {
		return false
	}
	if proxy == nil {
		return true
	}
	for depth := 0; proxy != nil && depth < 16; depth++ {
		switch proxy.Type() {
		case C.Direct, C.Pass, C.PassRule, C.Compatible:
			return true
		}
		proxy = proxy.Unwrap(metadata, false)
	}
	return proxy != nil // Reject cycles rather than guessing an egress.
}

// STUN's fixed header identifies Binding requests on arbitrary UDP ports,
// including the Google STUN service on 19302. Check every packet, including NAT
// sessions established before a configuration reload.
func privacyBlocksPacket(metadata *C.Metadata, payload []byte) bool {
	p := privacyPolicy.Load()
	if p == nil {
		return false
	}
	if p.BlockIPv6 && metadata.DstIP.Is6() && !metadata.DstIP.Is4In6() {
		return true
	}
	return p.BlockSTUN && len(payload) >= 20 && payload[0]&0xc0 == 0 &&
		binary.BigEndian.Uint32(payload[4:8]) == 0x2112a442 &&
		int(binary.BigEndian.Uint16(payload[2:4]))+20 <= len(payload)
}

func privacyMatch(metadata *C.Metadata, helper C.RuleMatchHelper) C.Rule {
	p := privacyPolicy.Load()
	if p == nil {
		return nil
	}
	for _, rule := range p.Rules {
		if matched, _ := rule.Match(metadata, helper); matched {
			return rule
		}
	}
	return nil
}
