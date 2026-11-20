> **Languages:** [English](../SECURITY.md) · [العربية](../ar/SECURITY.md) · [Čeština](../cs/SECURITY.md) · [Deutsch](../de/SECURITY.md) · [Español](../es/SECURITY.md) · [فارسی](../fa/SECURITY.md) · [Français](../fr/SECURITY.md) · [हिन्दी](../hi/SECURITY.md) · [Bahasa Indonesia](../id/SECURITY.md) · Italiano · [日本語](../ja/SECURITY.md) · [한국어](../ko/SECURITY.md) · [Nederlands](../nl/SECURITY.md) · [Polski](../pl/SECURITY.md) · [Português](../pt/SECURITY.md) · [Русский](../ru/SECURITY.md) · [Svenska](../sv/SECURITY.md) · [ไทย](../th/SECURITY.md) · [Türkçe](../tr/SECURITY.md) · [Українська](../uk/SECURITY.md) · [Tiếng Việt](../vi/SECURITY.md) · [中文](../zh/SECURITY.md)

---

# Policy di sicurezza e modello di fiducia

VDLiveUpdate (VDLU) applica **aggiornamenti root flashless** a un modulo vivo: scrive
in `/data/adb/modules/<mod>` e fa lo swap di una `.so` Zygisk all'avvio. Ogni campo di
un manifest recuperato (`path`, `sha256`, `delete[]`, `mode`, ...) è **input ostile** - un
feed avvelenato o un MITM lo consegna. Questa pagina è il modello di fiducia e la policy
di responsible disclosure. Per il contratto di costura completo vedi
[`INTERFACES.md`](INTERFACES.md), e gli interni di engine/producer in
[`ENGINE.md`](ENGINE.md) e [`PRODUCER.md`](PRODUCER.md); la pagina wiki
**Security-and-Trust-Model** porta lo stesso modello per i lettori fuori dal repo.

## Versioni supportate

Le correzioni di sicurezza arrivano nell'ultima `ENGINE_VERSION`; un manifest firmato
dichiara l'engine minimo di cui ha bisogno tramite `engine_min`, e l'engine on-device
rifiuta un manifest che chiede più di quanto implementa. Gli engine vendorizzati più
vecchi devono fare **re-vendor** per ottenere una correzione, non essere back-patchati
in place.

| ENGINE_VERSION | stato |
|---|---|
| 4 (corrente) | supportato - allowlist `key_id`, rifiuto dei path con dot-segment/trailing-slash, size cap, lock in fase di check |
| 3 | superato - default `hardened`, `profile` fail-closed per inversione, bind module/MODID, blocco del downgrade |
| <= 2 | non supportato - fai il re-vendor dell'engine corrente |

Qualsiasi modifica alla verifica dell'engine o alla logica di apply fa il bump di
`ENGINE_VERSION`.

## Segnalare una vulnerabilità

Segnala privatamente. **Non** aprire una issue pubblica, PR o post sul forum per un bug
di sicurezza. Usa i contatti del progetto (vedi [`CONTRIBUTING.md`](../CONTRIBUTING.md)):

- Telegram: **@VD_Priv8** (https://t.me/VD_Priv8)
- Canale: **@Priv8_VD** (https://t.me/Priv8_VD)
- E-mail: **vd.priv8@pm.me**

Includi la versione dell'engine, il `profile` in uso, e un manifest o feed che riproduce
il problema. Le correzioni vengono spedite come una nuova `ENGINE_VERSION` con una voce
nel `CHANGELOG.md`; coordina i tempi della disclosure sul thread della segnalazione.

## Modello di fiducia

- **Firme ed25519 detached.** Il producer firma il manifest canonico sul PC (openssl);
  il dispositivo verifica con l'`ed25519-mini` incorporato - **niente openssl sul
  dispositivo**. Il messaggio firmato è lo sha256 esadecimale del manifest senza il suo
  campo `sig` (chiavi ordinate, compatto, UTF-8), così sign e verify derivano gli stessi
  byte su due runtime senza una libreria JSON sul dispositivo.
- **Keyring = pubkey RAW da 32 byte**, solo-flash. Il keyring del dispositivo spedisce
  `<key_id>.pub` come la chiave grezza da 32 byte (mai il PEM); `vdlu-pack` **esclude** il
  keyring e i binari `verify/` dal feed, così un manifest non può mai riscrivere l'ancora
  di fiducia on-device via cavo.
- **Allowlist `key_id` di module-update (fail-closed, prima della selezione della
  pubkey).** Un keyring può legittimamente portare più di una chiave (per esempio una
  chiave di fingerprint-feed a fiducia inferiore accanto alla chiave di release). Prima
  che `<key_id>.pub` venga mai selezionata, `verify_manifest` rifiuta qualsiasi manifest
  il cui `key_id` non sia nell'allowlist configurata, in **entrambi** i profiles, e
  replica l'insieme risolto in `vdlu-verify` tramite `VDLU_KEYID_ALLOW`. Questo chiude un
  bypass per cui una chiave a fiducia inferiore trapelata potrebbe altrimenti firmare un
  aggiornamento root flashless completo. Sicuro di default quando `key_id` non è
  impostato: un keyring a **chiave singola** si auto-fissa su quell'unica chiave; un
  keyring **multichiave** è rifiutato finché `key_id` non è fissato (separate da virgola
  per la rotazione).
- **La radice di fiducia del fingerprint-feed è un path separato e fissato** con la
  propria chiave; non è mai raggiungibile tramite il path di module-update qui sopra.
- **La baseline è un seme locale fidato.** `baseline.json` arriva dentro lo zip flashato -
  il confine di fiducia dell'installazione - quindi è non firmata e senza chiave e **non**
  passa per `vdlu-verify`; solo un manifest **recuperato** dal feed viene verificato.
  Questo tiene la chiave di firma fuori dalla CI.

## Garanzie fail-closed

- **`validate_plan` gira prima di ogni fetch o apply.** In `do_diff`, fail-closed,
  rifiuta il manifest **intero** se un qualsiasi `path` è assoluto, contiene un segmento
  `..` o `.`, finisce in `/`, o contiene un carattere di controllo; se un qualsiasi
  `sha256` non è `^[0-9a-f]{64}$`; o se un qualsiasi `mode`/`class`/`enc` è invalido.
  Nessun campo ostile raggiunge una shell, e `cmd_check` non porta alcuna interpolazione
  `system()`.
- **Contenimento del path.** Ogni scrittura ed eliminazione è confinata in `MODULE_DIR`
  tramite `contained()` - apply, delete, e lo `stage_file` del reboot passano tutti per lo
  stesso guard. I symlink nell'albero vengono saltati dal producer (non fanno mai
  trapelare contenuto da fuori).
- **Due profiles, fail-closed per inversione.** `trusted` (privato, sorgente SSH-staged)
  è l'**unico** opt-in al verify best-effort; **qualsiasi** altro valore - incluso un
  typo, uno spazio/CR finale, o un case diverso - viene trattato come `hardened`, dove una
  firma valida è **obbligatoria** e un fallimento aborta. Lo `sha256` di ogni blob viene
  controllato in entrambi i profiles.
- **Firma + hash prima di ogni exec di tool.** Il `curl` statico recuperato gira come
  root, quindi `install-tool` verifica la firma del tools-manifest (ed25519-mini,
  obbligatoria in **qualsiasi** profile) e l'hash del curl **prima** che venga installato
  ed eseguito - sig+hash prima dell'exec chiude la RCE.
- **Transazione ripristinabile e pin-safe.** Il manifest in volo è fissato in
  `target.json`; un crash, una perdita di rete, o un reboot riprende dal journal senza
  ri-decidere il piano. Il downgrade è bloccato (`version` monotona), il campo `module`
  firmato deve essere uguale a `MODID`, e `delete[]` gira solo a `finalize_done` (un
  `PENDING_REBOOT` non elimina nulla). Niente è mai "concluso" senza un re-hash completo;
  niente viene sovrascritto senza prima un backup `rollback/<v>/`.

## Hardening (difesa in profondità)

- **Size cap.** Il manifest, il tools-manifest, e il path di download senza curl
  `wget`/`head -c` sono tutti limitati prima di essere letti (anti-OOM / anti-flood). Un
  blob fallisce la sua fase dopo 3 tentativi.
- **Lock in fase di check.** `check` prende il lock-mkdir prima di ricostruire la sua work
  dir, così un'esecuzione concorrente non può entrare in race con essa.
- **Contenimento dello staging.** `stage_file` ha lo stesso guard `contained()` delle
  primitive di apply live, così nemmeno un path reboot-hard in stage può sfuggire a
  `MODULE_DIR`.
- **Il TLS è difesa in profondità, non la radice di fiducia.** Il curl statico usa
  mbedTLS con il trust store di Android (`--capath`, override `ca_path`); la garanzia di
  integrità è la firma ed25519, il controllo del cert è un secondo livello.

## Vedi anche

- [`INTERFACES.md`](INTERFACES.md) - il contratto di costura immutabile (§5 config, §6 firma, §11 toolchain).
- [`ENGINE.md`](ENGINE.md) - l'engine device-side e la sua macchina a stati.
- [`PRODUCER.md`](PRODUCER.md) - packing, firma, canonicalizzazione, e rotazione delle chiavi.
- Wiki: **Security-and-Trust-Model**.

<!-- doc-footer -->

---

> _Questa documentazione è stata generata con Claude (Anthropic) ed è gestita da VD171. Correzioni e miglioramenti sono benvenuti; vedi [CONTRIBUTING.md](CONTRIBUTING.md)._
