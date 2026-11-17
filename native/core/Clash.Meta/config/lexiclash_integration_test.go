package config_test

// The upstream parser temporarily applies general settings via a go:linkname
// implementation in executor. Import it in the external test package to supply
// that implementation without creating a config -> executor import cycle.
import (
	"testing"

	"github.com/metacubex/mihomo/config"
	_ "github.com/metacubex/mihomo/hub/executor"
)

func TestLexiClashFlowPolicyUsesTheProductionYAMLParser(t *testing.T) {
	cfg, err := config.Parse([]byte(`mode: rule
proxies:
  - {name: Exit, type: http, server: 127.0.0.1, port: 8080}
rules: ["MATCH,REJECT"]
lexiclash: {version: 1, mode: global, dnsProxy: Exit, ipv6: false, blockStun: true, enhancedMode: fake-ip, nameservers: [https://1.1.1.1/dns-query], rules: ["DST-PORT,3478,REJECT"]}
`))
	if err != nil {
		t.Fatal(err)
	}
	if cfg.Privacy == nil || len(cfg.Privacy.Rules) != 1 || cfg.DNS.NameServer[0].ProxyName != "__LEXICLASH_DNS__" {
		t.Fatal("flow policy was not compiled by the production parser")
	}
}
