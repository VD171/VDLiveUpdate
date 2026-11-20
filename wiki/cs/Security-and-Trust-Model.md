# Security and Trust Model

VDLU aktualizuje modul na místě, přes síť, jako root. To je spousta síly namířené na soubor, který pochází z feedu, takže celý engine je postaven na jediném předpokladu:

> **Každé pole v manifestu je nepřátelský vstup.**

Feed může být otráven u zdroje, nebo vyměněn a zkomolen při přenosu MITM útočníkem. Když se to stane, manifest stále dorazí vypadající jako manifest: nese cesty souborů, řetězce `sha256`, seznam `delete[]`, módy, třídy a příznak kódování. VDLU žádný z nich nepovažuje za důvěryhodný. Ověří celý plán dříve, než stáhne jediný bajt, a nikdy nenechá hodnotu manifestu dosáhnout shellu.

Tato stránka je úplný příběh důvěry. Viz [[Feed Format]] pro schéma manifestu, které ověřuje, a [[Engine]] pro to, kde tyto kontroly sedí v transakci DIFF -> FETCH -> APPLY -> COMMIT.

---

## Základní myšlenka: fail-closed, dříve než se cokoli stane

`validate_plan()` běží uvnitř fáze `check`/diff, **dříve** než jakýkoli fetch a **dříve** než jakákoli aplikace. Prochází každý záznam v plánovaném stromu souborů a každý záznam v `delete[]`, a pokud je jediný záznam chybný, **zamítne celý manifest** a transakce nikdy nezačne. Není žádné částečné přijetí, žádné "přeskoč špatný a aplikuj zbytek". Jedno špatné pole otráví dávku, záměrně.

Manifest je přijat jen tehdy, pokud **všechny** tyto podmínky platí pro **každý** záznam:

| Pole | Pravidlo | Proč |
|---|---|---|
| `path` | není absolutní, žádná komponenta `..`, žádná komponenta `.`, žádné úvodní `./`, žádné vložené `/./`, žádné koncové lomítko, žádný řídicí znak (tab / nový řádek) | cesta musí zůstat uvnitř `MODULE_DIR`; absolutní cesta nebo cesta s `..` je zápis kamkoli |
| `sha256` | odpovídá přesně `^[0-9a-f]{64}$` | ne-hex sha by se jinak interpoloval do cesty shellu; je to obsahová adresa, takže musí být čistý hex digest a nic jiného |
| `mode` | jen oktalové (`[0-7]`) | řetězec módu se stane argumentem `chmod` |
| `size` | jen číslice, a `<=` stropu velikosti enginu | omezuje stažení a dekompresi |
| `class` | přesně `live`, `soft` nebo `reboot` | třída rozhoduje, zda se soubor aplikuje naostro nebo je inscenován pro restart |
| `enc` | přesně `raw` nebo `gz` | kódování rozhoduje, zda se blob gunzipuje |
| záznamy `delete[]` | stejná pravidla cest jako výše | záznam `delete[]` řídí odstranění; nekontrolované `..` by bylo `rm` mimo strom |

Protože toto běží jako první, otrávený manifest nikdy nemůže zapsat mimo modul, nikdy smazat mimo modul a nikdy vložit ne-hex token do příkazové řádky.

### Hodnoty manifestu se nikdy nedotknou shellu

Druhá polovina pravidla: i poté, co hodnota projde validací, se nikdy neinterpoluje do `sh` a nikdy nepředá do `awk system()`. Příkaz check byl záměrně přepsán tak, aby neobsahoval žádné volání `system()`. Obsahové adresování odvede zbytek práce: blob se stáhne podle jeho `sha256`, zapíše do cesty cache pojmenované podle stejného `sha256`, a stažené bajty se znovu zahashují a porovnají dříve, než se cokoli aplikuje. Hodnota, která není čistý 64-hex digest, se tak daleko nikdy nedostane, protože `validate_plan()` ji již zamítl.

### Druhá linie obrany v čase aplikace

`validate_plan()` blokuje `..` **lexikálně**, ale již existující symbolický odkaz uvnitř stromu by stále mohl přesměrovat zápis. Takže v čase aplikace `contained()` vyřeší skutečnou cílovou cestu a potvrdí, že sedí pod základnou modulu, selhávajíc fail-closed, když ji nemůže vyřešit. Zápisy jsou atomické (zápis do dočasného jména, pak `rename` přes cíl) a každé přepsání se nejprve zálohuje do `rollback/`; neúspěšná záloha přeruší aplikaci místo přepsání bez záchranné sítě.

---

## Dva profily

VDLU běží v jednom ze dvou profilů důvěry, nastaveného pomocí `profile=` v konfiguraci.

### `hardened` (veřejný výchozí)

- **Podpis je povinný.** Manifest musí nést platný ed25519 podpis z klíče v keyringu na zařízení, nebo transakce přeruší.
- **Downgrade je zablokován.** Manifest, jehož `version` je nižší než nainstalovaná verze, je odmítnut. Útočník vás nemůže vrátit na známý zranitelný build.
- To je profil pro jakýkoli modul distribuovaný veřejnosti přes `https://`.

### `trusted` (privátní, SSH-inscenovaný zdroj)

- Ověření podpisu je **best-effort**: zdroj je privátní `file://` nebo SSH-inscenovaný feed, který řídíte, takže chybějící nebo neověřitelný podpis tvrdě nepřeruší.
- **Ale `sha256` každého blobu se stále vždy kontroluje.** `trusted` uvolňuje *kdo podepsal manifest*, nikdy *zda bajty odpovídají plánu*. Integrita obsahu je nezměnitelná v obou profilech.

---

## Fail-closed inverze

To je ta jemná část a je to část, kterou většina systémů dělá špatně.

`trusted` je **jediný** řetězec, který se přihlašuje k uvolněnému ověření. Engine netestuje "je to `hardened`?" Testuje "je to **ne** `trusted`?":

```sh
prof=$(cfg profile hardened | tr -d '[:space:]')
...
if [ "$prof" != trusted ]; then
    # signature mandatory
fi
```

Takže **cokoli** jiného než doslovné `trusted` se vyřeší na chování hardened:

- řádek zcela chybí -> hardened
- překlep jako `hardend` -> hardened
- `trusted ` s koncovou mezerou, nebo `\r` z CRLF -> hardened
- `Trusted` se špatným písmenem -> hardened
- hodnota zkomolena MITM -> hardened

Dřívější verze nastavovala *chybějící* řádek na hardened jako výchozí, což stále nechávalo poškozenou *hodnotu* propadnout na otevřenou cestu. To bylo fail-open: zkomolený řetězec profilu mohl tiše přijmout nepodepsaný manifest, a nepodepsaný manifest znamená `.so` dodanou útočníkem vyměněnou pod MITM, což je vzdálené spuštění kódu na úrovni root. Inverze to uzavírá. Jediný způsob, jak získat uvolněné ověření, je napsat `trusted` přesně, a i tehdy se hashe blobů kontrolují. Engine nikdy není jeden překlep od přijetí nepodepsaného kódu. (`tr -d` odstraní zbloudilé bílé znaky, takže legitimní `trusted` s nedbalými mezerami není nesprávně zamítnuto, aniž by se znovu otevřela ta díra.)

**Tento test je nosný. Musí zůstat `!= trusted` a nikdy se stát `== hardened`.**

---

## Manifest je vázán na modul

Jediný release klíč podepisuje mnoho modulů. Takže manifest, který je platně podepsán, pro *jiný* modul, by v principu mohl být servírován tomuto (chybná konfigurace feedu, výměna zdroje nebo MITM přesměrování) a jeho podpis by vyšel.

VDLU to uzavírá vazbou: podepsané pole `module` uvnitř manifestu se musí rovnat `MODID` této instalace, nebo je manifest zamítnut jako feed pro jiný modul. Protože `module` je uvnitř podepsané kanonické formy, útočník ho nemůže změnit bez porušení podpisu. Platně podepsaný feed pro modul B prostě nelze aplikovat na modul A.

---

## Štíhlý ověřovač na zařízení

Ověření na zařízení používá **ed25519-mini**, nepatrný kontrolér jen pro ověření postavený na TweetNaCl (public domain). Na zařízení **není žádný `openssl`**.

- Záznam keyringu je **syrový 32-bajtový veřejný klíč**, uložený jako `keyring/<key_id>.pub`. (PEM veřejný klíč je artefakt jen na straně PC; kopírování PEM do keyringu zařízení rozbije ověření, protože ověřovač očekává přesně 32 syrových bajtů.)
- `vdlu-verify <manifest.json> <keyring_dir>` rekonstruuje kanonickou formu (text manifestu s odstraněným polem `sig`, kompaktní, seřazené klíče), zahashuje ji na 64-znakovou hex zprávu, kterou podpis pokrývá, dekóduje base64 podpis, zkontroluje, že má 64 bajtů, a požádá `ed25519-mini <pub32> <msg> <sig64>` o verdikt. rc 0 = platný, cokoli jiného = zamítnutí.
- Binární soubor je statický na ABI (arm64-v8a, armeabi-v7a, x86, x86_64), s `PROVENANCE.json` připínajícím přesně zdroje TweetNaCl, hash wrapperu a build flagy, takže věc běžící jako root je auditovatelná.
- `key_id` z manifestu je sám sanitizován (žádné `/`, žádné `..`, žádné uvozovky) dříve, než se použije k výběru souboru keyringu, takže nemůže uniknout z adresáře keyringu.

### Keyring je flash-only, verify-not-copy, stabilní

Keyring se dodává uvnitř modulu v čase flashe a update engine ho nepřepisuje. Při znovu-vendorování zní pravidlo **verify, do not copy**: keyring se mění jen při záměrné rotaci klíče, nikdy jako vedlejší efekt aktualizace.

### Rotace klíče nezabije starší instalace

Když se podpisový klíč rotuje, keyring dodává **jak aktuální, tak předchozí syrový veřejný klíč**. Ověřovač vybírá soubor klíče podle `key_id` manifestu, takže feed stále podepsaný starým klíčem se ověří proti starému pubkey a feed podepsaný novým klíčem se ověří proti novému. Zařízení, které neaktualizovalo za rotaci, funguje dál; nic nezůstane uvízlé.

---

## Co uzavírá tools-manifest

Štíhlý bootstrap fetche stáhne statické `curl` při prvním použití pro moduly, které nedodávají vlastní. Protože ten binární soubor běží jako root, jeho vlastní podpis manifestu (ed25519-mini) a jeho hash jsou **povinné v jakémkoli profilu**, včetně `trusted`, dříve než se kdy nainstaluje nebo spustí. Webview je jen transport; důvěra pochází z podpisu a kontroly hashe na zařízení, nikdy z faktu, že stažení uspělo.

---

## Co útočník NEMŮŽE udělat

I když vlastní feed, nebo sedí na drátě jako plný MITM, útočník nemůže:

- **Zapsat mimo modul.** Absolutní cesty, `..`, `.`, řídicí znaky a koncová lomítka jsou všechny zamítnuty dříve než jakákoli aplikace a přesměrování symbolického odkazu je znovu zachyceno v čase aplikace.
- **Smazat mimo modul.** Záznamy `delete[]` procházejí stejnou validací cest.
- **Vložit příkaz.** Žádná hodnota manifestu se neinterpoluje do shellu nebo `awk system()`; `sha256` musí být čistý 64-hex nebo je celý manifest zamítnut.
- **Dodat nepodepsaný kód veřejné instalaci.** `hardened` činí podpis povinným a profil je fail-closed inverze, takže žádný překlep nebo zkomolená hodnota to nesníží.
- **Servírovat zde podepsaný feed jiného modulu.** Podepsané pole `module` se musí rovnat tomuto `MODID`.
- **Vrátit vás zpět.** Downgrade je v `hardened` zablokován.
- **Poškodit blob nezjištěně.** Každý stažený blob se znovu zahashuje proti manifestovému `sha256` v obou profilech; neshoda po třech pokusech fázi přeruší, aniž by se cokoli aplikovalo.
- **Vyměnit falešný root fetcher.** Bootstrapované `curl` se kontroluje podpisem a hashem dříve, než se nainstaluje nebo spustí, v každém profilu.
- **Napůl aplikovat poškozenou aktualizaci.** Transakce dosáhne `DONE` jen tehdy, když opětovné zahashování všeho souhlasí; neúspěšná aplikace se vrátí zpět místo přepsání bez zálohy.

---

Viz také: [[Feed Format]] pro schéma manifestu, [[Engine]] pro transakci, ve které tyto kontroly žijí, a [[Architecture]] pro velký obraz.
