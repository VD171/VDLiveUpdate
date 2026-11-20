> **Languages:** [English](../QUICKSTART.md) · [العربية](../ar/QUICKSTART.md) · [Čeština](../cs/QUICKSTART.md) · [Deutsch](../de/QUICKSTART.md) · [Español](../es/QUICKSTART.md) · [فارسی](../fa/QUICKSTART.md) · [Français](../fr/QUICKSTART.md) · [हिन्दी](../hi/QUICKSTART.md) · [Bahasa Indonesia](../id/QUICKSTART.md) · [Italiano](../it/QUICKSTART.md) · [日本語](../ja/QUICKSTART.md) · [한국어](../ko/QUICKSTART.md) · [Nederlands](../nl/QUICKSTART.md) · [Polski](../pl/QUICKSTART.md) · [Português](../pt/QUICKSTART.md) · [Русский](../ru/QUICKSTART.md) · [Svenska](../sv/QUICKSTART.md) · [ไทย](../th/QUICKSTART.md) · [Türkçe](../tr/QUICKSTART.md) · [Українська](../uk/QUICKSTART.md) · [Tiếng Việt](../vi/QUICKSTART.md) · 中文

---

# VDLU 采用快速入门

一份将 **VDLiveUpdate** vendor 进一个模块的复制粘贴清单。VDLU 本身不是一个模块：它被放入
`<module>/vdlu/` 并随你模块的 zip 一起 ship。完整的理由见 [`INTERFACES.md`](INTERFACES.md)
（seam 契约）、[`ENGINE.md`](ENGINE.md)、[`PRODUCER.md`](PRODUCER.md) 与 [`WEBUI.md`](WEBUI.md)。

将 `<id>` 替换为你的签名密钥 id，将 `<abi>` 替换为你 ship 的设备 ABI（`arm64-v8a`、
`armeabi-v7a`、`x86_64`、`x86`），将 `<module>` 替换为你的模块树。

## 目标 layout

这是模块在采用后所携带的确切 `vdlu/` 树：

```
<module>/
├── module.prop
├── post-fs-data.sh            # pre-zygote trigger: sh "$MODDIR/vdlu/update.sh" boot
├── webroot/
│   └── index.html             # your WebUI, wiring the Updates panel (step 5)
└── vdlu/
    ├── update.sh              # the engine (vendored byte-for-byte)
    ├── vdlu-verify            # ed25519 verify shim (device-side, no openssl)
    ├── verify/
    │   └── <abi>/ed25519-mini # per-ABI verifier binary
    ├── keyring/
    │   └── <id>.pub           # RAW 32-byte public key (NEVER the PEM)
    ├── config.default         # profile + source + automation defaults
    └── baseline.json          # install seed (unsigned, keyless)
```

engine 的可变状态（`config`、`current.json`、journal、lock）位于 Tier-2，`/data/adb/<modid>/vdlu/`，
在 module dir 之外；`config.default` 在首次运行时为其播种。

## 1. Vendor engine

将 engine、verify shim 和逐 ABI 的 verifier 复制进 `<module>/vdlu/`：

```sh
mkdir -p <module>/vdlu/verify
cp engine/update.sh      <module>/vdlu/update.sh
cp engine/vdlu-verify    <module>/vdlu/vdlu-verify
cp -r verify/<abi>       <module>/vdlu/verify/<abi>      # ed25519-mini per ABI
```

只 ship 你支持的 ABI；`customize.sh` 可在安装时将 `verify/` 修剪至设备的 ABI。

## 2. 生成一个签名密钥（一次性）

```sh
producer/vdlu-keygen <id> ./keys
```

这会发出 `<id>.pem`（priv，保持其远离每一台设备和任何 repo push）、`<id>.pub`（PEM，仅 PC 侧）
和 `<id>.pub.raw`（RAW 32 字节，用于设备 keyring）。

## 3. 嵌入原始公钥

设备 keyring 持有 **RAW 32 字节** 密钥，绝不是 PEM（`ed25519-mini` 无法读取 PEM）：

```sh
mkdir -p <module>/vdlu/keyring
cp ./keys/<id>.pub.raw <module>/vdlu/keyring/<id>.pub
```

keyring 跨 release 是稳定的（它只在密钥轮换时改变）：在重新 vendor 时，**验证，不要覆盖**它。

## 4. 写 config

在 `<module>/vdlu/` 中 ship `config.default`（在首次运行时为 Tier-2 `config` 播种）：

```
auto_on_reboot=1
auto_on_webui_open=1
source=https://<user>.github.io/<repo>/<module>
channel=stable
profile=hardened        # public feed: signature mandatory, downgrade blocked
net_policy=any
pubkey_dir=keyring
```

只对一个私有的 `file://`/SSH 来源使用 `profile=trusted`（verify 尽力而为；每个 blob 的 sha256 仍被
检查）。除字面量 `trusted` 之外的任何值都被当作 `hardened` 处理（fail-closed）。

## 5. 接线 trigger

**在 reboot 时**（`auto_on_reboot`）：从 `post-fs-data.sh` 以 pre-zygote 调用 engine，让已暂存的文件
（一个 `.so`、一个 `/system` overlay、一个 `sepolicy.rule`）无需额外 reboot 即可交换进来：

```sh
# <module>/post-fs-data.sh
MODDIR=${0%/*}
sh "$MODDIR/vdlu/update.sh" boot
```

**在 WebUI 打开时**（`auto_on_webui_open`）：在你的 `webroot/index.html` 中接线 drop-in Updates panel：

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
  VDLU.onWebUIOpen();                                             // evaluates journal + banner + auto_on_webui_open
  VDLU.mountUpdatesPanel(document.getElementById('b-updates'));  // the "Updates" tab
</script>
```

（`vdlu.js` / `vdlu.css` 从 `webui/` vendor 而来；可用 `i18n: window.VDLU_I18N_<LANG>` 添加一种翻译。）

## 6. 在你的 release workflow 中签名 feed

每次 release，打包最终模块树并对清单签名。将私钥保留在操作员机器上，绝不在 CI：

```sh
producer/vdlu-pack  <module>  ./out  <module> <versionCode> --version-name v<versionCode> --channel stable \
                    [--prev ./prev/manifest.json]        # delete[] = paths gone since prev
producer/vdlu-sign  ./out/manifest.json  ./keys/<id>.pem  <id>
# publish ./out/{manifest.json,blobs/} to <source>
```

## 7. Ship baseline

在已 ship 的树上生成 `baseline.json` 并将其放在 `<module>/vdlu/baseline.json`。它在全新安装时为
`current.json` 播种，使设备诞生即“最新”（无需重新抓取）。它是一个**本地受信种子**：未签名、无密钥，
因此 CI 可以构建它而从不触碰签名密钥：

```sh
producer/vdlu-pack  <module>  ./seed  <module> <versionCode> --version-name v<versionCode>
cp ./seed/manifest.json <module>/vdlu/baseline.json
```

它若缺失也非致命（设备只是在首次更新时从 `0` 开始）。

---

这就是全部采用过程。`sh -n <module>/vdlu/update.sh` 必须通过；在你 ship 之前，按
[`PRODUCER.md`](PRODUCER.md) 和根 README 中所示端到端地测试 producer 与 engine。

<!-- doc-footer -->

---

> _本文档由 Claude (Anthropic) 生成，并由 VD171 维护。欢迎修正和改进；请参阅 [CONTRIBUTING.md](CONTRIBUTING.md)。_
