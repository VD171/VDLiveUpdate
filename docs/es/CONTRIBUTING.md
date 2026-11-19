> **Languages:** [English](../../CONTRIBUTING.md) · [العربية](../ar/CONTRIBUTING.md) · [Čeština](../cs/CONTRIBUTING.md) · [Deutsch](../de/CONTRIBUTING.md) · Español · [فارسی](../fa/CONTRIBUTING.md) · [Français](../fr/CONTRIBUTING.md) · [हिन्दी](../hi/CONTRIBUTING.md) · [Bahasa Indonesia](../id/CONTRIBUTING.md) · [Italiano](../it/CONTRIBUTING.md) · [日本語](../ja/CONTRIBUTING.md) · [한국어](../ko/CONTRIBUTING.md) · [Nederlands](../nl/CONTRIBUTING.md) · [Polski](../pl/CONTRIBUTING.md) · [Português](../pt/CONTRIBUTING.md) · [Русский](../ru/CONTRIBUTING.md) · [Svenska](../sv/CONTRIBUTING.md) · [ไทย](../th/CONTRIBUTING.md) · [Türkçe](../tr/CONTRIBUTING.md) · [Українська](../uk/CONTRIBUTING.md) · [Tiếng Việt](../vi/CONTRIBUTING.md) · [中文](../zh/CONTRIBUTING.md)

---

# Contribuir a VDLiveUpdate

VDLU es un engine de autoactualización flashless e incremental vendorizado en módulos KernelSU/APatch/Magisk.
Las contribuciones son bienvenidas.

- Lee [INTERFACES.md](INTERFACES.md) primero: es el contrato de costura entre los componentes (la ley de
  convergencia). Trátalo como inmutable salvo que un cambio se coordine entre el engine, el producer y la WebUI.
- Prueba de punta a punta antes de un PR: `producer/vdlu-keygen`, `vdlu-pack`, `vdlu-sign`, luego el engine
  (`check` / `run` / `boot`). También `sh -n engine/*.sh` y `node --check webui/vdlu.js`.
- La seguridad es innegociable: cada campo del manifiesto es input hostil y `validate_plan()` se mantiene
  fail-closed; la clave privada de firma nunca toca la CI ni un dispositivo.
- sh POSIX en el dispositivo (sin bashismos más allá de `local`, sin `jq`); mantén los comentarios escuetos.
- Un cambio lógico por PR; di qué cambió y por qué.

## Contactos

- Telegram: @VD_Priv8 https://t.me/VD_Priv8
- Canal: @Priv8_VD https://t.me/Priv8_VD
- E-mail: vd.priv8@pm.me

<!-- doc-footer -->

---

> _Esta documentación se generó con Claude (Anthropic) y la mantiene VD171. Las correcciones y mejoras son bienvenidas; consulta [CONTRIBUTING.md](CONTRIBUTING.md)._
