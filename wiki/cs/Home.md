# VDLiveUpdate (VDLU)

**VDLU je bezflashový, inkrementální engine pro samoaktualizaci modulů KernelSU / APatch / Magisk: nainstalovaný modul aktualizuje vlastní soubory přes podepsaný feed, stahuje jen to, co se změnilo, a většinu toho aplikuje bez restartu.**

Běžná aktualizace modulu znovu dodá celý `.zip`, takže pár změněných řádků stojí úplně nové stažení, a statický manifest aktualizace může ukazovat jen na jedinou `zipUrl` (jedna varianta pro každé zařízení). VDLU jde jinou cestou: porovnává skutečně nainstalovaný strom proti podepsanému, obsahově adresovanému feedu, stahuje jen delty a zapisuje je na místo. Plná instalace arm64 zůstává plnou arm64, lite instalace zůstává lite a modul se nikdy znovu neflashuje.

VDLU je určeno k **vendorování** (vložení) do modulu, umístěné do `<module>/vdlu/`. Není to samostatný modul.

## Cíle

- **Bezflashová samoaktualizace.** Aktualizuj nainstalovaný modul na místě, over the air, bez root manageru, bez znovu-flashování `.zip` a bez ztráty nainstalované varianty.
- **Inkrementální podle obsahu.** Přenášej jen bloby, jejichž obsah se změnil. Obsahově adresovaný feed (`manifest.json` + `blobs/<sha256>`) znamená, že nezměněné nebo vrácené soubory se nikdy znovu nestahují.
- **Bez restartu tam, kde je to bezpečné.** Běžné soubory aplikuj okamžitě naostro. Inscenovaný restart vyhrad jen pro těch několik souborů, které ho skutečně potřebují (`.so`, overlay `/system`, `sepolicy.rule`).
- **Štíhlé na zařízení.** Čisté POSIX `sh`, žádné `jq`, žádný `bash`, žádný `openssl` na zařízení. Ověření se opírá o vestavěné `ed25519-mini`; jediný stahovaný binární soubor je statické `curl`, použité jen pro `https` feedy.
- **Fail-closed a poctivé.** Každé pole manifestu je považováno za nepřátelský vstup a je ověřeno dříve, než se cokoli stáhne. Nic se nikdy nenahlásí jako "hotové", pokud to nedokáže opětovné zahashování, a nic se nepřepíše bez předchozího zálohování.

## Zvláštnosti

Co odlišuje VDLU od typického OTA klienta:

- **Bezflashové a inkrementální.** Obsahově adresované diff / fetch / apply s deduplikací: zařízení spočítá deltu proti podepsanému feedu a stáhne jen chybějící bloby.
- **Bez restartu, kde je to možné.** Běžné soubory se aplikují naostro; jen `.so`, overlaye `/system` a soubory `sepolicy.rule` se inscenují a vymění při jediném restartu. Viz [[Reboot Handling]].
- **POSIX `sh` na zařízení.** Běží pod toybox / busybox / mksh. Žádné `jq` (JSON parsuje `gron`-podobný flattener v `awk`), žádné `bash`-ismy, žádný těžký runtime.
- **Štíhlé ověření.** Vestavěné `ed25519-mini` ověřuje podpisy. Na zařízení **není žádný `openssl`**; privátní klíč se nikdy nedotkne zařízení ani CI.
- **Fail-closed bezpečnost.** `validate_plan()` zamítne **celý** manifest při jakémkoli špatném poli (absolutní cesta nebo cesta s `..`, `sha256`, který není 64 hex znaků, neplatný mód / třída / kódování). Dva profily, `trusted` a `hardened`, přičemž `hardened` je fail-closed inverzí. Viz [[Security and Trust Model]].
- **Obnovitelné a atomické.** Žurnál činí každou transakci odolnou proti pádu; zápisy používají `rename` / `mv`; před každým přepsáním se pořídí záloha, takže neúspěšná aplikace se vrátí zpět místo poškození modulu.

## Začněte zde

| Pokud chcete... | Přejděte na |
|---|---|
| Převzít VDLU do svého modulu krok za krokem | [[Quick Start]] |
| Porozumět celému systému na první pohled | [[Architecture]] |
| Poznat engine na straně zařízení (`update.sh`) | [[Engine]] |
| Sestavit a podepsat feed na svém PC | [[Producer]] |
| Vložit panel Updates | [[WebUI]] |
| Přečíst si model důvěry a bezpečnostní postoj | [[Security and Trust Model]] |
| Vidět rozložení manifestu a blobů | [[Feed Format]] |
| Vědět, co vyvolává restart a proč | [[Reboot Handling]] |
| Položit častou otázku | [[FAQ]] |
| Přispět | [[Contributing]] |

## Odkazy na projekt

- **Zdrojový kód:** https://github.com/VD171/VDLiveUpdate
- **Kanál (aktualizace):** @Priv8_VD https://t.me/Priv8_VD

VDLiveUpdate je nezávislý, neoficiální projekt. "Android" je ochranná známka Google LLC; "KernelSU", "Magisk" a "APatch" jsou známky jejich příslušných autorů. VDLU běží kompletně na vašem zařízení a na vašem vlastním release hostu.
