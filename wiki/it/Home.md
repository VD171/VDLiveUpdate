# VDLiveUpdate (VDLU)

**VDLU è un motore di self-update incrementale e flashless per moduli KernelSU / APatch / Magisk: un modulo installato aggiorna i propri file tramite un feed firmato, scaricando solo ciò che è cambiato e applicando gran parte di esso senza un riavvio.**

Un normale aggiornamento di modulo rispedisce di nuovo l'intero `.zip`, quindi poche righe modificate costano un re-download completo, e un manifest di aggiornamento statico può puntare solo a un singolo `zipUrl` (un solo flavor per ogni dispositivo). VDLU segue una strada diversa: calcola il diff fra l'albero effettivamente installato e un feed firmato e content-addressed, scarica solo i delta e li scrive in loco. Un'installazione full arm64 resta full arm64, un'installazione lite resta lite, e il modulo non viene mai riflashato.

VDLU è pensato per essere **vendorizzato** dentro un modulo, inserito in `<module>/vdlu/`. Non è un modulo a sé stante.

## Obiettivi

- **Self-update flashless.** Aggiornare in loco un modulo installato, over the air, senza root manager, senza riflashare lo `.zip` e senza perdere il flavor installato.
- **Incrementale per contenuto.** Trasferire solo i blob il cui contenuto è cambiato. Un feed content-addressed (`manifest.json` + `blobs/<sha256>`) fa sì che i file invariati o ripristinati non vengano mai riscaricati.
- **Reboot-free dove è sicuro.** Applicare i file ordinari dal vivo, immediatamente. Riservare un riavvio in staging solo per i pochi file che ne hanno davvero bisogno (un `.so`, un overlay `/system`, una `sepolicy.rule`).
- **Leggero sul dispositivo.** `sh` POSIX puro, niente `jq`, niente `bash`, niente `openssl` sul dispositivo. La verifica si appoggia a un `ed25519-mini` embedded; l'unico binario scaricato è un `curl` statico, usato solo per i feed `https`.
- **Fail-closed e onesto.** Ogni campo del manifest è trattato come input ostile e validato prima che qualsiasi cosa venga scaricata. Nulla viene mai riportato come "fatto" se un re-hash non lo dimostra, e nulla viene sovrascritto senza un backup prima.

## Peculiarità

Cosa rende VDLU diverso da un tipico client OTA:

- **Flashless e incrementale.** Diff / fetch / apply content-addressed con dedup: il dispositivo calcola il delta rispetto al feed firmato e scarica solo i blob mancanti.
- **Reboot-free dove possibile.** I file ordinari si applicano dal vivo; solo i file `.so`, gli overlay `/system` e i file `sepolicy.rule` vengono messi in staging e scambiati con un singolo riavvio. Vedi [[Reboot Handling]].
- **`sh` POSIX sul dispositivo.** Gira sotto toybox / busybox / mksh. Niente `jq` (un flattener `awk` in stile `gron` fa il parsing del JSON), niente `bash`ismi, nessun runtime pesante.
- **Verifica leggera.** Un `ed25519-mini` embedded verifica le firme. **Non c'è `openssl` sul dispositivo**; la chiave privata non tocca mai un dispositivo o la CI.
- **Sicurezza fail-closed.** `validate_plan()` rifiuta l'**intero** manifest su qualsiasi campo errato (path assoluto o con `..`, un `sha256` che non ha 64 caratteri esadecimali, un mode / class / encoding non valido). Due profili, `trusted` e `hardened`, con `hardened` fail-closed per inversione. Vedi [[Security and Trust Model]].
- **Riprendibile e atomico.** Un journal rende ogni transazione crash-safe; le scritture usano `rename` / `mv`; un backup viene preso prima di ogni sovrascrittura, così un apply fallito fa rollback invece di corrompere il modulo.

## Inizia da qui

| Se vuoi... | Vai a |
|---|---|
| Adottare VDLU nel tuo modulo, passo per passo | [[Quick Start]] |
| Capire l'intero sistema a colpo d'occhio | [[Architecture]] |
| Imparare il motore lato device (`update.sh`) | [[Engine]] |
| Costruire e firmare un feed sul tuo PC | [[Producer]] |
| Inserire il pannello Updates | [[WebUI]] |
| Leggere il modello di fiducia e la postura di sicurezza | [[Security and Trust Model]] |
| Vedere il layout di manifest e blob | [[Feed Format]] |
| Sapere cosa richiede un riavvio e perché | [[Reboot Handling]] |
| Porre una domanda comune | [[FAQ]] |
| Contribuire | [[Contributing]] |

## Link del progetto

- **Sorgente:** https://github.com/VD171/VDLiveUpdate
- **Canale (aggiornamenti):** @Priv8_VD https://t.me/Priv8_VD

VDLiveUpdate è un progetto indipendente e non ufficiale. "Android" è un marchio di Google LLC; "KernelSU", "Magisk" e "APatch" sono i marchi dei rispettivi autori. VDLU gira interamente sul tuo dispositivo e sul tuo host di release.
