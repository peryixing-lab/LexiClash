package config

import (
	"strings"
	"testing"

	C "github.com/metacubex/mihomo/constant"
	T "github.com/metacubex/mihomo/tunnel"
)

func privacyFixture() *RawConfig {
	raw := DefaultRawConfig()
	raw.Proxy = []map[string]any{{"name": "Exit, node", "type": "http", "server": "127.0.0.1", "port": 8080}}
	raw.ProxyGroup = []map[string]any{{"name": "Proxy", "type": "select", "proxies": []string{"DIRECT", "Exit, node"}}}
	raw.Rule = []string{"MATCH,Proxy"}
	raw.DNS.FallbackFilter.GeoIP = false
	raw.LexiClash = &RawLexiClash{Version: 1, Mode: "global", DNSProxy: "Exit, node", BlockSTUN: true,
		EnhancedMode: "fake-ip", Sniffer: true, ForceDNSMapping: true, ParsePureIP: true,
		Nameservers: []string{"https://1.1.1.1/dns-query#DIRECT&ecs=192.0.2.0/24"},
		Fallback:    []string{"tls://1.0.0.1:853"}, Rules: []string{"DST-PORT,3478,REJECT"},
		Selections: map[string]string{"Proxy": "Exit, node", "GLOBAL": "Exit, node"}}
	return raw
}

func TestLexiClashPolicyCompilesSettingsAndSelectionsBeforeApply(t *testing.T) {
	raw := privacyFixture()
	cfg, err := ParseRawConfig(raw)
	if err != nil {
		t.Fatal(err)
	}
	if cfg.General.Mode != T.Global || cfg.General.IPv6 || cfg.DNS.IPv6 || cfg.DNS.EnhancedMode != C.DNSFakeIP {
		t.Fatal("runtime mode/DNS/IPv6 settings were not applied")
	}
	for _, ns := range append(cfg.DNS.NameServer, cfg.DNS.Fallback...) {
		if ns.ProxyName != "__LEXICLASH_DNS__" || (ns.Net != "https" && ns.Net != "tls") || len(ns.Params) != 0 {
			t.Fatalf("DNS was not pinned and stripped of profile/ECS overrides: %+v", ns)
		}
	}
	if leaf := cfg.Proxies["__LEXICLASH_DNS__"].Unwrap(&C.Metadata{}, false); leaf == nil || leaf.Name() != "Exit, node" {
		t.Fatal("DNS selector was not pinned to the requested exit")
	}
	if cfg.Privacy == nil || !cfg.Privacy.BlockSTUN || !cfg.Privacy.BlockIPv6 || !cfg.Privacy.BlockDirectDNS || len(cfg.Privacy.Rules) != 1 {
		t.Fatal("global mode lost its independent privacy guard")
	}
	if len(cfg.Rules) != 2 || !cfg.Sniffer.Enable || len(cfg.Sniffer.Sniffers) == 0 {
		t.Fatal("overrides or sniffer settings were not compiled")
	}
	for _, name := range []string{"Proxy", "GLOBAL"} {
		if selected := cfg.Proxies[name].Unwrap(&C.Metadata{}, false); selected == nil || selected.Name() != "Exit, node" {
			t.Fatal("selection was not applied before publishing the new proxy map")
		}
	}
	if len(raw.Rule) != 1 || raw.Mode != T.Rule || raw.DNS.NameServer[0] != "https://doh.pub/dns-query" {
		t.Fatal("compiling policy mutated the subscription")
	}
	again, err := ParseRawConfig(raw)
	if err != nil || len(again.Rules) != 2 {
		t.Fatal("recompilation duplicated rules", err)
	}
}

func TestLexiClashDNSNamesCannotBecomeFragmentOptions(t *testing.T) {
	raw := privacyFixture()
	name := "Exit & region=HK %20"
	raw.Proxy[0]["name"] = name
	raw.LexiClash.DNSProxy = name
	raw.ProxyGroup = append(raw.ProxyGroup, map[string]any{"name": "__LEXICLASH_DNS__", "type": "select", "proxies": []string{"DIRECT"}})
	compiled, err := applyLexiClashPolicy(raw)
	if err != nil {
		t.Fatal(err)
	}
	if compiled.DNS.NameServer[0] != "https://1.1.1.1/dns-query#__LEXICLASH_DNS___" {
		t.Fatal("unsafe fragment or group collision")
	}
	last := compiled.ProxyGroup[len(compiled.ProxyGroup)-1]
	if last["proxies"].([]string)[0] != name {
		t.Fatal("proxy name was changed")
	}
	if len(raw.ProxyGroup) != 2 {
		t.Fatal("subscription groups were mutated")
	}
}

func TestLexiClashUnknownAndProviderDNSNamesCannotCreateGlobalCycles(t *testing.T) {
	raw := privacyFixture()
	raw.LexiClash.DNSProxy = "provider-node"
	raw.LexiClash.Selections = map[string]string{}
	cfg, err := ParseRawConfig(raw)
	if err != nil {
		t.Fatal(err)
	}
	if cfg.DNS.NameServer[0].ProxyName != "GLOBAL" {
		t.Fatal("missing provider name should use GLOBAL safely")
	}
	raw.LexiClash.Selections["Proxy"] = "provider-node"
	compiled, err := applyLexiClashPolicy(raw)
	if err != nil {
		t.Fatal(err)
	}
	last := compiled.ProxyGroup[len(compiled.ProxyGroup)-1]
	if last["proxies"].([]string)[0] != "Proxy" {
		t.Fatal("provider selection did not use its owning group")
	}
}

func TestLexiClashPolicyRejectsUnsafeOrUnsupportedSettings(t *testing.T) {
	for _, mutate := range []func(*RawLexiClash){
		func(p *RawLexiClash) { p.Nameservers = []string{"223.5.5.5"} },
		func(p *RawLexiClash) { p.Nameservers = []string{"http://resolver.example/dns-query"} },
		func(p *RawLexiClash) { p.DNSProxy = "DIRECT" },
		func(p *RawLexiClash) { p.Version = 2 },
		func(p *RawLexiClash) { p.EnhancedMode = "invalid" },
	} {
		raw := privacyFixture()
		mutate(raw.LexiClash)
		if _, err := applyLexiClashPolicy(raw); err == nil {
			t.Fatal("unsafe settings were accepted")
		}
	}
	raw := privacyFixture()
	raw.LexiClash.Mode = "direct"
	compiled, err := applyLexiClashPolicy(raw)
	if err != nil || !strings.HasSuffix(compiled.DNS.NameServer[0], "#DIRECT") {
		t.Fatal("explicit direct mode failed", err)
	}
}

func TestLexiClashPolicyDisablesSubscriptionDNSPoliciesAndPlainBootstrap(t *testing.T) {
	raw := privacyFixture()
	raw.DNS.DirectNameServer = []string{"system"}
	raw.DNS.ProxyServerNameserver = []string{"223.5.5.5"}
	compiled, err := applyLexiClashPolicy(raw)
	if err != nil {
		t.Fatal(err)
	}
	if len(compiled.DNS.DirectNameServer) != 0 || compiled.DNS.NameServerPolicy != nil || compiled.DNS.ProxyServerNameserverPolicy != nil {
		t.Fatal("subscription DNS overrides escaped the app policy")
	}
	for _, server := range append(compiled.DNS.DefaultNameserver, compiled.DNS.ProxyServerNameserver...) {
		if !strings.HasPrefix(server, "https://") && !strings.HasPrefix(server, "tls://") {
			t.Fatal("unencrypted bootstrap")
		}
	}
	if compiled.Tun.Enable || compiled.AllowLan || compiled.BindAddress != "127.0.0.1" {
		t.Fatal("REST reload lost platform invariants")
	}
}
