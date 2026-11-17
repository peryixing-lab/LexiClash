package main

import "testing"

func TestTunSettingsMatchVpnSession(t *testing.T) {
	for _, stack := range []string{"system", "gvisor", "mixed"} {
		settings, err := parseTunRuntimeSettings([]byte(`{"action":"start","tun":{"stack":"` + stack + `","mtu":1500}}`))
		if err != nil || settings.Stack != stack || settings.MTU != 1500 {
			t.Fatalf("settings=%+v error=%v", settings, err)
		}
	}
}

func TestTunSettingsLegacyDefaults(t *testing.T) {
	settings, err := parseTunRuntimeSettings([]byte(`{"action":"start"}`))
	if err != nil || settings != defaultTunRuntimeSettings() {
		t.Fatalf("settings=%+v error=%v", settings, err)
	}
}

func TestTunSettingsRejectInvalidCommand(t *testing.T) {
	for _, command := range []string{
		`{`, `{"tun":{}}`, `{"tun":{"stack":"unknown","mtu":1400}}`,
		`{"tun":{"stack":"system","mtu":1279}}`, `{"tun":{"stack":"system","mtu":9001}}`,
		`{"tun":{"stack":"system","mtu":1400.5}}`, `{"tun":{"stack":"system","mtu":-1}}`,
	} {
		if _, err := parseTunRuntimeSettings([]byte(command)); err == nil {
			t.Fatalf("accepted %s", command)
		}
	}
}
