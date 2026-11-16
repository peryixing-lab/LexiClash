# ARM64 预编译 Go 内核

为方便克隆后直接使用 DevEco Studio 构建，仓库包含原生库和对应生成头文件。两者由本仓库 `native/core/` 中的源码构建；未打包个人签名、订阅配置或本机绝对用户路径。

- 平台：OpenHarmony / HarmonyOS，`arm64-v8a`。
- 编译器：OpenHarmony Go 1.24.5；源码与工具链版本见 [SOURCE.md](SOURCE.md)。
- 构建：`native/build-core.sh`，使用 `-trimpath`、`-buildmode=c-shared`、`with_gvisor,no_tailscale,no_zerotier,no_fake_tcp`。
- 源码：`native/core/` 与 `native/core/Clash.Meta/`；修改内核后应同时重新生成库与头文件。
- 重建步骤：[docs/build-native.md](../docs/build-native.md)。
- 第三方许可归档：[THIRD_PARTY_LICENSES.zip](THIRD_PARTY_LICENSES.zip)，同时作为 Release 附件提供。

## SHA-256

```text
562b61a31cfaf8788c2830f0ad2f587689fdfc53c7de2455100bbc5241cc79e6  entry/libs/arm64-v8a/libflclash_core.so
e05b530744f294564de3799320f39ead7dbc1db74e787cce9e99ad8d9642f285  entry/src/main/cpp/prebuilt/arm64-v8a/flclash_core.h
```
