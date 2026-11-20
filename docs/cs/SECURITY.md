> **Languages:** [English](../SECURITY.md) · [العربية](../ar/SECURITY.md) · Čeština · [Deutsch](../de/SECURITY.md) · [Español](../es/SECURITY.md) · [فارسی](../fa/SECURITY.md) · [Français](../fr/SECURITY.md) · [हिन्दी](../hi/SECURITY.md) · [Bahasa Indonesia](../id/SECURITY.md) · [Italiano](../it/SECURITY.md) · [日本語](../ja/SECURITY.md) · [한국어](../ko/SECURITY.md) · [Nederlands](../nl/SECURITY.md) · [Polski](../pl/SECURITY.md) · [Português](../pt/SECURITY.md) · [Русский](../ru/SECURITY.md) · [Svenska](../sv/SECURITY.md) · [ไทย](../th/SECURITY.md) · [Türkçe](../tr/SECURITY.md) · [Українська](../uk/SECURITY.md) · [Tiếng Việt](../vi/SECURITY.md) · [中文](../zh/SECURITY.md)

---

# Bezpečnostní politika a model důvěry

VDLiveUpdate (VDLU) aplikuje **flashless root aktualizace** na živý modul: zapisuje
do `/data/adb/modules/<mod>` a swapuje Zygisk `.so` při bootu. Každé pole
staženého manifestu (`path`, `sha256`, `delete[]`, `mode`, ...) je **nepřátelský vstup** -
otrávený feed nebo MITM ho doručí. Tato stránka je model důvěry a politika odpovědného
zveřejnění. Pro úplný kontrakt costury viz [`INTERFACES.md`](INTERFACES.md),
a interní mechaniku engine/producer v [`ENGINE.md`](ENGINE.md) a
[`PRODUCER.md`](PRODUCER.md); wiki stránka **Security-and-Trust-Model** nese
stejný model pro čtenáře mimo repo.

## Podporované verze

Bezpečnostní opravy přistávají v nejnovějším `ENGINE_VERSION`; podepsaný manifest deklaruje
minimální engine, který potřebuje, přes `engine_min`, a engine na zařízení odmítne manifest,
který žádá víc, než implementuje. Od starších vendorovaných enginů se očekává, že udělají
**re-vendor**, aby pobraly opravu, ne že se budou patchovat na místě.

| ENGINE_VERSION | stav |
|---|---|
| 4 (aktuální) | podporováno - allowlist `key_id`, odmítnutí paths s dot-segmentem/trailing-slashem, stropy velikosti, lock v check-time |
| 3 | nahrazeno - default `hardened`, fail-closed `profile` inverzí, bind modul/MODID, blokace downgradu |
| <= 2 | nepodporováno - re-vendorovat aktuální engine |

Jakákoli změna ověřování enginu nebo apply logiky zvyšuje `ENGINE_VERSION`.

## Nahlášení zranitelnosti

Nahlas soukromě. **Neotvírej** veřejný issue, PR ani forum post kvůli bezpečnostnímu
bugu. Použij kontakty projektu (viz [`CONTRIBUTING.md`](../CONTRIBUTING.md)):

- Telegram: **@VD_Priv8** (https://t.me/VD_Priv8)
- Kanál: **@Priv8_VD** (https://t.me/Priv8_VD)
- E-mail: **vd.priv8@pm.me**

Prosím přilož verzi enginu, `profile` v použití, a manifest nebo feed, který
problém reprodukuje. Opravy se vydávají jako nový `ENGINE_VERSION` s položkou v
`CHANGELOG.md`; načasování zveřejnění zkoordinuj ve vlákně hlášení.

## Model důvěry

- **Oddělené (detached) ed25519 podpisy.** Producer podepisuje kanonický manifest na
  PC (openssl); zařízení ověřuje vestavěným `ed25519-mini` - **žádný openssl na
  zařízení**. Podepsaná zpráva je sha256 hex manifestu bez jeho pole `sig`
  (klíče seřazené, kompaktní, UTF-8), takže podpis a verify odvodí stejné bajty na dvou
  runtimech bez JSON knihovny na zařízení.
- **Keyring = RAW 32bajtové pubkeye**, flash-only. Keyring zařízení dodává `<key_id>.pub`
  jako holý 32bajtový klíč (nikdy PEM); `vdlu-pack` **vylučuje** keyring a
  `verify/` binárky z feedu, takže manifest nikdy nemůže přepsat kotvu důvěry
  na zařízení po síti.
- **Allowlist `key_id` pro module-update (fail-closed, před výběrem pubkey).** Keyring
  může legitimně nést víc než jeden klíč (například klíč fingerprint-feedu nižší
  důvěry vedle release klíče). Než se `<key_id>.pub` vůbec vybere, `verify_manifest`
  odmítne jakýkoli manifest, jehož `key_id` není v nakonfigurovaném allowlistu, v **obou**
  profiles, a zrcadlí vyřešenou množinu do `vdlu-verify` přes `VDLU_KEYID_ALLOW`. To
  uzavírá obchvat, kde by uniklý klíč nižší důvěry mohl jinak podepsat plnou flashless
  root aktualizaci. Bezpečné ve výchozím stavu, když `key_id` není nastaveno: keyring
  **s jedním klíčem** se automaticky připne na ten jeden klíč; **víceklíčový** keyring je odmítnut, dokud není `key_id`
  připnuto (oddělené čárkou pro rotaci).
- **Kořen důvěry fingerprint-feedu je oddělený, připnutý path** s vlastním klíčem; nikdy
  není dosažitelný skrze výše uvedený module-update path.
- **Baseline je lokální důvěryhodné seed.** `baseline.json` dorazí uvnitř flashnutého zipu -
  hranice důvěry instalace - takže je nepodepsaný a bez klíče a **neprochází** přes
  `vdlu-verify`; ověřuje se jen manifest **stažený** z feedu. To drží
  podepisovací klíč mimo CI.

## Fail-closed záruky

- **`validate_plan` běží před jakýmkoli fetchem nebo apply.** V `do_diff`, fail-closed,
  odmítne **celý** manifest, pokud je nějaký `path` absolutní, obsahuje segment `..` nebo `.`,
  končí na `/`, nebo drží řídicí znak; pokud nějaký `sha256` není
  `^[0-9a-f]{64}$`; nebo pokud je nějaký `mode`/`class`/`enc` neplatný. Žádné nepřátelské pole nedosáhne
  shellu, a `cmd_check` nenese žádnou `system()` interpolaci.
- **Zadržení path.** Každý zápis i mazání je omezen na `MODULE_DIR` přes
  `contained()` - apply, delete, i reboot `stage_file` procházejí stejnou stráží.
  Symlinky ve stromu producer přeskakuje (nikdy nevynesou obsah zvenčí).
- **Dva profiles, fail-closed inverzí.** `trusted` (soukromý, SSH-stageovaný zdroj) je
  **jediný** opt-in k best-effort verify; **jakákoli** jiná hodnota - včetně překlepu,
  koncové mezery/CR, nebo jiné velikosti písmen - je brána jako `hardened`, kde platný
  podpis je **povinný** a selhání abortuje. `sha256` každého blobu se kontroluje v
  obou profiles.
- **Podpis + hash před jakýmkoli spuštěním nástroje.** Stažený statický `curl` běží jako root, takže
  `install-tool` ověří podpis tools-manifestu (ed25519-mini, povinný v **jakémkoli**
  profile) a hash curlu **před** tím, než je nainstalován a spuštěn - sig+hash před
  execem uzavírá RCE.
- **Obnovitelná, pin-safe transakce.** Manifest v letu je připnutý v `target.json`;
  pád, ztráta sítě, nebo reboot se obnoví z journalu bez opětovného rozhodování o plánu.
  Downgrade je zablokován (monotónní `version`), podepsané pole `module` se musí rovnat
  `MODID`, a `delete[]` běží jen při `finalize_done` (`PENDING_REBOOT` nemaže
  nic). Nic není nikdy "hotovo" bez úplného přehašování; nic se nepřepisuje bez
  zálohy `rollback/<v>/` napřed.

## Zpevnění (defense in depth)

- **Stropy velikosti.** Manifest, tools-manifest, a download path `wget`/`head -c`
  bez curlu jsou všechny omezeny před čtením (anti-OOM / anti-flood). Blob selže
  ve své fázi po 3 pokusech.
- **Lock v check-time.** `check` bere mkdir-lock před přestavbou svého pracovního adresáře, takže
  souběžný run proti němu nemůže závodit.
- **Zadržení stagingu.** `stage_file` má stejnou `contained()` stráž jako primitiva
  živého apply, takže ani stageovaný reboot-hard path nemůže uniknout z `MODULE_DIR`.
- **TLS je defense in depth, ne kořen důvěry.** Statický curl používá mbedTLS s
  Android trust storem (`--capath`, override `ca_path`); zárukou integrity je
  ed25519 podpis, kontrola certu je druhá vrstva.

## Viz také

- [`INTERFACES.md`](INTERFACES.md) - neměnný kontrakt costury (§5 config, §6 podpis, §11 toolchain).
- [`ENGINE.md`](ENGINE.md) - engine na straně zařízení a jeho stavový automat.
- [`PRODUCER.md`](PRODUCER.md) - packing, podepisování, kanonikalizace, a rotace klíčů.
- Wiki: **Security-and-Trust-Model**.

<!-- doc-footer -->

---

> _Tato dokumentace byla vytvořena pomocí Claude (Anthropic) a spravuje ji VD171. Opravy a vylepšení jsou vítány; viz [CONTRIBUTING.md](CONTRIBUTING.md)._
