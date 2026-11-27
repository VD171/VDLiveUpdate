# Engine

Engine je strana VDLU na zařízení: část, která běží na telefonu, rozhodne, co se změnilo, stáhne to a aplikuje. Je to jediný POSIX shellový skript, `engine/update.sh`, plus malý kontrolér podpisu, `engine/vdlu-verify`. Oba jsou vendorovány do hostitelského modulu v `<module>/vdlu/` a spouštěny rootem.

Celý engine je postaven kolem jedné myšlenky: aktualizace je **obnovitelná transakce**. Pokud se telefon restartuje, zabije nebo ztratí síť v půlce, příští běh naváže přesně tam, kde skončil, a modul nikdy nezůstane napůl aplikovaný, zatímco předstírá, že je hotový.

Pokud chcete nejprve velký obraz, viz [[Architecture]]. Pro to, jak se aktualizace vyhýbají restartu, kdykoli mohou, viz [[Reboot Handling]].

## Napsáno pro zařízení, ne pro váš laptop

`update.sh` je čistě POSIX `sh`. Běží pod mksh, busybox nebo toybox, bez funkcí jen pro bash, a projde `sh -n`. To je důležité, protože prostředí na rootnutém Android zařízení je malé a přísné.

Zejména není žádné `jq`. VDLU parsuje `manifest.json` malým gron-podobným flattenerem napsaným v `awk`: prochází JSON znak po znaku a vydá jeden řádek `path<TAB>value` na list (například `files/0/sha256<TAB>ab..` nebo `version<TAB>6`). Shell pak čte tyto řádky pomocí `grep` a `cut`. Funguje to na kompaktním i pěkně formátovaném JSON a nikdy nevolá nástroj pro JSON, který tam není.

Engine závisí jen na tom, co toybox již dodává (`sha256sum`, `gzip`/`gunzip`, `base64`, `date`), na vestavěném ověřovači `ed25519-mini` a, pro `https://` feedy, na malém statickém `curl`, které se jednou stáhne a ověří. `file://` feed nepotřebuje žádné `curl`.

## Šest příkazů

Engine vyvoláte s cestami modulu v prostředí a jedním příkazem:

```sh
VDLU_DIR=/data/adb/<mod>/vdlu MODULE_DIR=/data/adb/modules/<mod> MODID=<mod> \
  sh "$MODULE_DIR/vdlu/update.sh" <cmd>
```

Návratový kód `0` znamená úspěch; jakýkoli jiný kód znamená chybu, s důvodem vypsaným na stderr.

| Příkaz | Co dělá |
|---|---|
| `check` | Diff jen pro čtení. Stáhne manifest, porovná ho s nainstalovaným a vypíše jednořádkové JSON shrnutí: `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`. Na disku nic nemění. Pokud je zařízení novější než feed (zablokovaný downgrade), nahlásí `{"update":false,"ahead":true,...}` s návratem `0`, ne chybu. |
| `run` | Úplný živý cyklus: DIFF, FETCH, APPLY, COMMIT. Aplikuje každý živý soubor okamžitě a inscenuje těch několik souborů třídy reboot. Respektuje `cancel`. Zapisuje postup do `journal.json`. |
| `resume` | Pokračuje v přerušené transakci, začíná od fáze, ve které byla. Idempotentní. **Nevymění** inscenované `.so` (to je vyhrazeno pro `boot`). |
| `boot` | Pre-zygote cesta. Provede `resume` a pak vymění všechny inscenované soubory `*.vdlu-new` na místo, čímž uzavře `PENDING_REBOOT` na `DONE`. Pokud není žádná čekající transakce, spustí čerstvý cyklus a aplikuje vše, včetně `.so`, v tomto jediném bootu. |
| `status` | Vypíše `journal.json`, nebo `{"state":"idle"}`, když nic neprobíhá. |
| `cancel` | Vytvoří marker `cancel`. Probíhající `run` se čistě zastaví v příštím bezpečném bodě. |

Příkaz `check` je záměrně levný, aby vám UI mohlo říct, že aktualizace existuje, na jakékoli síti. Samotné stažení je omezeno zvlášť (viz fáze fetch níže).

## Transakce, krok za krokem

Každý `run` prochází pevným stavovým automatem, zaznamenaným v `journal.json`, takže WebUI (a vy) ho můžete sledovat:

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)
```

**DIFF.** Engine stáhne `manifest.json`, ověří každé pole (viz níže a [[Security and Trust Model]]) a porovná podepsaný cílový strom proti `current.json`, manifestu již nainstalované verze. Výsledkem je plán po souborech zapsaný do `plan.tsv`: jeden řádek na soubor, nesoucí jeho třídu, cílový hash, mód a stav postupu. Soubory již na cílovém hashi se označí k přeskočení.

**FETCH.** Pro každý ještě potřebný soubor engine stáhne jeho obsahově adresovaný blob z `<source>/blobs/<sha>` (nebo `<sha>.gz`, když je komprimovaný) do souboru `.part`. Pokud je blob gzipovaný, dekomprimuje se, pak se jeho SHA-256 zkontroluje proti manifestu. Jen při shodě se atomicky `mv`-ne do `blobs/<sha>`. Blob již v cache se správným hashem se zcela přeskočí a nezměněný lokální soubor může nasadit cache bez jakéhokoli stažení. Tři selhání na stejném blobu fázi přeruší, aniž by se cokoli aplikovalo. Fáze dosáhne `FETCHED` až jakmile je každý blob v plánu přítomný a ověřený. Pro [[Feed Format]], ze kterého tyto bloby pocházejí, viz onu stránku. Při nastavení toolchainu engine loguje vyřešenou TLS důvěru - cestu k CA a zda je čitelná, plus velikost bundlu a počet certifikátů - takže curl `rc 77` při bootu je v `boot.log` samovysvětlující (rozliší prázdný trust store od nečitelného, případ SELinux kontextu při bootu).

Fetch je omezen síťovou politikou: feed může být omezen jen na Wi-Fi, jen na mobilní data nebo na jakoukoli síť. Když aktuální síť není povolena, fetch neselže; vstoupí do neškodného stavu `DEFERRED`, drží plán a cíl připnutý a obnoví se při příští kontrole nebo bootu, jakmile se objeví správná síť. Mezitím se nespotřebují žádná data.

**APPLY.** Vstupuje se do něj jen z `FETCHED`. Pro každý soubor engine jedná podle třídy:

- soubory `live` a `soft`: zálohuj aktuální soubor do `rollback/<version>/<path>`, zapiš nový obsah do sourozence `.vdlu-tmp`, `chmod` ho, ověř jeho hash, pak atomicky `rename` přes cíl. Soubor již na cílovém hashi se přeskočí.
- soubory `reboot` (`.so`, overlay `/system`, `sepolicy.rule`): materializuj do `staged/<path>.vdlu-new`. Živý inode se zde nikdy nedotýká. Viz [[Reboot Handling]].
- mazání: zálohuj, pak odstraň. Mazání se aplikují až úplně na konci, při čistém `DONE`, nikdy zatímco restart stále čeká.

**COMMIT.** Engine znovu zahashuje každý živý a soft soubor, kterého se dotkl. Jen když všechny souhlasí, zapíše `current.json`, čímž učiní novou verzi základem diffu. Pokud byl inscenován nějaký soubor třídy reboot, stav se stane `PENDING_REBOOT` místo `DONE`; výměna a finální opětovné ověření se stanou později pod příkazem `boot`.

## Bezpečné z konstrukce

Záruky, které činí bezpečným spouštět to bez dozoru:

- **Nic se neoznačí `DONE` bez odpovídajícího opětovného zahashování.** `DONE` se dosáhne až poté, co byl každý aplikovaný soubor přečten zpět a jeho SHA-256 porovnán s manifestem. Inscenovaný soubor reboot vynutí `PENDING_REBOOT`, nikdy falešné `DONE`.
- **Nic se neztrácí.** Každý soubor se zálohuje do `rollback/<version>/` dříve, než se přepíše, a uchovávají se poslední tři verze. Pokud aplikace selže, živé soubory se vrátí ze zálohy; modul nikdy nezůstane napůl aplikovaný, zatímco o tom lze. `apply_live` okamžitě přeruší, pokud krok zálohy selže, místo přepsání bez cesty zpět.
- **Vše je atomické.** Nový obsah přistane přes `rename`/`mv` přes cíl, takže čtenář vidí vždy buď starý nebo nový soubor, nikdy oříznutý zápis.
- **Obnovitelné po pádu nebo zabití.** Pád, ztráta sítě nebo restart v půlce zanechá platný žurnál; `resume` (nebo `boot`) pokračuje od zaznamenané fáze. Návrh předpokládá, že bude přerušeno.
- **Degraduje čistě.** Chybějící binární soubor, vypadlá síť nebo plný disk vyprodukuje jasnou chybu na stderr a `state:ERROR` v žurnálu, aniž by poškodil modul.
- **Kotva důvěry je vyloučena (`ENGINE_VERSION` 5).** Engine ignoruje každou cestu `vdlu/` ve staženém plánu - své vlastní `update.sh`, `vdlu-verify`, binárky `verify/`, keyring a config - takže feed nikdy nemůže vyměnit ověřovač ani podepisovací klíč po síti; kotva se mění jen úplným podepsaným re-flashem. Viz [[Security and Trust Model]].
- **Update se odloží, dokud je modul zaneprázdněný.** S opt-in `apply_busy_file` nastaveným na absolutní cestu, které se hostitelský modul dotýká během svých vlastních operací (například běžící záloha), APPLY čeká, dokud ta cesta existuje, takže se soubory nikdy nevymění uprostřed operace; bloby jsou již stažené, takže další spoušť aplikuje bez opětovného stahování.
- **Stropy velikosti.** Soubor je omezen na **128 MiB** a manifest na **2 MiB**, vynucené před čtením obou v `update.sh` i `vdlu-verify` (anti dekompresní bomba / anti-OOM).
- **Modul, který je napřed před feedem, se nikdy nevrací zpět (`ENGINE_VERSION` 7).** Živě nainstalovaný `versionCode`, načtený z vlastního `module.prop` modulu, tvoří spodní hranici verze "from", takže zařízení ručně aktualizované za zastaralý feed je čteno jako *napřed*: downgrade stráž vrací neškodný výsledek, bez plánu a bez návratu. `boot` také sám opravuje stávající instalaci - uložený plán, jehož target je pod nainstalovanou verzí, nebo zastaralý journal s `target <= 0` (`ENGINE_VERSION` 6), je vyčištěn před jakýmkoli resume.

## Zámek

Jen jedna transakce se smí dotknout stavu najednou. `flock` není na toybox spolehlivé, takže VDLU serializuje adresářovým zámkem: `mkdir "$VDLU_DIR/lock.d"` uspěje přesně pro jednoho volajícího a selže pro zbytek, což je atomické na jakémkoli rozumném souborovém systému. Zastaralý zámek zanechaný mrtvým procesem se obnoví kontrolou zaznamenaného PID.

Trpělivý opakovaný pokus při bootu (použitý, když je zařízení při bootu offline) tento zámek **nedrží**, zatímco čeká. Získává a uvolňuje ho mezi pokusy, takže ruční `run` nikdy není blokován bootem, který čeká na síť, a nikdy nedrží wakelock. Šetrný k baterii z návrhu. Více o tom v [[Reboot Handling]].

## Kontrola podpisu: `vdlu-verify`

`vdlu-verify` je kontrolér podpisu na zařízení, záměrně držen štíhlý:

```
vdlu-verify <manifest.json> <keyring_dir>
```

Návrat `0` znamená, že podpis manifestu je platný proti veřejnému klíči keyringu, jehož id odpovídá `key_id` manifestu; jakýkoli jiný kód je zamítnutí.

Co ho činí štíhlým, je, že nepoužívá **žádné `openssl` na zařízení**. Čte veřejný klíč keyringu jako **syrový 32-bajtový** soubor, kanonizuje manifest (text manifestu s odstraněným polem `sig`), zahashuje ho pomocí toybox `sha256sum`, dekóduje podpis z base64 a předá syrový klíč, zprávu a 64-bajtový podpis vestavěnému bináru `ed25519-mini`. Kontrolér také odmítne cokoli chybného dříve, než vůbec ověří: chybějící nebo prázdný `key_id` či `sig`, `key_id` obsahující oddělovače cest, veřejný klíč, který není přesně 32 bajtů, nebo podpis, který není přesně 64 bajtů.

Než vůbec vybere klíč, engine vynucuje **allowlist `key_id`**: `key_id` manifestu musí být jeden z těch, kterým konfigurace povoluje podepsat *aktualizaci modulu*, a klíč, který je pouze přítomen v keyringu, ale není na allowlistu, je odmítnut dříve, než je jeho pubkey vůbec načten. Keyring s jediným klíčem automaticky připne tento jeden klíč bez konfigurace; keyring s více klíči musí připnout `key_id`, jinak engine selže fail-closed. Povolená množina se předává do `vdlu-verify` jako `VDLU_KEYID_ALLOW` a platí v obou profilech. To brání klíči nižší důvěry, jako je klíč fingerprint feedu sdílející keyring, podepsat plnou root aktualizaci; samostatný fingerprint feed si drží vlastní připnutý klíč, `FEED_KEY_ID`. Úplný příběh je v [[Security and Trust Model]].

Kanonizace je bajt po bajtu identická s podepisovačem produceru, což je to, co činí podpis ověřitelným napříč nástroji. Odpovídající privátní klíč se nikdy nedotkne zařízení ani CI; vestavěn je jen syrový veřejný klíč. Úplný příběh důvěry, dva profily a proč je `hardened` fail-closed inverzí, jsou v [[Security and Trust Model]].

Engine volá `vdlu-verify` během fáze diff. Pod profilem `hardened` neúspěšné ověření přeruší celou aktualizaci; pod `trusted` je ověření best-effort, ale hash každého blobu se stále vždy kontroluje, takže poškozený obsah se zachytí bez ohledu na profil.

## Stav na disku

Všechen stav enginu žije v `$VDLU_DIR` (mimo adresář modulu), takže samotný strom modulu drží vždy jen hotové soubory:

| Cesta | Role |
|---|---|
| `config` | nastavení key=value (source, profil, kanál, síťová politika, opakování bootu) |
| `current.json` | manifest aktivní verze; to je základ diffu. Nepřítomnost znamená nikdy neaktualizováno |
| `target.json` | připnutý manifest probíhající transakce. Jeho přítomnost značí aktivní transakci; stane se `current.json` při `DONE` |
| `plan.tsv` / `plan.del` | plán a postup po souborech a seznam cest ke smazání |
| `journal.json` | postup pro WebUI, přepsán při každé změně stavu |
| `blobs/<sha256>` | cache ověřeného, dekomprimovaného originálního obsahu |
| `rollback/<version>/<path>` | zálohy přepsaných souborů; uchovávají se poslední tři verze |
| `staged/<path>.vdlu-new` | soubor třídy reboot čekající na výměnu při bootu |
| `lock.d/` | zámek mkdir |
| `tools/<abi>/curl` | stažené, ověřené statické curl; přetrvává napříč aktualizacemi |
| `cancel` | požadavek na zrušení |

## Viz také

- [[Reboot Handling]]: jak třídní systém udržuje většinu aktualizací bez restartu a jak se inscenované `.so` vymění pre-zygote.
- [[Security and Trust Model]]: dva profily, fail-closed validace a řetězec ed25519 se syrovým klíčem.
- [[Feed Format]]: manifest a obsahově adresované bloby, které engine konzumuje.
- [[Architecture]]: jak engine, producer a WebUI do sebe zapadají.
