# FAQ

对最常出现的问题的简短回答。每一条都链接到有完整叙述的那一页。

## "flashless"（免刷入）是什么意思？我第一次还要刷入吗？

是的，你刷入一次。模块以正常方式安装（在你的 root 管理器中刷入 zip）。
"Flashless" 描述的是此后的每一次更新：VDLU 只拉取
发生变化的文件并就地应用它们，因此你永远不会仅仅为了交付几行改动而重新刷入一个
完整的 zip。参见 [[Architecture]]。

## 一次更新需要重启吗？

通常不需要。大多数文件（你的 WebUI、二进制、库、配置、`module.prop`）
属于 **live** class 并原子地应用、无需重启。只有 reboot 类文件
（`zygisk/` 下的一个 `.so`、一个 `/system/**` overlay、一个 `*.rule` sepolicy 文件）会被
**staged** 并在下一次启动时交换，因为一个运行中的进程已经
映射了那个在用的 inode。当这发生时，WebUI 显示一个持久的 "reboot to
activate" 横幅。参见 [[Reboot Handling]]。

## 如果 feed 被 MITM 或被投毒，还安全吗？

安全，在一个 `hardened` feed 上。每个清单字段都被视为敌对输入。
清单必须携带一个针对其规范化形式的有效 ed25519 签名，而
`validate_plan()` **在任何下载之前**故障即关闭地运行：它在一个绝对路径或 `..` 路径、一个
不是 64 个十六进制字符的 `sha256`，或一个无效的 mode、class 或编码上拒绝整个
清单。清单还被绑定到你的模块 id，因此一个为不同模块有效签名的 feed
无法被用来替换它。无论哪个配置档，每个 blob 的 sha256 都会在下载后被验证。参见
[[Security and Trust Model]]。

## 它在设备上需要什么（依赖）？

非常少。纯 POSIX sh（mksh / busybox / toybox）外加 toybox 的 `sha256sum`、
`gzip`、`base64` 和 `date`；内嵌的 `ed25519-mini` 校验器；以及，仅对
一个 `https` 源，一个被拉取一次并缓存在 Tier-2 的静态 `curl`。
一个 `file://` 源则完全不需要 curl。**不依赖 `jq`**：
引擎用一个 gron 风格、用 `awk` 写成的扁平化器解析 JSON。参见 [[Engine]]。

## 设备上需要 openssl 吗？

不需要。`openssl` 只在 PC/发布端使用（`vdlu-keygen`、`vdlu-sign`）。
在设备上，签名验证使用精简的内嵌 `ed25519-mini` 二进制，
它读取一个原始 32 字节公钥。参见 [[Producer]] 和
[[Security and Trust Model]]。

## 我如何轮换签名密钥？

用 `vdlu-keygen` 生成一对新密钥，把新的原始 32 字节公钥添加到
设备 keyring 中、与先前的并列，并开始用新的 `key_id` 签名。设备按
清单的 `key_id` 挑选 `<keyring>/<key_id>.pub`，因此无需改动引擎。
交付当前和先前两个公钥意味着一个被轮换的密钥永远不会砖掉较旧的安装。
参见 [[Security and Trust Model]]。

## hardened 对比 trusted - 我该用哪个？

对任何公开 feed（通过 `https` 提供，例如 GitHub Pages）使用 `hardened`。
它使签名成为强制的并阻止降级。只对一个你已经控制的
私有 `file://` 或经 SSH staged 的源使用 `trusted`，在那里签名
是尽力而为的（每个 blob 哈希仍会被校验）。拿不定主意时，用 `hardened`：
它是故障即关闭的默认值，而且任何非 `trusted` 的值都被当作
`hardened` 处理。参见 [[Security and Trust Model]]。

## 如果一个 blob 被篡改或清单畸形了怎么办？

更新中止，不应用任何内容。一个畸形的清单会在任何 fetch 之前被
`validate_plan()` 整体拒绝。一个 sha256 与清单不匹配的 blob 会被拒绝；
同一个 blob 上的三次失败会中止 fetch 阶段，不应用任何内容。在任何严重失败时，
日志记录 `ERROR`，模块保持完好无损。参见 [[Engine]]。

## 一次更新能删除我的文件或砖掉设备吗？

该风险在设计上被遏制。被覆盖和被删除的文件会先备份
到 `rollback/<version>/`，而 `apply` 会中止，而不是在没有一次成功
备份的情况下覆盖。删除只在一笔事务到达 `DONE` 时运行，绝不会
在重启仍待处理时进行。一次失败的 apply 会回退它已经写入的 live 文件。
路径在使用前会被校验是否包含在模块目录内，
因此一个清单无法写到或删除到树外。参见 [[Engine]] 和
[[Security and Trust Model]]。

## 它在 KernelSU、Magisk 和 APatch 上都能用吗？

能。VDLU 是纯 POSIX sh 外加一个 WebUI，内嵌进模块，因此它在
KernelSU、APatch 和 Magisk 上一样运行。它使用 root 管理器的 WebUI 桥
（`ksu.exec`）来驱动引擎并轮询进度。参见 [[Architecture]] 和
[[WebUI]]。

## 设备上的占用有多大？

很小。引擎是脚本；唯一的二进制是每个 ABI 的 `ed25519-mini`
校验器（微小）以及，对一个 `https` 源，一个被拉取一次并缓存的静态 `curl`（约 1MB）。
一个已经捆绑了自己 `curl` 的模块会复用它，
完全不增加任何下载。Tier-2 blob 缓存保存已验证的内容外加
最近 3 个回滚版本。参见 [[Engine]] 和 [[Architecture]]。
