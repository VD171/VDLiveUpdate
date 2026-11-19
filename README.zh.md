<!--
  ======================================================================
   VDLiveUpdate (VDLU)  ::  flashless, incremental module updates
   A self-update engine for KernelSU/APatch/Magisk modules: fetch only the
   files that changed, apply the live ones with no reboot, verified by ed25519.

   Copyright (C) 2026  VD171
   SPDX-License-Identifier: Apache-2.0

   Licensed under the Apache License, Version 2.0; you may obtain a copy at
   http://www.apache.org/licenses/LICENSE-2.0

   Site           : https://vd171.ru
   Site           : https://vd.priv8.ru
   Source         : https://github.com/VD171/VDLiveUpdate
   GitHub         : @VD171 https://github.com/VD171
   XDA-Developers : @VD171 https://xdaforums.com/m/vd171.4699873/
   Telegram       : @VD_Priv8 https://t.me/VD_Priv8
   Channel        : @Priv8_VD https://t.me/Priv8_VD
   Discord        : @VD.Priv8 https://discord.com/users/1296831918989639721
   E-mail         : vd.priv8@pm.me
  ======================================================================
-->

# VDLiveUpdate

> **Languages:** [English](README.md) · [العربية](README.ar.md) · [Čeština](README.cs.md) · [Deutsch](README.de.md) · [Español](README.es.md) · [فارسی](README.fa.md) · [Français](README.fr.md) · [हिन्दी](README.hi.md) · [Bahasa Indonesia](README.id.md) · [Italiano](README.it.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Nederlands](README.nl.md) · [Polski](README.pl.md) · [Português](README.pt.md) · [Русский](README.ru.md) · [Svenska](README.sv.md) · [ไทย](README.th.md) · [Türkçe](README.tr.md) · [Українська](README.uk.md) · [Tiếng Việt](README.vi.md) · [中文](README.zh.md)

**VDLU** 是面向 **KernelSU / APatch / Magisk** 模块的 flashless、增量式自更新引擎。已安装的模块通过**只获取发生变化的文件**（按内容寻址的 blob + 一份已签名的清单）来自我更新，将「可热更」的文件**无需重启**地应用，并暂存并标记少数确实需要重启的文件（一个 `.so`、一个 `/system` overlay、一个 `sepolicy.rule`）。无需 root 管理器，无需重新下载整个 `.zip`，除了那些暂存的文件之外无需重启。

它被设计为 **vendored** 进一个模块（放入 `<module>/vdlu/`），而不是作为模块本身运行。

## 为什么

常规的模块更新会再次发送整个 `.zip`。对于一个大型模块，这意味着为了几行改动就要进行一次庞大的重新下载，而一份静态的更新清单只能指向一个 `zipUrl`，所以它无法提供设备实际拥有的那个 flavor（ABI、full vs lite）。VDLU 将**已安装的**文件树与一份已签名的 feed 做差异比对，只获取增量，于是 arm64-full 的安装保持 arm64-full，lite 的安装保持 lite，而且大多数更新都能热应用。

## 工作原理

- **Producer（PC / 发布）:** `vdlu-pack` 将一个模块文件树变成按内容寻址的 feed（`manifest.json` + `blobs/<sha256>`、gzip、去重、`delete[]`）；`vdlu-keygen` / `vdlu-sign`（ed25519）；`vdlu-gc` 按对最近 N 份清单的引用来修剪孤立的 blob（fail-safe，默认 dry-run）。
- **Engine（设备）:** POSIX sh，不用 `jq`。`update.sh`（`check | run | resume | boot | status | cancel`）把 DIFF -> FETCH -> APPLY -> COMMIT 作为一个**可恢复的事务**（日志）来运行，带回滚和一个 `mkdir` 锁。签名由内嵌的 `ed25519-mini` 校验（设备上没有 `openssl`）。
- **WebUI:** 一个即插即用的 Updates 面板（进度提示、取消、重启横幅），纯 JS。

## 配置档（Profiles）

- `trusted`：私人使用，`file://` 或 SSH 源，尽力而为式校验（始终校验 hash）。
- `hardened`：公开使用，**强制签名**，禁止降级。清单**绑定到模块 id**，并且在下载任何内容之前，每个字段都以 fail-closed 方式验证。

## 在你的模块中采用它

将 `engine/update.sh` + `vdlu-verify` + `verify/<abi>/ed25519-mini` vendor 进 `<module>/vdlu/`，把你的**原始 32 字节公钥**嵌入为 `vdlu/keyring/<id>.pub`，添加一份 `config`（profile + 源），接好触发器（`post-fs-data.sh` pre-zygote 以便开机自动更新；一个 WebUI 打开时的触发器），并把 `vdlu-pack` + `vdlu-sign` 加入你的发布流程。可运行的模板见 [`integration/`](integration/)。

## 安全

- **清单的每个字段都是敌对输入。** 当路径为绝对路径或含 `..`、`sha256` 不是 64 个十六进制字符、或 mode / class / encoding 无效时，`validate_plan()` 会在任何 fetch 或 apply **之前**以 fail-closed 方式拒绝整份清单。
- **私有签名密钥绝不接触 CI 或设备**；只嵌入原始公钥，校验使用 `ed25519-mini`，而非 `openssl`。
- `hardened` 通过取反实现 fail-closed：除了字面量 `trusted` 之外的任何值都被当作 `hardened`，因此一个被破坏的 profile 值永远无法悄悄接受一份未签名的清单。
- 重启类文件（`.so`、`/system` overlay、`sepolicy.rule`）会被**暂存，绝不覆盖写入一个活动的 inode**；其余一切都热应用。一次失败的 apply 会中止，而不是在没有备份的情况下覆盖。

## 构建 / 测试

它是脚本，没有什么要编译的。端到端（producer + engine 一起）:

```sh
producer/vdlu-keygen demo /tmp/k
producer/vdlu-pack /tmp/tree /tmp/feed demo 1 --version-name v1
producer/vdlu-sign /tmp/feed/manifest.json /tmp/k/demo.pem demo
VDLU_DIR=... MODULE_DIR=... MODID=demo sh engine/update.sh check   # then run / boot
```

`sh -n engine/*.sh`、`node --check webui/vdlu.js`，并在浏览器中打开 `webui/demo.html`（它会模拟到设备的桥接）。

## 文档

- [`INTERFACES.md`](INTERFACES.md): 各组件之间的接缝契约（收敛之法；请将其视为不可变）。
- `integration/`: 一份逐步的采用指南和接线片段。

## 另见

同一作者的姊妹项目:

- **[VDBackup](https://github.com/VD171/VD-Backup)**: 以 root 权限对应用和数据进行完整备份与还原，完全由 WebUI 驱动。
- **[COPG-VD](https://github.com/VD171/COPG-VD)**: 一个设备伪装器，把一个全新的 fingerprint 变成一份连贯、一致的配置。
- **[VD-dropbear](https://github.com/VD171/VD-dropbear)**: 一个面向 KernelSU/APatch/Magisk 的独立、可配置的 root SSH 守护进程。
- **[VDInfos](https://github.com/VD171/VD-Infos)**: 一个设备方法调试器，通过每一种能读取某项的方法来读取该项。
- **[VDGoogle](https://github.com/VD171/VD-Google)**: 读取 Google 在你设备上记录的内容，完全在设备上进行且无需联网。

## Contacts

- https://vd171.ru
- https://vd.priv8.ru
- **Telegram:** @VD_Priv8 https://t.me/VD_Priv8
- **Channel:** @Priv8_VD https://t.me/Priv8_VD
- **Discord:** @VD.Priv8 https://discord.com/users/1296831918989639721
- **E-mail:** vd.priv8@pm.me
- **XDA-Developers:** @VD171 https://xdaforums.com/m/vd171.4699873/
- **GitHub:** @VD171 https://github.com/VD171

## 许可证

VDLiveUpdate 自身的代码采用 **Apache-2.0**；见 [LICENSE](LICENSE)。它 vendor 了一个小型的 `ed25519-mini`
校验器和一个用于获取引导的静态 `curl`，各自遵循其自身的许可证；见
[NOTICE.md](NOTICE.md) 以及随附二进制文件旁边的 `PROVENANCE.json` 文件。

## 商标

VDLiveUpdate 是一个独立的、非官方的项目，不隶属于任何第三方，也未获得其认可。
"Android" 是 Google LLC 的商标；"KernelSU"、"Magisk" 和 "APatch" 是其各自作者的标志。VDLU
完全运行在你的设备上以及你自己的发布主机上。

## Tags

`VDLU` `flashless-update` `incremental-update` `KernelSU` `Magisk` `APatch` `module-update` `ed25519` `content-addressed` `OTA` `self-update` `Android` `VDLiveUpdate`
