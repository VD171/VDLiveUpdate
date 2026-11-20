# Contributing

欢迎贡献。VDLU 是一个免刷入、增量式的自更新引擎，
内嵌进 KernelSU / APatch / Magisk 模块。本页是实用的开发
工作流；关于各部分如何拼合，请先阅读 [[Architecture]]、[[Engine]] 和
[[Producer]]。

## 没有东西需要编译

VDLU 是脚本（POSIX sh、发布端的一点 Python、WebUI 的纯 JS），
因此没有构建步骤。你通过端到端运行流水线
并对每一部分做静态检查来验证一次改动。

## 接缝契约优先

组件之间的接口契约（引擎、producer 与 WebUI 共享的
CLI 签名、文件名和 JSON 键）是**收敛之法**。
把它当作不可变的。如果你的改动触及 producer 到引擎的接缝
（清单模式、日志模式、配置键、签名/规范化规则），
**先对齐接口契约**，然后改动两侧的代码以匹配。
接缝一侧而非另一侧的改动会悄然破坏引入者。
关于签名器与校验器必须逐字节一致的规范化规则，参见 [[Producer]]。

## 在 PR 之前端到端测试

在一个一次性的目录树上一起运行 producer 和引擎，方式与一个
引入者的发布完全相同：

```sh
# 1. a signing key
producer/vdlu-keygen demo /tmp/k

# 2. pack a module tree into a feed
producer/vdlu-pack /tmp/tree /tmp/feed demo 1 --version-name v1

# 3. sign the manifest in place
producer/vdlu-sign /tmp/feed/manifest.json /tmp/k/demo.pem demo

# 4. verify the manifest the way the device will (RAW 32B keyring)
engine/vdlu-verify /tmp/feed/manifest.json /tmp/keyring

# 5. drive the engine against the feed (source=file:///tmp/feed in the config)
VDLU_DIR=... MODULE_DIR=... MODID=demo sh engine/update.sh check   # then run / boot
```

然后对每个组件做静态检查：

```sh
sh -n engine/*.sh            # POSIX sh syntax, must pass
node --check webui/vdlu.js   # WebUI JS syntax
```

并在浏览器中打开 `webui/demo.html`：它模拟 root 管理器桥
（`ksu.exec`），因此你可以在无设备的情况下演练 Updates 面板、进度 toast、取消
和重启横幅。参见 [[WebUI]]。

## 内部规则

- **设备上的 POSIX sh。**除了 `local` 之外不用任何 bash 写法，也不用 `jq`。它必须
  在 toybox / busybox 上运行。
- **安全不可商量。**每个清单字段都是敌对输入；
  `validate_plan()` 保持故障即关闭，而私有签名密钥从不接触
  CI 或设备。不要为了让一个测试通过而放松一项检查。
- **失败时的严谨。**让事务保持可续传：没有匹配的重新哈希
  就没有东西报告 "done"，没有备份就没有东西被覆盖，而且
  apply 保持原子。
- **始终是发布质量。**保持注释简洁；不要无谓的注释。
- **每个 PR 一个逻辑改动。**说明改了什么以及为什么。

## 提交 issue

开一个 issue，描述你做了什么、你期望什么，以及发生了什么。
对于一个 bug，附上模块 id、源配置档（`hardened` 或 `trusted`）、
你运行的 `update.sh` 命令，以及相关的 `journal.json`（它记录
阶段、状态和错误）。对于一个特性，说明它触及哪个组件（引擎、
producer 或 WebUI），以便接缝影响从一开始就清晰。
