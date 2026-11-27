> **Languages:** [English](../../SECURITY.md) · [العربية](../ar/SECURITY.md) · [Čeština](../cs/SECURITY.md) · [Deutsch](../de/SECURITY.md) · [Español](../es/SECURITY.md) · [فارسی](../fa/SECURITY.md) · [Français](../fr/SECURITY.md) · [हिन्दी](../hi/SECURITY.md) · [Bahasa Indonesia](../id/SECURITY.md) · [Italiano](../it/SECURITY.md) · [日本語](../ja/SECURITY.md) · [한국어](../ko/SECURITY.md) · Nederlands · [Polski](../pl/SECURITY.md) · [Português](../pt/SECURITY.md) · [Русский](../ru/SECURITY.md) · [Svenska](../sv/SECURITY.md) · [ไทย](../th/SECURITY.md) · [Türkçe](../tr/SECURITY.md) · [Українська](../uk/SECURITY.md) · [Tiếng Việt](../vi/SECURITY.md) · [中文](../zh/SECURITY.md)

---

# Beveiligingsbeleid

VDLiveUpdate (VDLU) past flashless root-updates toe op een actieve module: het schrijft
naar de eigen map van de module en wisselt bij het opstarten een Zygisk-`.so` om, draaiend
in de root-context van de module. Wij nemen beveiliging serieus.

## Een kwetsbaarheid melden

- **Site:** https://vd171.ru
- **Site:** https://vd.priv8.ru
- **Issues:** https://github.com/VD171/VDLiveUpdate/issues
- **GitHub:** [@VD171](https://github.com/VD171)
- **XDA-Developers:** [@VD171](https://xdaforums.com/m/vd171.4699873/)
- **Telegram:** [@VD_Priv8](https://t.me/VD_Priv8)
- **Channel:** [@Priv8_VD](https://t.me/Priv8_VD)
- **Discord:** [@VD.Priv8](https://discord.com/users/1296831918989639721)
- **E-mail:** vd.priv8@pm.me

Voeg een duidelijke beschrijving toe en, indien mogelijk, een manifest of feed die het
probleem reproduceert. We reageren zo snel als we kunnen en vermelden je met naam als je
dat wilt.

## Scope-opmerkingen

- Updates zijn content-addressed blobs plus een met ed25519 ondertekende `manifest.json`.
  Het apparaat verifieert de handtekening met een ingebedde `ed25519-mini` (geen openssl op
  het apparaat), en elke blob wordt tegen zijn `sha256` gecontroleerd voordat die wordt
  gebruikt.
- Het hardened profiel (de publieke standaard) vereist een geldige handtekening en blokkeert
  downgrade. De "van"-versie wordt begrensd door de `versionCode` van de geïnstalleerde
  module (gelezen uit `module.prop`), zodat een module nooit achter de feed wordt teruggezet.
- De vertrouwensbasis (de ruwe ed25519-publieke sleutel in `keyring/` en de binaries in
  `verify/`) is alleen-flash en wordt nooit via het netwerk geroteerd. De producer sluit die
  uit van de feed en de engine negeert elk `vdlu/`-pad in een opgehaald plan, zodat een
  gelekte ondertekeningssleutel de verifier of de sleutel niet kan verwisselen en root niet
  kan laten voortduren.
- Een manifest dat geldig is ondertekend voor een andere module kan niet schrijven naar de
  map van een andere module. Het ondertekende veld `module` moet gelijk zijn aan de `MODID`
  op het apparaat (module-overschrijdende bindingscontrole), en elk schrijven en verwijderen
  blijft beperkt tot de modulemap.
- De engine draait in de eigen root-context van de module en verzwakt die nooit. Het voegt
  geen privileges toe en interpoleert geen enkel manifestveld in een shell, elke waarde van
  `path`, `sha256`, `mode` en `delete[]` wordt vóór gebruik als vijandige invoer gevalideerd.
- De houding is fail-closed. Een beschadigde of onbekende `profile`-waarde valt nooit door
  naar het accepteren van niet-ondertekende inhoud (alles wat niet exact `trusted` is, wordt
  als `hardened` behandeld), en er wordt een back-up geschreven voordat enig bestand wordt
  overschreven, zodat een mislukte apply de geïnstalleerde versie nooit vernietigt.
- Zie [TRUST-MODEL.md](TRUST-MODEL.md) voor het volledige vertrouwensmodel, de fail-closed
  garanties en de hardening-details.

<!-- doc-footer -->

---

> _Deze documentatie is gegenereerd met Claude (Anthropic) en wordt onderhouden door VD171. Correcties en verbeteringen zijn welkom, zie [CONTRIBUTING.md](CONTRIBUTING.md)._
