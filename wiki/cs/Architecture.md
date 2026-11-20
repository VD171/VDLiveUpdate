# Architecture

VDLU má dvě strany spojené jednou věcí uprostřed. Na PC [[Producer]] promění strom modulu na podepsaný, obsahově adresovaný feed. Na zařízení [[Engine]] ten feed čte, zjistí, co se změnilo, a aplikuje to. Svarem mezi nimi je **podepsaný manifest plus úložiště blobů** (viz [[Feed Format]]). Nic jiného mezeru nepřekračuje.

```
        PC / release host                                device
  +--------------------------+                 +---------------------------+
  |  Producer                |                 |  Engine  (update.sh)      |
  |  vdlu-pack  -> manifest  |    signed       |  POSIX sh, no jq          |
  |  vdlu-sign  -> sig       |    feed         |  DIFF FETCH APPLY COMMIT  |
  |  vdlu-gc    -> prune     | =============>  |  journal + rollback       |
  +--------------------------+   manifest.json |  ed25519-mini verify      |
                                 blobs/<sha>   +-------------+-------------+
                                                             |
                                                       +-----v------+
                                                       |  WebUI     |
                                                       |  Updates   |
                                                       |  panel     |
                                                       +------------+
```

Obě strany nikdy nesdílejí runtime. Producer používá `python3` a `openssl`; Engine je čistě POSIX `sh` s toybox a vestavěným `ed25519-mini`. Shodují se jen proto, že obě odvozují **tytéž kanonické bajty** z manifestu (viz [[Security and Trust Model]]). WebUI je tenký panel ve vanilla JS, který řídí engine přes most root manageru a čte jeho žurnál postupu; nemá žádnou vlastní logiku aktualizace. Viz [[WebUI]].

## Dvě strany

| Strana | Běží na | Postavena z | Úloha |
|---|---|---|---|
| [[Producer]] | PC / CI | `python3` + `sh` + `openssl` | Projít strom modulu do `manifest.json` + `blobs/`, podepsat, odstranit siroty |
| [[Engine]] | zařízení | POSIX `sh` + toybox + `ed25519-mini` | Porovnat nainstalovaný strom proti feedu, stáhnout delty, aplikovat, commitnout |
| [[WebUI]] | zařízení (webview) | vanilla JS/CSS | Spouštět aktualizace, zobrazovat postup, upravovat konfiguraci, zobrazit banner restartu |

## Pipeline aktualizace

Každá aktualizace je jedna transakce, spuštěná v pevném pořadí:

```
  DIFF  ------>  FETCH  ------>  APPLY  ------>  COMMIT
  read feed      download        write live     re-hash all,
  + validate     only missing    files now,      promote target
  + plan         blobs, verify   stage reboot     -> current,
  (no changes)   each sha256     ones             DONE or
                                                  PENDING_REBOOT
```

- **DIFF** (`update.sh check` je tato fáze, jen pro čtení). Engine stáhne jen manifest, spustí `validate_plan()` nad každým polem **dříve**, než se čehokoli dotkne, a pak porovná feed proti `current.json`, aby sestavil plán po souborech. Na disku nic nemění. Zařízení před feedem je neškodný výsledek "ahead", ne chyba.
- **FETCH.** Stáhne jen bloby, které plánu chybí, do `<sha>.part`, dekomprimuje `gz`, zkontroluje `sha256sum` proti manifestu a každý ověřený blob atomicky `mv`-ne do cache. Blob již v cache (nebo nasazený z nezměněného lokálního souboru) se přeskočí, takže vrácení nebo sdílený soubor nestojí nic. Tři selhání na jednom blobu fázi přeruší, aniž by se cokoli aplikovalo. Stažení zablokované síťovou politikou skončí jako `DEFERRED` (obnovitelné), ne chyba.
- **APPLY.** Běžné soubory (`live` / `soft`) se zapisují nyní: záloha do `rollback/<v>/`, zápis `.vdlu-tmp`, `chmod`, ověření, pak atomické `rename` přes cíl. Soubory třídy reboot se materializují do `staged/<path>.vdlu-new` a živý inode zůstává nedotčený. Záznam `delete[]` se zálohuje a pak odstraní. Každý krok je idempotentní: soubor již na cílovém hashi se přeskočí.
- **COMMIT.** Znovu zahashuje každý živý soubor; jen pokud vše souhlasí, engine povýší `target.json` na `current.json`. Pokud se něco inscenovalo, transakce skončí v `PENDING_REBOOT`; jinak v `DONE`.

## Obsahově adresovaný manifest a bloby

Feed je obsahově adresovaný: manifest vypisuje **úplný** cílový strom, každý soubor nesen svým `sha256`, a úložiště blobů drží jednu kopii každého odlišného obsahu pod `blobs/<sha256>` (nebo `blobs/<sha256>.gz`).

- **Deduplikace.** Identický obsah kdekoli ve stromu, nebo napříč vydáními, je jeden blob. Publikování je inkrementální: blob, jehož `sha256` již na hostu existuje, se nikdy znovu nepushuje, a zařízení nikdy znovu nestahuje obsah, který již má.
- **sha256 je z originálu.** Hash vždy pojmenovává nekomprimovaný obsah; `enc` (`raw` nebo `gz`) jen zaznamenává, jak je ten jeden blob náhodou uložen. Zařízení dekomprimuje `gz` pomocí toybox `gunzip`, takže se nedodává žádný další kompresor.
- **Stabilní vůči variantě.** Protože zařízení porovnává proti tomu, co je skutečně nainstalováno, feed může nést celou rodinu modulů; každá instalace stáhne jen bloby, které dokončí její vlastní variantu.

Úplné rozložení pole po poli je v [[Feed Format]].

## Obnovitelný žurnál

Každá transakce je odolná proti pádu, protože její postup žije v žurnálu (`journal.json`) a připnutý cíl probíhající transakce žije v `target.json`. Stavový automat běží v pevném pořadí:

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> ( PENDING_REBOOT | DONE )
                                                               \-> ERROR / DEFERRED
```

| Stav | Význam |
|---|---|
| `PLANNED` | Plán sestaven, zatím nic nestaženo |
| `FETCHING` / `FETCHED` | Stahují se bloby / všechny bloby přítomny a ověřeny |
| `APPLYING` / `APPLIED_LIVE` | Zapisují se soubory / všechny živé soubory zapsány |
| `PENDING_REBOOT` | Soubor třídy reboot je inscenovaný, čeká na výměnu při bootu |
| `DONE` | Opětovné zahashování všeho souhlasilo; `current.json` povýšen |
| `ERROR` | Tvrdé selhání; modul ponechán neporušený, živé soubory vráceny z `rollback/` |
| `DEFERRED` | Stažení zadrženo síťovou politikou; plán přetrvává, obnoví se později |

`DONE` se dosáhne **až** jakmile opětovné zahashování všeho souhlasí, takže žurnál nikdy netvrdí, že napůl aplikovaná aktualizace je hotova. Pád, výpadek sítě nebo restart v půlce zanechá obnovitelný žurnál; `update.sh resume` (nebo `boot`) naváže od aktuální fáze. Viz [[Engine]] pro sadu příkazů a stavové soubory na zařízení.

## Atomicita a rollback

Nic se nikdy nepřepisuje na místě a nic se neztrácí:

- **Atomické zápisy.** Každý soubor přistane přes dočasný (`.vdlu-tmp`) a atomicky `rename` / `mv`, takže čtenář nikdy nevidí napůl zapsaný soubor.
- **Záloha před přepsáním.** Předchozí obsah jde do `rollback/<version>/<path>` dříve, než se přes něj nový soubor přejmenuje (několik posledních verzí se uchovává). Pokud aplikace selže, živé soubory se vrátí z kopie rollbacku místo ponechání poškozené. Neúspěšná záloha aplikaci **přeruší** místo přepsání bez záchranné sítě.
- **Serializované.** Zámek založený na `mkdir` (`lock.d/`, protože `flock` na toybox není použitelný, s obnovou po zastaralém zámku podle PID) serializuje souběžné běhy.

## Princip bez restartu

Většinu souborů lze vyměnit, zatímco modul běží naostro, takže VDLU je aplikuje okamžitě. Jen tři třídy potřebují restart, protože je běžící proces již namapoval: `.so` (načítáno Zygiskem), overlay `/system` a `sepolicy.rule`. Ty jsou **inscenovány, nikdy nezapsány přes živý inode** a vyměněny v jediném pre-zygote kroku při příštím bootu. Úplná taxonomie a průběh bootu jsou v [[Reboot Handling]].

## Fail-closed postoj důvěry

Feed je jediná věc, která přechází z PC na zařízení, takže engine považuje každý jeho bajt za nepřátelský. `validate_plan()` běží ve fázi DIFF, před každým stahováním, a zamítne celý manifest při jakémkoli chybném poli. Ověření podpisu používá vestavěné `ed25519-mini` (žádný `openssl` na zařízení), privátní klíč se nikdy nedotkne zařízení ani CI, a profil `hardened` je fail-closed inverzí, takže poškozená hodnota profilu nikdy nemůže tiše přijmout nepodepsaný feed. Úplný model, dva profily a hrozby, které každý z nich řeší, jsou v [[Security and Trust Model]].
