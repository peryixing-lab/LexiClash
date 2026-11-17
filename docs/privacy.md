# 网络隐私策略与验证

应用把网络设置、覆写规则和节点选择写入运行配置的 `lexiclash` 字段，订阅原文保持不变。原生内核共用一套 YAML 编译逻辑处理启动和 REST 热重载。旧内核不支持 `privacy.capabilities` 时拒绝启动 VPN，避免静默忽略策略。

## 当前行为

- 默认开启「WebRTC 防泄露」，根据 STUN 报头拦截 UDP 探测，包括 3478、19302 和其他端口。可能影响语音、视频和 P2P，可在高级设置关闭。它不能改变浏览器枚举本地接口、生成 host candidate 的行为。
- VPN 同时配置 IPv4、IPv6 默认路由。关闭 IPv6 时仍接管流量，再由内核拒绝；开启后按配置分流。系统网卡和内核共用 TUN 页面设置的 MTU，默认 1400。
- 分应用名单决定哪些应用进入隧道；绕过 VPN 的应用不受内核防泄露策略保护。入口与设置见 [TUN 使用说明](tun.md) 和 [分应用代理说明](app-routing.md)。
- TUN 接管所有目的地址的 TCP/UDP 53。应用自带 DoH/DoT 不会被解密，按普通网络连接处理。
- 规则、全局模式下，内核业务域名解析使用经代理发送的 DoH/DoT；应用代理链时 DNS 指向链的出口。主、备解析器走同一代理路径，不回落系统/明文 DNS。提供器节点经 GLOBAL 组解析，DNS 拨号前检查选中的节点，拒绝隐藏的 DIRECT。
- 节点域名和 DNS 服务域名使用独立启动解析：直连的 `tls://223.5.5.5:853` / `https://1.1.1.1/dns-query`。这些解析器仍能看到设备对代理节点域名的查询，但不是业务查询的失败回退路径。
- 主动选择直连模式时，业务 DNS 也使用直连加密上游。规则模式下明确配置的 DIRECT 规则仍有效。
- 覆写规则置于订阅规则前；其中 REJECT / REJECT-DROP 还在全局/直连路由选择前检查。STUN 特征拦截独立于路由模式。
- 命中的代理不支持 UDP 时拒绝连接，不继续匹配到 DIRECT；TCP 链仍可用，并提示已知 TCP-only 节点。
- 热重载顺序执行。拒绝错误配置时保留 TUN 和上次有效配置，不替换成允许直连的默认配置。切换模式、节点、设置时重载完整策略；应用成功后才更新下次启动配置。
- 网络恢复清真实 DNS 答案缓存，保留 fake-IP 映射。DNS 页面停止从普通连接推造查询、上游和耗时，明确提示尚未接入真实 DNS 日志。

## 本地验证

```sh
node scripts/test-runtime.cjs
cd native/core
CGO_ENABLED=0 go test -tags no_tailscale,no_zerotier,no_fake_tcp ./...
cd Clash.Meta
go test -race -tags no_tailscale,no_zerotier,no_fake_tcp ./config ./tunnel ./listener/sing_tun
```

包装层测试需允许本地 loopback 监听。修改 Go 后必须按 [build-native.md](build-native.md) 重建 ARM64 `.so`，再构建应用。

## 真机验收

1. 安装新 HAP，开启 WebRTC 防泄露，在规则、全局、代理链下访问 [Egress Observatory](https://blackslience-reaper.github.io/egress-observatory/)。预期 STUN 无公网候选；这表示探测被阻断，不表示浏览器禁用了 WebRTC。
2. 在双栈 Wi-Fi、蜂窝网络测试 IPv6 开关。关闭时 IPv6 目标应不可达；开启后核对实际分流路径，不能出现意外的运营商公网 IPv6。
3. 从路由器抓包核对：业务查询不应直接发出 TCP/UDP 53；启动解析仍可出现上述加密 DNS 连接。浏览器安全 DNS 需单独核对路径。
4. 阻断节点、切网、重载错误配置后复测。UDP 不支持时应失败，不能出现运营商 STUN 出口；错误配置不能销毁现有 TUN。
5. 自动测试、交叉编译不能代替真机验收。VPN 进程被终止、VPN 关闭或权限被撤销后，应用尚无系统级始终阻断功能，不能承诺继续阻止普通上网。

TCP「像代理转发」反映目标看到的 SYN 等连接特征，不等于真实地址泄露。增加跳数、拦截 STUN、更换 MTU 都不能保证消除该标记；本次修复不伪造检测结果。
