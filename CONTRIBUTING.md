> **Languages:** English · [العربية](docs/ar/CONTRIBUTING.md) · [Čeština](docs/cs/CONTRIBUTING.md) · [Deutsch](docs/de/CONTRIBUTING.md) · [Español](docs/es/CONTRIBUTING.md) · [فارسی](docs/fa/CONTRIBUTING.md) · [Français](docs/fr/CONTRIBUTING.md) · [हिन्दी](docs/hi/CONTRIBUTING.md) · [Bahasa Indonesia](docs/id/CONTRIBUTING.md) · [Italiano](docs/it/CONTRIBUTING.md) · [日本語](docs/ja/CONTRIBUTING.md) · [한국어](docs/ko/CONTRIBUTING.md) · [Nederlands](docs/nl/CONTRIBUTING.md) · [Polski](docs/pl/CONTRIBUTING.md) · [Português](docs/pt/CONTRIBUTING.md) · [Русский](docs/ru/CONTRIBUTING.md) · [Svenska](docs/sv/CONTRIBUTING.md) · [ไทย](docs/th/CONTRIBUTING.md) · [Türkçe](docs/tr/CONTRIBUTING.md) · [Українська](docs/uk/CONTRIBUTING.md) · [Tiếng Việt](docs/vi/CONTRIBUTING.md) · [中文](docs/zh/CONTRIBUTING.md)

---

# Contributing to VDLiveUpdate

VDLU is a flashless, incremental self-update engine vendored into KernelSU/APatch/Magisk modules.
Contributions are welcome.

- Read [INTERFACES.md](docs/INTERFACES.md) first: it is the seam contract between the components (the law of
  convergence). Treat it as immutable unless a change is coordinated across the engine, producer and WebUI.
- Test end to end before a PR: `producer/vdlu-keygen`, `vdlu-pack`, `vdlu-sign`, then the engine
  (`check` / `run` / `boot`). Also `sh -n engine/*.sh` and `node --check webui/vdlu.js`.
- Security is non-negotiable: every manifest field is hostile input and `validate_plan()` stays
  fail-closed; the private signing key never touches CI or a device.
- POSIX sh on the device (no bashisms beyond `local`, no `jq`); keep comments terse.
- One logical change per PR; say what changed and why.

## Contacts

- Telegram: @VD_Priv8 https://t.me/VD_Priv8
- Channel: @Priv8_VD https://t.me/Priv8_VD
- E-mail: vd.priv8@pm.me

<!-- doc-footer -->

---

> _This documentation was generated with Claude (Anthropic) and is maintained by VD171. Corrections and improvements are welcome; see [CONTRIBUTING.md](CONTRIBUTING.md)._
