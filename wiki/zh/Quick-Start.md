# Quick Start

这是引入清单：如何把 **VDLiveUpdate (VDLU)** 内嵌（vendor）进一个
KernelSU / APatch / Magisk 模块。VDLU 本身不是一个模块。它被放入
`<module>/vdlu/` 并在你模块的 zip 内部交付，因此一个已安装的模块可以
从你发布的一个已签名 feed 免刷入地更新自身。

全文中，把 `<id>` 替换为你的签名密钥 id，`<abi>` 替换为你所交付的设备
ABI（`arm64-v8a`、`armeabi-v7a`、`x86_64`、`x86`），`<module>`
替换为你的模块目录树。

关于每一部分背后的理由，参见 [[Engine]]、[[Producer]]、[[WebUI]] 和
[[Security and Trust Model]]。

## 模块内 `vdlu/` 布局

这是你的模块在引入之后所承载的确切目录树：

```
<module>/
|-- module.prop
|-- post-fs-data.sh            # pre-zygote trigger: sh "$MODDIR/vdlu/update.sh" boot
|-- webroot/
|   `-- index.html             # your WebUI, wiring the Updates panel (step 5)
`-- vdlu/
    |-- update.sh              # the engine (vendored byte-for-byte)
    |-- vdlu-verify            # ed25519 verify shim (device-side, no openssl)
    |-- verify/
    |   `-- <abi>/ed25519-mini # per-ABI verifier binary
    |-- keyring/
    |   `-- <id>.pub           # RAW 32-byte public key (NEVER the PEM)
    |-- config.default         # profile + source + automation defaults
    `-- baseline.json          # install seed (unsigned, keyless)
```

引擎的可变状态（`config`、`current.json`、日志、锁、blob 缓存）
存在于 Tier-2 的 `/data/adb/<modid>/vdlu/`，在模块目录之外。
`config.default` 在首次运行时播种那个 Tier-2 `config`。完整状态布局参见
[[Engine]]。

## 1. 内嵌引擎

把引擎、verify shim 和每个 ABI 的校验器二进制复制进
`<module>/vdlu/`：

```sh
mkdir -p <module>/vdlu/verify
cp engine/update.sh   <module>/vdlu/update.sh
cp engine/vdlu-verify <module>/vdlu/vdlu-verify
cp -r verify/<abi>    <module>/vdlu/verify/<abi>    # ed25519-mini per ABI
```

只交付你所支持的 ABI。你的 `customize.sh` 可以在安装时把 `verify/` 裁剪到
设备的 ABI。

## 2. 生成一个签名密钥（一次性）

```sh
producer/vdlu-keygen <id> ./keys
```

这会发出三个文件：

- `<id>.pem` - 私钥。把它从每台设备上、从任何仓库推送或 CI 密钥中
  排除出去。
- `<id>.pub` - PEM 公钥。仅 PC 端（由 `vdlu-sign` 使用）。
- `<id>.pub.raw` - 原始 32 字节公钥，用于设备 keyring。

关于为什么这种拆分很重要，参见 [[Security and Trust Model]]。

## 3. 内嵌原始公钥

设备 keyring 保存**原始 32 字节**密钥，绝不是 PEM。`ed25519-mini`
无法读取一个 PEM，因此把 PEM 复制到这里会破坏设备上的验证：

```sh
mkdir -p <module>/vdlu/keyring
cp ./keys/<id>.pub.raw <module>/vdlu/keyring/<id>.pub
```

keyring 跨版本是稳定的：它只在密钥轮换时更改。在
重新内嵌时，**verify 它，不要覆盖它**。

## 4. 写配置

在 `<module>/vdlu/` 中交付 `config.default`。它在首次运行时播种 Tier-2 `config`：

```
auto_on_reboot=1
auto_on_webui_open=1
source=https://<user>.github.io/<repo>/<module>
channel=stable
profile=hardened        # public feed: signature mandatory, downgrade blocked
net_policy=any
pubkey_dir=keyring
```

只对一个私有 `file://` 或 SSH 源使用 `profile=trusted`（那里 verify 是
尽力而为，但每个 blob 的 sha256 仍会被校验）。任何不同于字面
`trusted` 的值都被当作 `hardened` 处理，故障即关闭。完整的配置档语义参见
[[Security and Trust Model]]。

## 5. 接入触发器

**在重启时**（`auto_on_reboot`）：从 `post-fs-data.sh` 在 pre-zygote 调用引擎，
使 staged 的 reboot 类文件（一个 `.so`、一个 `/system` overlay、
一个 `sepolicy.rule`）无需额外重启即可交换到位：

```sh
# <module>/post-fs-data.sh
MODDIR=${0%/*}
sh "$MODDIR/vdlu/update.sh" boot
```

**在 WebUI 打开时**（`auto_on_webui_open`）：在你的
`webroot/index.html` 中接入即插即用的 Updates 面板：

```html
<link rel="stylesheet" href="vdlu.css">
<script src="vdlu.js"></script>
<script>
  VDLU.init({
    moduleDir: '/data/adb/modules/' + MODID,
    vdluDir:   '/data/adb/' + MODID + '/vdlu',
    modid:     MODID,
    module:    'YourModule'
  });
  VDLU.onWebUIOpen();                                            // journal + banner + auto_on_webui_open
  VDLU.mountUpdatesPanel(document.getElementById('b-updates'));  // the "Updates" tab
</script>
```

`vdlu.js` 和 `vdlu.css` 从 `webui/` 内嵌而来。一个翻译可以通过
`i18n: window.VDLU_I18N_<LANG>` 添加。面板契约参见 [[WebUI]]。

## 6. 在你的发布工作流中签名 feed

每次发布，打包最终的模块目录树并签名清单。把私钥
保留在操作者机器上，绝不放进 CI：

```sh
producer/vdlu-pack  <module>  ./out  <module> <versionCode> \
                    --version-name v<versionCode> --channel stable \
                    [--prev ./prev/manifest.json]      # delete[] = paths gone since prev
producer/vdlu-sign  ./out/manifest.json  ./keys/<id>.pem  <id>
# publish ./out/{manifest.json,blobs/} to <source>
```

`vdlu-pack` 按内容寻址且去重，因此发布是增量的：
未变化的 blob 永远不会被再次推送。参见 [[Producer]] 和 [[Feed Format]]。

## 7. 交付 baseline

在所交付的目录树上生成 `baseline.json`，并把它放在
`<module>/vdlu/baseline.json`。它在一次全新安装时播种 `current.json`，因此
设备一出生即为"当前"，不会重新拉取它自己所交付的版本。它是一个
**本地可信种子**：未签名且无密钥，因此 CI 可以构建它而从不
触碰签名密钥：

```sh
producer/vdlu-pack  <module>  ./seed  <module> <versionCode> --version-name v<versionCode>
cp ./seed/manifest.json <module>/vdlu/baseline.json
```

它缺失也不致命：设备只是在首次更新时从版本 `0` 开始。

---

这就是全部引入。在你交付之前，`sh -n <module>/vdlu/update.sh`
必须通过，而且你应该像 [[Contributing]] 和 [[Producer]] 中所示那样端到端地
测试 producer 和引擎。
