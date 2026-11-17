package config

import (
	"fmt"
	"net/netip"
	"net/url"
	"strings"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/adapter/outboundgroup"
	C "github.com/metacubex/mihomo/constant"
	T "github.com/metacubex/mihomo/tunnel"
)

// App-owned settings are decoded by the same YAML parser on startup and REST
// reload. Subscription credentials and transport options are never rewritten.
type RawLexiClash struct {
	MixedPort       int               `yaml:"mixedPort" json:"mixedPort"`
	Version         int               `yaml:"version" json:"version"`
	Mode            string            `yaml:"mode" json:"mode"`
	DNSProxy        string            `yaml:"dnsProxy" json:"dnsProxy"`
	IPv6            bool              `yaml:"ipv6" json:"ipv6"`
	BlockSTUN       bool              `yaml:"blockStun" json:"blockStun"`
	Sniffer         bool              `yaml:"sniffer" json:"sniffer"`
	ForceDNSMapping bool              `yaml:"forceDnsMapping" json:"forceDnsMapping"`
	ParsePureIP     bool              `yaml:"parsePureIp" json:"parsePureIp"`
	EnhancedMode    string            `yaml:"enhancedMode" json:"enhancedMode"`
	Nameservers     []string          `yaml:"nameservers" json:"nameservers"`
	Fallback        []string          `yaml:"fallback" json:"fallback"`
	Rules           []string          `yaml:"rules" json:"rules"`
	Selections      map[string]string `yaml:"selections" json:"selections"`
}

// Restore app selections after persisted profile selections are loaded. Without
// this, a live chain change can silently select the previous chain's exit.
func ApplyLexiClashSelections(cfg *Config) {
	if cfg.LexiSelections != nil {
		selectLexiClashProxies(&RawLexiClash{Selections: cfg.LexiSelections}, cfg.Proxies)
	}
}

func selectLexiClashProxies(policy *RawLexiClash, proxies map[string]C.Proxy) {
	if policy == nil {
		return
	}
	for name, selected := range policy.Selections {
		proxy, ok := proxies[name].(*adapter.Proxy)
		if !ok {
			continue
		}
		selector, ok := proxy.ProxyAdapter.(outboundgroup.SelectAble)
		if ok {
			selector.ForceSet(selected)
		}
	}
}

func (p *RawLexiClash) rejectRules() []string {
	var rules []string
	for _, rule := range p.Rules {
		parts := strings.Split(rule, ",")
		last := strings.TrimSpace(parts[len(parts)-1])
		if last == "no-resolve" && len(parts) > 1 {
			last = strings.TrimSpace(parts[len(parts)-2])
		}
		if last == "REJECT" || last == "REJECT-DROP" {
			rules = append(rules, rule)
		}
	}
	return rules
}

func encryptedNameservers(servers []string, proxy string) ([]string, error) {
	result := make([]string, 0, len(servers))
	for _, server := range servers {
		u, err := url.Parse(strings.TrimSpace(server))
		if err != nil || u.Hostname() == "" || (u.Scheme != "https" && u.Scheme != "tls") {
			return nil, fmt.Errorf("隐私 DNS 仅支持 HTTPS/DoT 上游")
		}
		// Replace profile fragments, including ECS and direct/interface overrides.
		u.Fragment = proxy
		result = append(result, u.String())
	}
	return result, nil
}

func dnsProxyGroup(raw *RawConfig, target string) string {
	name := "__LEXICLASH_DNS__"
	for {
		found := false
		for _, node := range raw.Proxy {
			if node["name"] == name {
				found = true
			}
		}
		for _, group := range raw.ProxyGroup {
			if group["name"] == name {
				found = true
			}
		}
		if !found {
			break
		}
		name += "_"
	}
	raw.ProxyGroup = append(append([]map[string]any{}, raw.ProxyGroup...), map[string]any{
		"name": name, "type": "select", "proxies": []string{target},
	})
	return name
}

func applyLexiClashPolicy(source *RawConfig) (*RawConfig, error) {
	p := source.LexiClash
	if p == nil {
		return source, nil
	}
	if p.Version != 1 {
		return nil, fmt.Errorf("不支持的隐私配置版本 %d", p.Version)
	}
	raw := *source
	if p.MixedPort != 0 && (p.MixedPort < 1024 || p.MixedPort > 65535) {
		return nil, fmt.Errorf("无效的本地代理端口")
	}
	raw.MixedPort = p.MixedPort
	if raw.MixedPort == 0 {
		raw.MixedPort = 7890
	}
	switch p.Mode {
	case "rule":
		raw.Mode = T.Rule
	case "global":
		raw.Mode = T.Global
	case "direct":
		raw.Mode = T.Direct
	default:
		return nil, fmt.Errorf("无效的出站模式")
	}
	proxy := p.DNSProxy
	if raw.Mode == T.Direct {
		proxy = "DIRECT" // Explicit direct mode remains an intentional opt-out.
	} else if proxy == "" {
		proxy = "REJECT" // An empty profile must not bootstrap business DNS directly.
	} else {
		if proxy == "DIRECT" || proxy == "PASS" {
			return nil, fmt.Errorf("DNS 出口不能使用直连或无效节点名称")
		}
		// Provider nodes are owned by groups rather than the global proxy map.
		// GLOBAL resolves those names after provider initialization; the DNS
		// dialer checks the selected leaf and refuses DIRECT on every request.
		found := false
		for _, node := range raw.Proxy {
			if node["name"] == proxy {
				found = true
				break
			}
		}
		if !found {
			proxy = "GLOBAL"
			for _, group := range raw.ProxyGroup {
				name, _ := group["name"].(string)
				if name == p.DNSProxy || policySelection(p, name) == p.DNSProxy {
					proxy = name
					break
				}
			}
		}
		// DNS fragments reserve '&' and '='. A private single-member selector
		// supports arbitrary node names without changing the shared URL parser.
		// GLOBAL is synthesized after other groups and must not be a dependency
		// of a new group, which would create a GLOBAL -> DNS -> GLOBAL cycle.
		if proxy != "GLOBAL" {
			proxy = dnsProxyGroup(&raw, proxy)
		}
	}
	nameservers := p.Nameservers
	if len(nameservers) == 0 {
		nameservers = []string{"https://1.1.1.1/dns-query"}
	}
	var err error
	raw.DNS.NameServer, err = encryptedNameservers(nameservers, proxy)
	if err != nil {
		return nil, err
	}
	raw.DNS.Fallback, err = encryptedNameservers(p.Fallback, proxy)
	if err != nil {
		return nil, err
	}
	mode, ok := C.DNSModeMapping[p.EnhancedMode]
	if !ok {
		return nil, fmt.Errorf("无效的 DNS 增强模式")
	}
	raw.DNS.Enable = true
	raw.DNS.EnhancedMode = mode
	raw.DNS.IPv6 = p.IPv6
	raw.DNS.RespectRules = false // The explicit proxy fragment takes precedence.
	raw.DNS.PreferH3 = false
	raw.DNS.NameServerPolicy = nil
	raw.DNS.ProxyServerNameserverPolicy = nil
	raw.DNS.DirectNameServer = nil
	// Only proxy endpoints and resolver hostnames use this encrypted bootstrap.
	// No business query is allowed to fall back to it on proxy failure.
	raw.DNS.DefaultNameserver = []string{"tls://223.5.5.5:853", "https://1.1.1.1/dns-query"}
	raw.DNS.ProxyServerNameserver = append([]string{}, raw.DNS.DefaultNameserver...)
	raw.IPv6 = p.IPv6
	raw.Rule = append(append([]string{}, p.Rules...), source.Rule...)
	raw.Sniffer.Enable = p.Sniffer
	raw.Sniffer.ForceDnsMapping = p.ForceDNSMapping
	raw.Sniffer.ParsePureIp = p.ParsePureIP
	if p.Sniffer && len(raw.Sniffer.Sniff) == 0 && len(raw.Sniffer.Sniffing) == 0 {
		raw.Sniffer.Sniff = map[string]RawSniffingConfig{
			"TLS": {Ports: []string{"443"}}, "HTTP": {Ports: []string{"80", "8080-8880"}},
		}
	}
	// The OS owns the descriptor and both default routes; a second TUN must not
	// be created when the REST endpoint applies this configuration.
	raw.Tun.Enable = false
	raw.Tun.Inet6Address = []netip.Prefix{netip.MustParsePrefix("fdfe:dcba:9876::1/126")}
	raw.AllowLan = false
	raw.BindAddress = "127.0.0.1"
	raw.Listeners = nil
	return &raw, nil
}

func policySelection(policy *RawLexiClash, name string) string { return policy.Selections[name] }
