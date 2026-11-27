> **Languages:** [English](../../CONTRIBUTING.md) · [العربية](../ar/CONTRIBUTING.md) · [Čeština](../cs/CONTRIBUTING.md) · [Deutsch](../de/CONTRIBUTING.md) · [Español](../es/CONTRIBUTING.md) · [فارسی](../fa/CONTRIBUTING.md) · Français · [हिन्दी](../hi/CONTRIBUTING.md) · [Bahasa Indonesia](../id/CONTRIBUTING.md) · [Italiano](../it/CONTRIBUTING.md) · [日本語](../ja/CONTRIBUTING.md) · [한국어](../ko/CONTRIBUTING.md) · [Nederlands](../nl/CONTRIBUTING.md) · [Polski](../pl/CONTRIBUTING.md) · [Português](../pt/CONTRIBUTING.md) · [Русский](../ru/CONTRIBUTING.md) · [Svenska](../sv/CONTRIBUTING.md) · [ไทย](../th/CONTRIBUTING.md) · [Türkçe](../tr/CONTRIBUTING.md) · [Українська](../uk/CONTRIBUTING.md) · [Tiếng Việt](../vi/CONTRIBUTING.md) · [中文](../zh/CONTRIBUTING.md)

---

# Contribuer à VDLiveUpdate

VDLU est un engine d'auto-mise-à-jour flashless et incrémentale vendorisé dans les modules KernelSU/APatch/Magisk.
Les contributions sont bienvenues.

- Lis [INTERFACES.md](INTERFACES.md) d'abord : c'est le contrat de couture entre les composants (la loi de
  convergence). Traite-le comme immuable sauf si un changement est coordonné à travers l'engine, le producer et la WebUI.
- Teste de bout en bout avant un PR : `producer/vdlu-keygen`, `vdlu-pack`, `vdlu-sign`, puis l'engine
  (`check` / `run` / `boot`). Aussi `sh -n engine/*.sh` et `node --check webui/vdlu.js`.
- La sécurité n'est pas négociable : chaque champ du manifeste est un input hostile et `validate_plan()` reste
  fail-closed, la clé privée de signature ne touche jamais la CI ni un appareil.
- sh POSIX sur l'appareil (pas de bashismes au-delà de `local`, pas de `jq`), garde les commentaires laconiques.
- Un changement logique par PR, dis ce qui a changé et pourquoi.

## Contacts

- Telegram: @VD_Priv8 https://t.me/VD_Priv8
- Canal: @Priv8_VD https://t.me/Priv8_VD
- E-mail: vd.priv8@pm.me

<!-- doc-footer -->

---

> _Cette documentation a été générée avec Claude (Anthropic) et est maintenue par VD171. Les corrections et améliorations sont les bienvenues, voir [CONTRIBUTING.md](CONTRIBUTING.md)._
