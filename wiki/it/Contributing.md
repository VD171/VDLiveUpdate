# Contributing

I contributi sono benvenuti. VDLU è un motore di self-update incrementale e flashless
vendorizzato nei moduli KernelSU / APatch / Magisk. Questa pagina è il workflow pratico di
sviluppo; per come i pezzi si incastrano, leggi prima [[Architecture]], [[Engine]] e
[[Producer]].

## Niente viene compilato

VDLU è fatto di script (`sh` POSIX, un po' di Python sul lato release, JS vanilla per la
WebUI), quindi non c'è build step. Verifichi una modifica eseguendo la pipeline
end-to-end e facendo lo static-check di ogni pezzo.

## Prima il contratto della cucitura

Il contratto di interfaccia fra i componenti (le firme CLI, i nomi di file e le
chiavi JSON condivise da engine, producer e WebUI) è la **legge della
convergenza**. Trattalo come immutabile. Se la tua modifica tocca la
cucitura producer-engine (schema del manifest, schema del journal, chiavi di config, la
regola di firma/canonicalizzazione), **allinea prima il contratto di interfaccia**, poi
cambia il codice su entrambi i lati per farlo combaciare. Una modifica su un lato della cucitura senza
l'altro rompe silenziosamente gli adopter. Vedi [[Producer]] per la regola di canonicalizzazione
su cui signer e verificatore devono concordare byte-per-byte.

## Testa end-to-end prima di una PR

Esegui il producer e l'engine insieme su un albero usa-e-getta, nello stesso modo in cui
la release di un adopter fa:

```sh
# 1. a signing key
producer/vdlu-keygen demo /tmp/k

# 2. pack a module tree into a feed
producer/vdlu-pack /tmp/tree /tmp/feed demo 1 --version-name v1

# 3. sign the manifest in place
producer/vdlu-sign /tmp/feed/manifest.json /tmp/k/demo.pem demo

# 4. verify the manifest the way the device will (RAW 32B keyring)
engine/vdlu-verify /tmp/feed/manifest.json /tmp/keyring

# 5. drive the engine against the feed (source=file:///tmp/feed in the config)
VDLU_DIR=... MODULE_DIR=... MODID=demo sh engine/update.sh check   # then run / boot
```

Poi fai lo static-check di ogni componente:

```sh
sh -n engine/*.sh            # POSIX sh syntax, must pass
node --check webui/vdlu.js   # WebUI JS syntax
```

E apri `webui/demo.html` in un browser: simula il bridge del root manager
(`ksu.exec`), così puoi esercitare il pannello Updates, il toast di avanzamento, il cancel
e il banner di riavvio senza dispositivo. Vedi [[WebUI]].

## Regole della casa

- **`sh` POSIX sul dispositivo.** Nessun bashismo oltre a `local`, e niente `jq`. Deve
  girare su toybox / busybox.
- **La sicurezza non è negoziabile.** Ogni campo del manifest è input ostile;
  `validate_plan()` resta fail-closed, e la chiave di firma privata non tocca mai
  la CI o un dispositivo. Non allentare un controllo per far passare un test.
- **Rigore sul fallimento.** Mantieni la transazione riprendibile: nulla riporta "done"
  senza un re-hash corrispondente, nulla viene sovrascritto senza un backup, e gli
  apply restano atomici.
- **Sempre qualità da release.** Mantieni i commenti concisi; nessun commento gratuito.
- **Una modifica logica per PR.** Di' cosa è cambiato e perché.

## Aprire issue

Apri una issue descrivendo cosa hai fatto, cosa ti aspettavi, e cosa è successo.
Per un bug, includi l'id del modulo, il profilo della sorgente (`hardened` o `trusted`),
il comando `update.sh` che hai eseguito, e il `journal.json` rilevante (registra la
fase, lo stato e l'errore). Per una feature, di' quale componente tocca (engine,
producer, o WebUI) così l'impatto sulla cucitura è chiaro fin da subito.
