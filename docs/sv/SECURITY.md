> **Languages:** [English](../../SECURITY.md) · [العربية](../ar/SECURITY.md) · [Čeština](../cs/SECURITY.md) · [Deutsch](../de/SECURITY.md) · [Español](../es/SECURITY.md) · [فارسی](../fa/SECURITY.md) · [Français](../fr/SECURITY.md) · [हिन्दी](../hi/SECURITY.md) · [Bahasa Indonesia](../id/SECURITY.md) · [Italiano](../it/SECURITY.md) · [日本語](../ja/SECURITY.md) · [한국어](../ko/SECURITY.md) · [Nederlands](../nl/SECURITY.md) · [Polski](../pl/SECURITY.md) · [Português](../pt/SECURITY.md) · [Русский](../ru/SECURITY.md) · Svenska · [ไทย](../th/SECURITY.md) · [Türkçe](../tr/SECURITY.md) · [Українська](../uk/SECURITY.md) · [Tiếng Việt](../vi/SECURITY.md) · [中文](../zh/SECURITY.md)

---

# Säkerhetspolicy

VDLiveUpdate (VDLU) tillämpar flashless root-uppdateringar på en aktiv modul: den skriver
till modulens egen katalog och byter ut en Zygisk-`.so` vid uppstart, och körs i modulens
root-kontext. Vi tar säkerhet på allvar.

## Rapportera en sårbarhet

- **Site:** https://vd171.ru
- **Site:** https://vd.priv8.ru
- **Issues:** https://github.com/VD171/VDLiveUpdate/issues
- **GitHub:** [@VD171](https://github.com/VD171)
- **XDA-Developers:** [@VD171](https://xdaforums.com/m/vd171.4699873/)
- **Telegram:** [@VD_Priv8](https://t.me/VD_Priv8)
- **Channel:** [@Priv8_VD](https://t.me/Priv8_VD)
- **Discord:** [@VD.Priv8](https://discord.com/users/1296831918989639721)
- **E-mail:** vd.priv8@pm.me

Inkludera en tydlig beskrivning och, om möjligt, ett manifest eller feed som återskapar
problemet. Vi svarar så snart vi kan och ger dig erkännande om du vill.

## Omfattningsanteckningar

- Uppdateringar är content-addressed blobbar plus en `manifest.json` signerad med ed25519.
  Enheten verifierar signaturen med en inbäddad `ed25519-mini` (ingen openssl på enheten),
  och varje blob kontrolleras mot sin `sha256` innan den används.
- Den hardened profilen (den publika standarden) kräver en giltig signatur och blockerar
  downgrade. "Från"-versionen begränsas nedåt av den installerade modulens `versionCode`
  (läst från `module.prop`), så att en modul aldrig återställs bakom feeden.
- Förtroenderoten (den råa ed25519-publika nyckeln i `keyring/` och binärerna i `verify/`)
  är endast-flash och roteras aldrig över nätet. Producenten utesluter den från feeden och
  engine ignorerar varje `vdlu/`-sökväg i en hämtad plan, så att en läckt signeringsnyckel
  inte kan byta ut verifieraren eller nyckeln och bevara root.
- Ett manifest som är giltigt signerat för en annan modul kan inte skriva till en annan
  moduls katalog. Det signerade fältet `module` måste vara lika med `MODID` på enheten
  (bindningskontroll mellan moduler), och varje skrivning och radering hålls begränsad till
  modulkatalogen.
- Engine körs i modulens egen root-kontext och försvagar den aldrig. Den lägger inte till
  några privilegier och interpolerar inget manifestfält i ett skal, varje värde för `path`,
  `sha256`, `mode` och `delete[]` valideras som fientlig indata före användning.
- Hållningen är fail-closed. Ett skadat eller okänt `profile`-värde faller aldrig igenom
  till att acceptera osignerat innehåll (allt som inte är exakt `trusted` behandlas som
  `hardened`), och en säkerhetskopia skrivs innan någon fil skrivs över, så att en
  misslyckad apply aldrig förstör den installerade versionen.
- Se [TRUST-MODEL.md](TRUST-MODEL.md) för den fullständiga förtroendemodellen,
  fail-closed-garantierna och hardening-detaljerna.

<!-- doc-footer -->

---

> _Denna dokumentation genererades med Claude (Anthropic) och underhålls av VD171. Rättelser och förbättringar välkomnas, se [CONTRIBUTING.md](CONTRIBUTING.md)._
