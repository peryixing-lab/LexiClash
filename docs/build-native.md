# 重新构建 Go 原生内核

仓库已提供可用的 ARM64 原生库和 C 头文件。只有修改 Go 内核或需要自行构建时，才需要执行以下步骤。

在 macOS / Linux 的 shell 环境中，先安装 Go 1.24.5 作为引导工具链，并准备 C/C++ 构建环境，然后在项目目录之外构建 OpenHarmony Go：

```sh
# 在项目目录之外执行，避免将工具链放入仓库。
git clone --branch release-branch.go1.24 --single-branch \
  https://gitcode.com/openharmony-sig/ohos_golang_go.git ohos-go
cd ohos-go
git checkout 302a5306b6fad2f47196360b82561d1db1f954cf
cd src
GOROOT_BOOTSTRAP="$(go env GOROOT)" ./make.bash
```

回到 LexiClash 项目根目录，按实际安装位置设置路径后构建内核：

```sh
export OHOS_GO="/绝对路径/ohos-go/bin/go"
# macOS 默认安装位置示例，其他系统请填写本机 SDK 的对应位置。
export OHOS_SDK="/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony"
sh native/build-core.sh
```

脚本生成 `entry/libs/arm64-v8a/libflclash_core.so` 与 `entry/src/main/cpp/prebuilt/arm64-v8a/flclash_core.h`，依赖 POSIX shell 与 SDK 的 OHOS Clang。Windows 用户需准备兼容的构建环境并调整工具链路径。源码版本及适配说明见 [native/SOURCE.md](../native/SOURCE.md)。
