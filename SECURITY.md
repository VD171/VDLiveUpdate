> **Languages:** English · [العربية](docs/ar/SECURITY.md) · [Čeština](docs/cs/SECURITY.md) · [Deutsch](docs/de/SECURITY.md) · [Español](docs/es/SECURITY.md) · [فارسی](docs/fa/SECURITY.md) · [Français](docs/fr/SECURITY.md) · [हिन्दी](docs/hi/SECURITY.md) · [Bahasa Indonesia](docs/id/SECURITY.md) · [Italiano](docs/it/SECURITY.md) · [日本語](docs/ja/SECURITY.md) · [한국어](docs/ko/SECURITY.md) · [Nederlands](docs/nl/SECURITY.md) · [Polski](docs/pl/SECURITY.md) · [Português](docs/pt/SECURITY.md) · [Русский](docs/ru/SECURITY.md) · [Svenska](docs/sv/SECURITY.md) · [ไทย](docs/th/SECURITY.md) · [Türkçe](docs/tr/SECURITY.md) · [Українська](docs/uk/SECURITY.md) · [Tiếng Việt](docs/vi/SECURITY.md) · [中文](docs/zh/SECURITY.md)

---

# Security Policy

VDLiveUpdate (VDLU) applies flashless root updates to a live module: it writes into the
module's own directory and swaps a Zygisk `.so` at boot, running in the module's root
context. We take security seriously.

## Reporting a vulnerability

- **Site:** https://vd171.ru
- **Site:** https://vd.priv8.ru
- **Issues:** https://github.com/VD171/VDLiveUpdate/issues
- **GitHub:** [@VD171](https://github.com/VD171)
- **XDA-Developers:** [@VD171](https://xdaforums.com/m/vd171.4699873/)
- **Telegram:** [@VD_Priv8](https://t.me/VD_Priv8)
- **Channel:** [@Priv8_VD](https://t.me/Priv8_VD)
- **Discord:** [@VD.Priv8](https://discord.com/users/1296831918989639721)
- **E-mail:** vd.priv8@pm.me

Include a clear description and, if possible, a manifest or feed that reproduces the
issue. We will respond as soon as we can and credit you if you wish.

## Scope notes

- Updates are content-addressed blobs plus an ed25519-signed `manifest.json`. The device
  verifies the signature with an embedded `ed25519-mini` (no openssl on the device), and
  every blob is checked against its `sha256` before it is used.
- The hardened profile (the public default) requires a valid signature and blocks
  downgrade. The "from" version is floored by the installed module's `versionCode` (read
  from `module.prop`), so a module is never reverted behind the feed.
- The trust root (the `keyring/` raw ed25519 public key and the `verify/` binaries) is
  flash-only and is never rotated over the air. The producer excludes it from the feed
  and the engine ignores every `vdlu/` path in a fetched plan, so a leaked signing key
  cannot swap the verifier or the key and persist root.
- A manifest validly signed for another module cannot write into a different module's
  directory. The signed `module` field must equal the on-device `MODID` (cross-module
  bind check), and every write and delete is confined to the module directory.
- The engine runs in the module's own root context and never weakens it. It adds no
  privilege and interpolates no manifest field into a shell, every `path`, `sha256`,
  `mode`, and `delete[]` entry is validated as hostile input before use.
- The posture is fail-closed. A corrupted or unknown `profile` value never falls through
  to accepting unsigned content (anything that is not exactly `trusted` is treated as
  `hardened`), and a backup is written before any file is overwritten, so a failed apply
  never destroys the installed version.
- See [TRUST-MODEL.md](docs/TRUST-MODEL.md) for the full trust model, fail-closed
  guarantees, and hardening details.

<!-- doc-footer -->

---

> _This documentation was generated with Claude (Anthropic) and is maintained by VD171. Corrections and improvements are welcome, see [CONTRIBUTING.md](CONTRIBUTING.md)._
