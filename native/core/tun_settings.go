package main

import (
	"encoding/json"
	"fmt"
)

// Kept in the session command so the ArkTS VPN and native packet stack use
// exactly the same MTU. Missing settings preserve the legacy defaults.
type tunRuntimeSettings struct {
	Stack string `json:"stack"`
	MTU   uint32 `json:"mtu"`
}

func defaultTunRuntimeSettings() tunRuntimeSettings {
	return tunRuntimeSettings{Stack: "system", MTU: 1400}
}

func parseTunRuntimeSettings(data []byte) (tunRuntimeSettings, error) {
	var command struct {
		Tun *tunRuntimeSettings `json:"tun"`
	}
	settings := defaultTunRuntimeSettings()
	if err := json.Unmarshal(data, &command); err != nil {
		return settings, fmt.Errorf("invalid VPN session command: %w", err)
	}
	if command.Tun == nil {
		return settings, nil
	}
	settings = *command.Tun
	switch settings.Stack {
	case "system", "gvisor", "mixed":
	default:
		return settings, fmt.Errorf("invalid TUN stack: %q", settings.Stack)
	}
	if settings.MTU < 1280 || settings.MTU > 9000 {
		return settings, fmt.Errorf("TUN MTU must be between 1280 and 9000")
	}
	return settings, nil
}
