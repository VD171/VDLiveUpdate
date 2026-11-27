> **Languages:** [English](../../SECURITY.md) · [العربية](../ar/SECURITY.md) · [Čeština](../cs/SECURITY.md) · [Deutsch](../de/SECURITY.md) · [Español](../es/SECURITY.md) · [فارسی](../fa/SECURITY.md) · [Français](../fr/SECURITY.md) · [हिन्दी](../hi/SECURITY.md) · [Bahasa Indonesia](../id/SECURITY.md) · Italiano · [日本語](../ja/SECURITY.md) · [한국어](../ko/SECURITY.md) · [Nederlands](../nl/SECURITY.md) · [Polski](../pl/SECURITY.md) · [Português](../pt/SECURITY.md) · [Русский](../ru/SECURITY.md) · [Svenska](../sv/SECURITY.md) · [ไทย](../th/SECURITY.md) · [Türkçe](../tr/SECURITY.md) · [Українська](../uk/SECURITY.md) · [Tiếng Việt](../vi/SECURITY.md) · [中文](../zh/SECURITY.md)

---

# Politica di sicurezza

VDLiveUpdate (VDLU) applica aggiornamenti flashless con root a un modulo attivo: scrive
nella directory del modulo stesso e sostituisce una `.so` Zygisk al boot, eseguendo nel
contesto root del modulo. Prendiamo la sicurezza sul serio.

## Segnalare una vulnerabilità

- **Site:** https://vd171.ru
- **Site:** https://vd.priv8.ru
- **Issues:** https://github.com/VD171/VDLiveUpdate/issues
- **GitHub:** [@VD171](https://github.com/VD171)
- **XDA-Developers:** [@VD171](https://xdaforums.com/m/vd171.4699873/)
- **Telegram:** [@VD_Priv8](https://t.me/VD_Priv8)
- **Channel:** [@Priv8_VD](https://t.me/Priv8_VD)
- **Discord:** [@VD.Priv8](https://discord.com/users/1296831918989639721)
- **E-mail:** vd.priv8@pm.me

Includi una descrizione chiara e, se possibile, un manifest o un feed che riproduca il
problema. Risponderemo appena possibile e ti accrediteremo se lo desideri.

## Note sull'ambito

- Gli aggiornamenti sono blob content-addressed più un `manifest.json` firmato con ed25519.
  Il dispositivo verifica la firma con un `ed25519-mini` incorporato (senza openssl sul
  dispositivo), e ogni blob viene controllato rispetto al suo `sha256` prima di essere usato.
- Il profilo hardened (l'impostazione predefinita pubblica) richiede una firma valida e
  blocca il downgrade. La versione "di partenza" ha come limite inferiore il `versionCode`
  del modulo installato (letto da `module.prop`), quindi un modulo non viene mai riportato
  indietro rispetto al feed.
- La radice di fiducia (la chiave pubblica ed25519 raw del `keyring/` e i binari di
  `verify/`) è solo-flash e non viene mai ruotata via rete. Il producer la esclude dal feed
  e l'engine ignora ogni percorso `vdlu/` in un piano scaricato, quindi una chiave di firma
  trapelata non può sostituire il verificatore o la chiave e persistere come root.
- Un manifest validamente firmato per un altro modulo non può scrivere nella directory di
  un modulo diverso. Il campo `module` firmato deve essere uguale al `MODID` del dispositivo
  (verifica di vincolo tra moduli), e ogni scrittura ed eliminazione resta confinata alla
  directory del modulo.
- L'engine viene eseguito nel contesto root del modulo stesso e non lo indebolisce mai. Non
  aggiunge privilegi e non interpola alcun campo del manifest in una shell, ogni valore di
  `path`, `sha256`, `mode` e `delete[]` viene validato come input ostile prima dell'uso.
- La postura è fail-closed. Un valore di `profile` corrotto o sconosciuto non scivola mai
  nell'accettare contenuto non firmato (tutto ciò che non è esattamente `trusted` viene
  trattato come `hardened`), e un backup viene scritto prima che qualsiasi file venga
  sovrascritto, quindi un apply fallito non distrugge mai la versione installata.
- Vedi [TRUST-MODEL.md](TRUST-MODEL.md) per il modello di fiducia completo, le garanzie
  fail-closed e i dettagli di hardening.

<!-- doc-footer -->

---

> _Questa documentazione è stata generata con Claude (Anthropic) ed è gestita da VD171. Correzioni e miglioramenti sono benvenuti, vedi [CONTRIBUTING.md](CONTRIBUTING.md)._
