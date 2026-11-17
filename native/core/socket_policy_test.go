package main

import "testing"

func TestPhysicalBindingPreservesBothTunForwarders(t *testing.T) {
	for _, address := range []string{"172.19.0.1:443", "172.19.0.2:53", "[fdfe:dcba:9876::1]:443", "[fdfe:dcba:9876::2]:53", "127.0.0.1:9090", "[::1]:9090"} {
		if needsPhysicalBinding("tcp", address) {
			t.Fatalf("local socket incorrectly bound outside TUN: %s", address)
		}
	}
	for _, address := range []string{"1.1.1.1:443", "[2606:4700:4700::1111]:443", "proxy.example:443"} {
		if !needsPhysicalBinding("tcp", address) {
			t.Fatalf("outbound socket would loop into TUN: %s", address)
		}
	}
	if !needsPhysicalBinding("udp", "[::]:0") || needsPhysicalBinding("tcp", "[::]:0") {
		t.Fatal("wildcard listener binding is incorrect")
	}
}
