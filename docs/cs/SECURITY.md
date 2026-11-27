> **Languages:** [English](../../SECURITY.md) · [العربية](../ar/SECURITY.md) · Čeština · [Deutsch](../de/SECURITY.md) · [Español](../es/SECURITY.md) · [فارسی](../fa/SECURITY.md) · [Français](../fr/SECURITY.md) · [हिन्दी](../hi/SECURITY.md) · [Bahasa Indonesia](../id/SECURITY.md) · [Italiano](../it/SECURITY.md) · [日本語](../ja/SECURITY.md) · [한국어](../ko/SECURITY.md) · [Nederlands](../nl/SECURITY.md) · [Polski](../pl/SECURITY.md) · [Português](../pt/SECURITY.md) · [Русский](../ru/SECURITY.md) · [Svenska](../sv/SECURITY.md) · [ไทย](../th/SECURITY.md) · [Türkçe](../tr/SECURITY.md) · [Українська](../uk/SECURITY.md) · [Tiếng Việt](../vi/SECURITY.md) · [中文](../zh/SECURITY.md)

---

# Bezpečnostní zásady

VDLiveUpdate (VDLU) aplikuje flashless root aktualizace na živý modul: zapisuje do
vlastního adresáře modulu a při startu vyměňuje knihovnu `.so` Zygisk, přičemž běží v root
kontextu modulu. Bezpečnost bereme vážně.

## Nahlášení zranitelnosti

- **Site:** https://vd171.ru
- **Site:** https://vd.priv8.ru
- **Issues:** https://github.com/VD171/VDLiveUpdate/issues
- **GitHub:** [@VD171](https://github.com/VD171)
- **XDA-Developers:** [@VD171](https://xdaforums.com/m/vd171.4699873/)
- **Telegram:** [@VD_Priv8](https://t.me/VD_Priv8)
- **Channel:** [@Priv8_VD](https://t.me/Priv8_VD)
- **Discord:** [@VD.Priv8](https://discord.com/users/1296831918989639721)
- **E-mail:** vd.priv8@pm.me

Přiložte jasný popis a pokud možno manifest nebo feed, který problém reprodukuje. Odpovíme
co nejdříve a uvedeme vás, pokud si to budete přát.

## Poznámky k rozsahu

- Aktualizace jsou content-addressed bloby plus `manifest.json` podepsaný pomocí ed25519.
  Zařízení ověřuje podpis pomocí vestavěného `ed25519-mini` (bez openssl na zařízení) a
  každý blob je před použitím zkontrolován proti svému `sha256`.
- Profil hardened (veřejné výchozí nastavení) vyžaduje platný podpis a blokuje downgrade.
  Výchozí verze ("from") je zdola omezena hodnotou `versionCode` nainstalovaného modulu
  (načtenou z `module.prop`), takže modul nikdy není vrácen za feed.
- Kořen důvěry (surový veřejný klíč ed25519 v `keyring/` a binárky ve `verify/`) je
  pouze-flash a nikdy není rotován přes síť. Producent jej vylučuje z feedu a engine
  ignoruje každou cestu `vdlu/` ve staženém plánu, takže uniklý podpisový klíč nemůže
  vyměnit verifikátor ani klíč a přetrvat jako root.
- Manifest platně podepsaný pro jiný modul nemůže zapisovat do adresáře jiného modulu.
  Podepsané pole `module` se musí rovnat `MODID` na zařízení (kontrola vazby mezi moduly) a
  každý zápis a mazání zůstává omezen na adresář modulu.
- Engine běží ve vlastním root kontextu modulu a nikdy jej neoslabuje. Nepřidává žádná
  oprávnění a neinterpoluje žádné pole manifestu do shellu, každá hodnota `path`, `sha256`,
  `mode` a `delete[]` je před použitím ověřena jako nepřátelský vstup.
- Postoj je fail-closed. Poškozená nebo neznámá hodnota `profile` nikdy neprojde k přijetí
  nepodepsaného obsahu (cokoli, co není přesně `trusted`, je považováno za `hardened`) a
  před přepsáním jakéhokoli souboru je zapsána záloha, takže neúspěšné apply nikdy nezničí
  nainstalovanou verzi.
- Úplný model důvěry, záruky fail-closed a podrobnosti o hardeningu najdete v
  [TRUST-MODEL.md](TRUST-MODEL.md).

<!-- doc-footer -->

---

> _Tato dokumentace byla vytvořena pomocí Claude (Anthropic) a spravuje ji VD171. Opravy a vylepšení jsou vítány, viz [CONTRIBUTING.md](CONTRIBUTING.md)._
