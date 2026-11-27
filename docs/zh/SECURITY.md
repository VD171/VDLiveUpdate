> **Languages:** [English](../../SECURITY.md) · [العربية](../ar/SECURITY.md) · [Čeština](../cs/SECURITY.md) · [Deutsch](../de/SECURITY.md) · [Español](../es/SECURITY.md) · [فارسی](../fa/SECURITY.md) · [Français](../fr/SECURITY.md) · [हिन्दी](../hi/SECURITY.md) · [Bahasa Indonesia](../id/SECURITY.md) · [Italiano](../it/SECURITY.md) · [日本語](../ja/SECURITY.md) · [한국어](../ko/SECURITY.md) · [Nederlands](../nl/SECURITY.md) · [Polski](../pl/SECURITY.md) · [Português](../pt/SECURITY.md) · [Русский](../ru/SECURITY.md) · [Svenska](../sv/SECURITY.md) · [ไทย](../th/SECURITY.md) · [Türkçe](../tr/SECURITY.md) · [Українська](../uk/SECURITY.md) · [Tiếng Việt](../vi/SECURITY.md) · 中文

---

# 安全策略

VDLiveUpdate (VDLU) 对运行中的模块应用 flashless 的 root 更新：它写入模块自身的目录，并在
启动时替换 Zygisk 的 `.so`，在模块的 root 上下文中运行。我们认真对待安全。

## 报告漏洞

- **Site:** https://vd171.ru
- **Site:** https://vd.priv8.ru
- **Issues:** https://github.com/VD171/VDLiveUpdate/issues
- **GitHub:** [@VD171](https://github.com/VD171)
- **XDA-Developers:** [@VD171](https://xdaforums.com/m/vd171.4699873/)
- **Telegram:** [@VD_Priv8](https://t.me/VD_Priv8)
- **Channel:** [@Priv8_VD](https://t.me/Priv8_VD)
- **Discord:** [@VD.Priv8](https://discord.com/users/1296831918989639721)
- **E-mail:** vd.priv8@pm.me

请附上清晰的描述，如有可能，附上能复现该问题的 manifest 或 feed。我们会尽快回复，并在你愿意
时给予致谢。

## 范围说明

- 更新是 content-addressed 的 blob 加上一个由 ed25519 签名的 `manifest.json`。设备使用内嵌
  的 `ed25519-mini` 验证签名（设备上没有 openssl），并且每个 blob 在使用前都会与其 `sha256`
  进行核对。
- hardened 配置（公开默认值）要求有效签名并阻止 downgrade。"起始"版本以已安装模块的
  `versionCode`（从 `module.prop` 读取）为下限，因此模块永远不会被回退到 feed 之后。
- 信任根（`keyring/` 中的原始 ed25519 公钥和 `verify/` 中的二进制文件）仅限 flash，绝不通过
  网络轮换。生产者将其排除在 feed 之外，engine 会忽略已下载计划中的每个 `vdlu/` 路径，因此
  泄露的签名密钥无法替换验证器或密钥并持久保持 root。
- 为另一个模块有效签名的 manifest 无法写入不同模块的目录。签名的 `module` 字段必须等于设备
  上的 `MODID`（跨模块绑定检查），并且每次写入和删除都被限制在模块目录内。
- engine 在模块自身的 root 上下文中运行，且绝不削弱它。它不添加任何权限，也不将任何 manifest
  字段插入 shell，`path`、`sha256`、`mode` 和 `delete[]` 的每个值在使用前都会作为敌对输入进
  行校验。
- 其姿态是 fail-closed。损坏或未知的 `profile` 值绝不会滑向接受未签名的内容（任何不完全等于
  `trusted` 的值都被视为 `hardened`），并且在覆盖任何文件之前都会写入备份，因此失败的 apply
  绝不会破坏已安装的版本。
- 完整的信任模型、fail-closed 保证和 hardening 详情，请参阅 [TRUST-MODEL.md](TRUST-MODEL.md)。

<!-- doc-footer -->

---

> _本文档由 Claude (Anthropic) 生成，并由 VD171 维护。欢迎修正和改进；请参阅 [CONTRIBUTING.md](CONTRIBUTING.md)。_
