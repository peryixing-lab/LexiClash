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
69a198450f08c8d74b8b1cd2ae2fecb8faf752f00e7218619b1a4f3551915503  entry/libs/arm64-v8a/libflclash_core.so
259659e487be797d7fb8fec0542e5f0e7ab25d780674afd7fb6e918e9c49a630  entry/src/main/cpp/prebuilt/arm64-v8a/flclash_core.h
```
