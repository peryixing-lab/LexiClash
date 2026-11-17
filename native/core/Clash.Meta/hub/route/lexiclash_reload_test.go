package route

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"testing"
	"time"

	C "github.com/metacubex/mihomo/constant"
)

func TestLexiClashLiveChainChangeOverridesCachedExit(t *testing.T) {
	oldHome := C.Path.HomeDir()
	C.SetHomeDir(t.TempDir())
	t.Cleanup(func() { CloseServers(); C.SetHomeDir(oldHome) })
	ReCreateServer(&Config{Addr: "127.0.0.1:0", Secret: "chain-test"})
	result := ControllerListenResult()
	if !strings.HasPrefix(result, "listening at ") {
		t.Fatal(result)
	}
	base := "http://" + strings.TrimPrefix(result, "listening at ")
	client := &http.Client{Timeout: 3 * time.Second}
	defer client.CloseIdleConnections()
	request := func(method, path string, body any, want int) []byte {
		t.Helper()
		data, _ := json.Marshal(body)
		req, err := http.NewRequest(method, base+path, bytes.NewReader(data))
		if err != nil {
			t.Fatal(err)
		}
		req.Header.Set("Authorization", "Bearer chain-test")
		req.Header.Set("Content-Type", "application/json")
		resp, err := client.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		defer resp.Body.Close()
		reply, _ := io.ReadAll(resp.Body)
		if resp.StatusCode != want {
			t.Fatalf("%s %s: %d %s", method, path, resp.StatusCode, reply)
		}
		return reply
	}
	profile := func(entry, exit string) string {
		// Selectors were previously restored from cache after app selections,
		// selecting B again when a live change had moved the exit to A.
		return fmt.Sprintf(`mixed-port: 7890
proxies:
  - {name: A, type: http, server: 127.0.0.1, port: 18001%s}
  - {name: B, type: http, server: 127.0.0.1, port: 18002%s}
  - {name: C, type: http, server: 127.0.0.1, port: 18003}
proxy-groups:
  - {name: Main, type: select, proxies: [A, B, C, DIRECT]}
profile: {store-selected: true}
rules: ["MATCH,Main"]
lexiclash: {version: 1, mode: rule, dnsProxy: %s, enhancedMode: fake-ip, selections: {Main: %s}}
`, func() string {
			if exit == "A" {
				return ", dialer-proxy: " + entry
			}
			return ""
		}(),
			func() string {
				if exit == "B" {
					return ", dialer-proxy: " + entry
				}
				return ""
			}(), exit, exit)
	}
	request("PUT", "/configs?force=true", map[string]string{"payload": profile("A", "B")}, 204)
	request("PUT", "/proxies/Main", map[string]string{"name": "B"}, 204)
	request("PUT", "/configs?force=true", map[string]string{"payload": profile("C", "A")}, 204)
	var selected struct {
		Now string `json:"now"`
	}
	if err := json.Unmarshal(request("GET", "/proxies/Main", nil, 200), &selected); err != nil {
		t.Fatal(err)
	}
	if selected.Now != "A" {
		t.Fatalf("live chain selected cached exit %q instead of A", selected.Now)
	}
	request("PUT", "/configs?force=true", map[string]string{"payload": "proxies: [invalid"}, 400)
	if err := json.Unmarshal(request("GET", "/proxies/Main", nil, 200), &selected); err != nil {
		t.Fatal(err)
	}
	if selected.Now != "A" {
		t.Fatal("a rejected chain update replaced the applied chain")
	}
}
