# Contributing

Bijdragen zijn welkom. VDLU is een flashloze, incrementele zelf-update-engine
gevendord in KernelSU- / APatch- / Magisk-modules. Deze pagina is de praktische dev-
workflow; voor hoe de stukken in elkaar passen, lees eerst [[Architecture]], [[Engine]] en
[[Producer]].

## Niets compileert

VDLU is scripts (POSIX sh, een beetje Python aan de release-zijde, vanilla JS voor de
WebUI), dus er is geen build-stap. Je verifieert een wijziging door de pijplijn
end-to-end te draaien en door elk stuk statisch te controleren.

## Naad-contract eerst

Het interface-contract tussen de componenten (de CLI-signaturen, bestandsnamen en
JSON-sleutels gedeeld door de engine, de producer en de WebUI) is de **wet van
convergentie**. Behandel het als onveranderlijk. Als je wijziging de
producer-naar-engine-naad raakt (manifestschema, journalschema, config-sleutels, de
handtekening-/canonicalisatieregel), **lijn eerst het interface-contract uit**, en
wijzig dan de code aan beide zijden om te matchen. Een wijziging aan één kant van de naad zonder
de andere breekt stilletjes adopters. Zie [[Producer]] voor de canonicalisatie-
regel waarover de signer en verifier het byte voor byte eens moeten zijn.

## Test end-to-end voor een PR

Draai de producer en de engine samen op een wegwerpboom, op dezelfde manier als een
release van een adopter:

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

Controleer daarna elk component statisch:

```sh
sh -n engine/*.sh            # POSIX sh syntax, must pass
node --check webui/vdlu.js   # WebUI JS syntax
```

En open `webui/demo.html` in een browser: het mockt de root-manager-brug
(`ksu.exec`), zodat je het Updates-paneel, de voortgangstoast, annuleren
en de herstartbanner kunt uitoefenen zonder apparaat. Zie [[WebUI]].

## Huisregels

- **POSIX sh op het apparaat.** Geen bashisms behalve `local`, en geen `jq`. Het moet
  draaien op toybox / busybox.
- **Beveiliging is niet onderhandelbaar.** Elk manifestveld is vijandige invoer;
  `validate_plan()` blijft fail-closed, en de private signeringssleutel raakt nooit
  CI of een apparaat aan. Versoepel geen controle om een test te laten slagen.
- **Rigoureus bij falen.** Houd de transactie hervatbaar: niets rapporteert "done"
  zonder een overeenkomende herhash, niets wordt overschreven zonder een back-up, en
  applies blijven atomair.
- **Altijd release-kwaliteit.** Houd commentaar beknopt; geen gratuite commentaren.
- **Eén logische wijziging per PR.** Zeg wat er veranderde en waarom.

## Issues indienen

Open een issue die beschrijft wat je deed, wat je verwachtte, en wat er gebeurde.
Voor een bug, voeg de module-id toe, het bronprofiel (`hardened` of `trusted`),
het `update.sh`-commando dat je draaide, en het relevante `journal.json` (het legt de
fase, toestand en fout vast). Voor een feature, zeg welk component het raakt (engine,
producer, of WebUI) zodat de naad-impact van tevoren duidelijk is.
