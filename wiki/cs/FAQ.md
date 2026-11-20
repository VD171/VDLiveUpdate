# FAQ

Krátké odpovědi na otázky, které se vyskytují nejčastěji. Každá odkazuje na stránku s
úplným příběhem.

## Co znamená "bezflashový"? Musím poprvé stejně flashovat?

Ano, flashujete jednou. Modul se nainstaluje normálním způsobem (flashnout zip ve
vašem root manageru). "Bezflashový" popisuje každou aktualizaci poté: VDLU stahuje
jen soubory, které se změnily, a aplikuje je na místě, takže nikdy znovu neflashujete
celý zip jen kvůli dodání pár změněných řádků. Viz [[Architecture]].

## Potřebuje aktualizace restart?

Obvykle ne. Většina souborů (vaše WebUI, binární soubory, knihovny, konfigy, `module.prop`)
je třídy **live** a aplikuje se atomicky bez restartu. Jen soubory třídy reboot
(`.so` pod `zygisk/`, overlay `/system/**`, soubor sepolicy `*.rule`) se
**inscenují** a vymění při příštím bootu, protože běžící proces již namapoval
živý inode. Když se to stane, WebUI zobrazí trvalý banner "reboot to
activate". Viz [[Reboot Handling]].

## Je to bezpečné, pokud je feed pod MITM nebo otrávený?

Ano, na feedu `hardened`. Každé pole manifestu je považováno za nepřátelský vstup.
Manifest musí nést platný ed25519 podpis nad svou kanonickou formou a
`validate_plan()` běží fail-closed **před jakýmkoli stahováním**: zamítne celý
manifest při absolutní cestě nebo cestě s `..`, `sha256`, který nemá 64 hex znaků,
nebo neplatném módu, třídě či kódování. Manifest je také vázán na vaše id modulu,
takže platně podepsaný feed pro jiný modul nelze servírovat na jeho místě.
`sha256` každého blobu se po stažení ověřuje bez ohledu na profil. Viz
[[Security and Trust Model]].

## Co to potřebuje na zařízení (závislosti)?

Velmi málo. Čisté POSIX sh (mksh / busybox / toybox) plus toyboxův `sha256sum`,
`gzip`, `base64` a `date`; vestavěný ověřovač `ed25519-mini`; a, jen pro
`https` zdroj, statické `curl`, které se jednou stáhne a uloží do cache v Tier-2.
`file://` zdroj nepotřebuje žádné curl. **Není žádná závislost na `jq`**:
engine parsuje JSON gron-podobným flattenerem napsaným v `awk`. Viz [[Engine]].

## Je na zařízení potřeba openssl?

Ne. `openssl` se používá jen na straně PC/release (`vdlu-keygen`, `vdlu-sign`).
Na zařízení ověření podpisu používá štíhlý vestavěný binární soubor `ed25519-mini`,
který čte SYROVÝ 32-bajtový veřejný klíč. Viz [[Producer]] a
[[Security and Trust Model]].

## Jak rotuji podpisový klíč?

Vygenerujte nový pár klíčů pomocí `vdlu-keygen`, přidejte nový SYROVÝ 32-bajtový veřejný klíč do
keyringu zařízení vedle předchozího a začněte podepisovat novým `key_id`.
Zařízení vybírá `<keyring>/<key_id>.pub` podle `key_id` manifestu,
takže není potřeba žádná změna enginu. Dodávání jak aktuálního, tak předchozího veřejného klíče
znamená, že rotovaný klíč nikdy nezabije starší instalace. Protože rotace ponechává v keyringu více než jeden klíč, musíte také připnout, který klíč smí podepsat aktualizaci modulu: nastavte konfiguraci `key_id` (oddělenou čárkami během okna rotace). Keyring s jediným klíčem se připne automaticky a nepotřebuje konfiguraci. Viz [[Security and Trust Model]].

## hardened vs trusted - který použiji?

Použijte `hardened` pro jakýkoli veřejný feed (servírován přes `https`, např. GitHub Pages).
Činí podpis povinným a blokuje downgrady. Použijte `trusted` jen pro
privátní `file://` nebo SSH-inscenovaný zdroj, který již řídíte, kde je podpis
best-effort (hash každého blobu se stále kontroluje). Při pochybnostech použijte `hardened`:
je to fail-closed výchozí a jakákoli hodnota jiná než `trusted` je považována za
`hardened`. Viz [[Security and Trust Model]].

## Co když je blob zmanipulován nebo je manifest chybný?

Aktualizace přeruší a nic se neaplikuje. Chybný manifest je zamítnut celý
pomocí `validate_plan()` před jakýmkoli fetchem. Blob, jehož sha256 neodpovídá
manifestu, je zamítnut; tři selhání na stejném blobu přeruší fázi fetch, aniž by se
cokoli aplikovalo. Při jakémkoli tvrdém selhání žurnál zaznamená `ERROR` a modul
zůstane netknutý. Viz [[Engine]].

## Může aktualizace smazat mé soubory nebo zabít zařízení?

Riziko je zadrženo návrhem. Přepsané a smazané soubory se nejprve zálohují do
`rollback/<version>/`, a `apply` přeruší místo přepsání bez úspěšné
zálohy. Mazání běží jen tehdy, když transakce dosáhne `DONE`, nikdy
zatímco restart stále čeká. Neúspěšná aplikace vrátí živé soubory, které již
zapsala. Cesty se před použitím ověřují na zadržení uvnitř adresáře modulu,
takže manifest nemůže zapsat ani smazat mimo strom. Viz [[Engine]] a
[[Security and Trust Model]].

## Funguje to na KernelSU A Magisk A APatch?

Ano. VDLU je obyčejné POSIX sh plus WebUI, vendorované do modulu, takže běží na
KernelSU, APatch i Magisk stejně. Používá WebUI most root manageru
(`ksu.exec`) k řízení enginu a pollování postupu. Viz [[Architecture]] a
[[WebUI]].

## Jak velká je stopa na zařízení?

Malá. Engine jsou skripty; jediné binární soubory jsou per-ABI ověřovač `ed25519-mini`
(nepatrný) a, pro `https` zdroj, statické `curl` (~1MB), které se
jednou stáhne a uloží do cache. Modul, který již svazuje vlastní `curl`, ho znovu použije
a nepřidá žádné stažení vůbec. Tier-2 cache blobů drží ověřený obsah plus
posledních 3 verzí rollbacku. Viz [[Engine]] a [[Architecture]].
