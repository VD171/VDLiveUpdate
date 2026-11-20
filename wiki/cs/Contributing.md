# Contributing

Příspěvky jsou vítány. VDLU je bezflashový, inkrementální engine pro samoaktualizaci,
vendorovaný do modulu KernelSU / APatch / Magisk. Tato stránka je praktický vývojářský
workflow; pro to, jak kusy do sebe zapadají, přečtěte si nejprve [[Architecture]], [[Engine]] a
[[Producer]].

## Nic se nekompiluje

VDLU jsou skripty (POSIX sh, trocha Pythonu na straně release, vanilla JS pro
WebUI), takže není žádný build krok. Změnu ověříte spuštěním pipeline
end-to-end a statickou kontrolou každého kusu.

## Nejprve kontrakt svaru

Interface kontrakt mezi komponentami (CLI signatury, názvy souborů a
JSON klíče sdílené enginem, producerem a WebUI) je **zákon
konvergence**. Považujte ho za neměnný. Pokud se vaše změna dotýká
svaru producer-engine (schéma manifestu, schéma žurnálu, konfigurační klíče,
pravidlo podpisu/kanonizace), **nejprve zarovnejte interface kontrakt**, pak
změňte kód na obou stranách, aby odpovídal. Změna na jedné straně svaru bez
druhé tiše rozbije přejímatele. Viz [[Producer]] pro pravidlo kanonizace,
na kterém se podepisovač a ověřovač musí shodnout bajt po bajtu.

## Testování end-to-end před PR

Spusťte producer a engine společně na jednorázovém stromu, stejně jako to dělá
release přejímatele:

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

Pak staticky zkontrolujte každou komponentu:

```sh
sh -n engine/*.sh            # POSIX sh syntax, must pass
node --check webui/vdlu.js   # WebUI JS syntax
```

A otevřete `webui/demo.html` v prohlížeči: napodobuje most root manageru
(`ksu.exec`), takže můžete vyzkoušet panel Updates, toast postupu, zrušení
a banner restartu bez zařízení. Viz [[WebUI]].

## Domácí pravidla

- **POSIX sh na zařízení.** Žádné bashismy nad rámec `local` a žádné `jq`. Musí to
  běžet na toybox / busybox.
- **Bezpečnost je neměnná.** Každé pole manifestu je nepřátelský vstup;
  `validate_plan()` zůstává fail-closed a privátní podpisový klíč se nikdy nedotkne
  CI ani zařízení. Neuvolňujte kontrolu, aby prošel test.
- **Přísnost při selhání.** Udržujte transakci obnovitelnou: nic nehlásí "done"
  bez odpovídajícího opětovného zahashování, nic se nepřepisuje bez zálohy a
  aplikace zůstávají atomické.
- **Vždy release kvalita.** Udržujte komentáře stručné; žádné zbytečné komentáře.
- **Jedna logická změna na PR.** Řekněte, co se změnilo a proč.

## Podávání issues

Otevřete issue popisující, co jste udělali, co jste očekávali a co se stalo.
Pro bug uveďte id modulu, zdrojový profil (`hardened` nebo `trusted`),
příkaz `update.sh`, který jste spustili, a relevantní `journal.json` (zaznamenává
fázi, stav a chybu). Pro funkci řekněte, které komponenty se dotýká (engine,
producer nebo WebUI), aby byl dopad na svar jasný předem.
