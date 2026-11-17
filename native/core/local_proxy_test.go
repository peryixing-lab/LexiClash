package main

import (
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strconv"
	"testing"
	"time"

	"github.com/metacubex/mihomo/hub/executor"
	"github.com/metacubex/mihomo/listener"
)

func TestLocalProxyForwardsWithoutSystemTun(t *testing.T) {
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) { _, _ = io.WriteString(w, "local-proxy-ok") }))
	defer upstream.Close()
	portReservation, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	port := portReservation.Addr().(*net.TCPAddr).Port
	_ = portReservation.Close()
	cfg, err := executor.ParseWithBytes([]byte(`mode: direct
allow-lan: false
bind-address: 127.0.0.1
rules: ["MATCH,DIRECT"]
`))
	if err != nil {
		t.Fatal(err)
	}
	cfg.General.MixedPort = port
	withCurrentConfig(t, cfg)
	wasRunning := isRunning.Load()
	t.Cleanup(func() { handleStopListener(); isRunning.Store(wasRunning) })
	executor.ApplyConfig(cfg, true)
	if err := startLocalProxyListeners(); err != nil {
		t.Fatal(err)
	}
	if listener.GetTunConf().Enable {
		t.Fatal("local proxy unexpectedly enabled TUN")
	}
	proxyURL, _ := url.Parse("http://" + net.JoinHostPort("127.0.0.1", strconv.Itoa(port)))
	transport := &http.Transport{Proxy: http.ProxyURL(proxyURL)}
	defer transport.CloseIdleConnections()
	client := &http.Client{Transport: transport, Timeout: 2 * time.Second}
	response, err := client.Get(upstream.URL)
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	body, _ := io.ReadAll(response.Body)
	if string(body) != "local-proxy-ok" {
		t.Fatalf("unexpected response: %q", body)
	}
}
