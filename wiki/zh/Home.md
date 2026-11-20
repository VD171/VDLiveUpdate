# VDLiveUpdate (VDLU)

**VDLU 是面向 KernelSU / APatch / Magisk 模块的免刷入、增量式自更新引擎：已安装的模块通过一个已签名的 feed 更新自身文件，只拉取发生变化的部分，并且大多数内容无需重启即可应用。**

普通的模块更新会再次推送整个 `.zip`，因此几行改动也要付出一次完整重新下载的代价，而静态的更新清单只能指向单个 `zipUrl`（对所有设备只有一个版本变体）。VDLU 走的是另一条路：它将实际已安装的目录树与一个已签名、按内容寻址的 feed 做差异比较（diff），只下载差量（delta），并就地写入。arm64 的完整安装仍保持 arm64 full，lite 安装仍保持 lite，而且模块从不被重新刷入。

VDLU 的设计目的是被**内嵌（vendor）**进一个模块，放入 `<module>/vdlu/`。它本身不是一个独立模块。

## 目标

- **免刷入自更新。**就地更新已安装的模块，通过网络进行，无需 root 管理器，不重新刷入 `.zip`，也不丢失已安装的版本变体。
- **按内容增量。**只传输内容发生变化的 blob。按内容寻址的 feed（`manifest.json` + `blobs/<sha256>`）意味着未变化或已回退的文件永远不会被重新拉取。
- **在安全时免重启。**对普通文件立即、实时地应用。仅对确实需要重启的少数文件（一个 `.so`、一个 `/system` overlay、一个 `sepolicy.rule`）保留分阶段（staged）的重启。
- **在设备上保持精简。**纯 POSIX `sh`，设备上没有 `jq`、没有 `bash`、没有 `openssl`。验证依托于一个内嵌的 `ed25519-mini`；唯一被拉取的二进制是一个静态 `curl`，仅用于 `https` feed。
- **故障即关闭（fail-closed）且诚实。**清单中的每个字段都被视为敌对输入，在下载任何内容之前都会被校验。除非一次重新哈希（re-hash）证明确实完成，否则绝不报告"已完成"；在先做好备份之前绝不覆盖任何内容。

## 独特之处

VDLU 与典型 OTA 客户端的不同之处：

- **免刷入且增量。**按内容寻址的 diff / fetch / apply，并带去重（dedup）：设备相对于已签名的 feed 计算差量，只拉取缺失的 blob。
- **在可能时免重启。**普通文件实时应用；只有 `.so`、`/system` overlay 和 `sepolicy.rule` 文件会被 staged 并在一次重启中完成交换。参见 [[Reboot Handling]]。
- **设备上的 POSIX `sh`。**在 toybox / busybox / mksh 下运行。没有 `jq`（由一个 `gron` 风格、用 `awk` 写成的扁平化器解析 JSON），没有 `bash` 特有写法，没有重型运行时。
- **精简验证。**一个内嵌的 `ed25519-mini` 验证签名。**设备上没有 `openssl`**；私钥从不接触任何设备或 CI。
- **故障即关闭的安全性。**`validate_plan()` 在任何不合法字段上都会拒绝**整个**清单（绝对路径或 `..` 路径、不是 64 个十六进制字符的 `sha256`、无效的 mode / class / encoding）。有两个配置档，`trusted` 和 `hardened`，其中 `hardened` 通过反向判断实现故障即关闭。参见 [[Security and Trust Model]]。
- **可续传且原子。**一个日志（journal）使每笔事务都能抵御崩溃；写入使用 `rename` / `mv`；在任何覆盖之前都会先做备份，因此一次失败的应用会回滚，而不会损坏模块。

## 从这里开始

| 如果你想... | 前往 |
|---|---|
| 一步步把 VDLU 引入你的模块 | [[Quick Start]] |
| 一眼了解整个系统 | [[Architecture]] |
| 了解设备端引擎（`update.sh`） | [[Engine]] |
| 在你的 PC 上构建并签名一个 feed | [[Producer]] |
| 放入 Updates 面板 | [[WebUI]] |
| 阅读信任模型与威胁态势 | [[Security and Trust Model]] |
| 查看清单与 blob 布局 | [[Feed Format]] |
| 了解什么会触发重启以及为什么 | [[Reboot Handling]] |
| 提一个常见问题 | [[FAQ]] |
| 参与贡献 | [[Contributing]] |

## 项目链接

- **源码：** https://github.com/VD171/VDLiveUpdate
- **频道（更新）：** @Priv8_VD https://t.me/Priv8_VD

VDLiveUpdate 是一个独立的非官方项目。"Android" 是 Google LLC 的商标；"KernelSU"、"Magisk" 和 "APatch" 是各自作者的标识。VDLU 完全运行在你自己的设备和你自己的发布主机上。
