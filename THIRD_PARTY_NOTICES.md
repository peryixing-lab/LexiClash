# 第三方来源与许可声明

LexiClash 由 [OHClash](https://github.com/peryixing-lab/OHClash) 迭代而来，项目整体采用 GPL-3.0。第三方代码与资源的版权归各自权利人所有，原有许可及版权声明继续适用。

## FlClash

- 上游：<https://github.com/chen08209/FlClash>。
- 来源版本：`v0.8.98`，提交 `7c61c90ac20493b474d19c75ec96262b478b4b88`。
- 使用范围：`native/core/` 的 Go 内核封装、部分界面交互参考和图像资源。
- 许可：GPL-3.0，副本见 [native/core/LICENSE](native/core/LICENSE)。服务图标的单独许可见 [SERVICE_ICONS_LICENSE.md](entry/src/main/resources/base/media/SERVICE_ICONS_LICENSE.md)。
- LexiClash 在 2026 年增加了 OpenHarmony 桥接、套接字保护、VPN / TUN 接入、配置预览及延迟测试等适配，具体改动以本仓库历史为准。

## ClashMeta / mihomo

- 主项目：<https://github.com/MetaCubeX/mihomo>。
- 实际源码分支：<https://github.com/chen08209/Clash.Meta>。
- 来源提交：`70f0570405c3c2c47bb113b88db95006d239b346`。
- 位置：`native/core/Clash.Meta/`。
- 许可：GPL-3.0，见 [内核许可证](native/core/Clash.Meta/LICENSE)。其他独立许可证和版权声明保留在对应目录中。
- 本项目增加控制器生命周期适配与测试，将 OpenVPN 测试的静态证书、私钥改为运行时生成。部分含认证字段的上游集成测试配置不随仓库分发，详见 [native/SOURCE.md](native/SOURCE.md)。

## OpenHarmony Go

- 来源：<https://gitcode.com/openharmony-sig/ohos_golang_go>。
- 构建版本：`release-branch.go1.24`，提交 `302a5306b6fad2f47196360b82561d1db1f954cf`（Go 1.24.5）。
- 工具链本体不随源码仓库分发，Release 中的原生库使用该工具链构建。

## Go 依赖与运行库

Go 依赖版本记录于 `native/core/go.mod`、`native/core/go.sum` 及 mihomo 源码目录内的对应文件。Release 随附第三方许可证归档，收录 Go 工具链、构建依赖及打包运行库所适用的可获取许可证和声明；各组件仍适用其原许可证。
