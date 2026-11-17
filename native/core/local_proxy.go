package main

import (
	"errors"
	"github.com/metacubex/mihomo/listener"
)

// Only starts loopback listeners; it never creates a system VPN or TUN.
func startLocalProxyListeners() error {
	if currentConfig == nil || currentConfig.General.MixedPort <= 0 {
		return errors.New("本地混合代理端口未配置")
	}
	handleStartListener()
	if listener.GetPorts().MixedPort != currentConfig.General.MixedPort {
		return errors.New("本地混合代理端口监听失败，请检查端口是否被占用")
	}
	return nil
}
