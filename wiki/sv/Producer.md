# Producent

**Producenten** är PC- / releasesidan av VDLU: den lilla uppsättningen verktyg som förvandlar ett färdigt modulträd till ett signerat, innehållsadresserat flöde som enheten kan uppdatera från. Inget här körs på telefonen. Dessa verktyg körs på din releasemaskin (eller, för de delar som är säkra, i CI).

Det finns fyra av dem:

| Verktyg | Körs på | Språk | Uppgift |
|---|---|---|---|
| `vdlu-pack` | PC / CI | python3 | Gå igenom det slutliga modulträdet till `manifest.json` + `blobs/<sha256>` |
| `vdlu-keygen` | PC | sh + openssl | Generera ett ed25519-signeringsnyckelpar |
| `vdlu-sign` | PC | sh + openssl | Injicera `key_id` + signatur i ett manifest, på plats |
| `vdlu-gc` | PC | python3 | Rensa föräldralösa blobbar från ett publicerat flöde (felsäkert) |

Releaseflödet är tre steg, utfört en gång per release: **packa, sedan signera, sedan publicera**. `vdlu-keygen` är en engångsuppsättning, och `vdlu-gc` är underhåll du kör när flödet växer. Allt producenten skickar ut följer [[Feed Format]], som är det motorn på enheten konsumerar.

---

## vdlu-pack

`vdlu-pack` tar **exakt det träd som din `.zip` levererar** (det slutliga trädet, efter att ditt bygge har tillämpat sin egen vitlista och ABI-rensning) och producerar flödet för det.

```sh
vdlu-pack <module_tree_dir> <out_dir> <module_id> <version> \
          [--version-name v106] [--channel stable] [--prev ./prev/manifest.json]
```

Det skriver två saker in i `<out_dir>`:

- `manifest.json` - den fullständiga beskrivningen av målträdet (varje fil med sin `sha256`, `size`, `mode`, kodning och omstartsklass), fortfarande **osignerad** (`key_id`- och `sig`-fälten är tomma platshållare).
- `blobs/<sha256>` (eller `blobs/<sha256>.gz`) - en blob per distinkt filinnehåll.

### Innehållsadresserad och deduplicerande

Varje blob namnges av **sha256 av dess ursprungliga (okomprimerade) innehåll**. Eftersom namnet är hashen landar identiskt innehåll på samma blob. `vdlu-pack` skriver en blob bara om den inte redan finns, så:

- En fil som inte ändrades behåller samma blobnamn och skrivs eller skickas aldrig om.
- Två olika filer med identiskt innehåll delar en blob.
- En återställd fil återanvänder blobben som redan fanns där från tidigare.

Publicering är därför **inkrementell genom konstruktion**: över releaser växer `blobs/` bara, och bara genuint nytt innehåll läggs till. Enheten hämtar efter samma hashar, så den laddar bara ner de blobbar den inte redan har.

### Komprimering (fältet `enc`)

För varje fil avgör `vdlu-pack` hur blobben ska lagras:

- `gz` när filen är minst 4096 byte **och** gzip (deterministisk `-9 -n`) sparar minst 10 procent.
- `raw` annars (små filer som gzip på tråden redan täcker, eller redan inkomprimerbar data).
- Om `gzip` saknas på byggvärden lagras allt `raw`. Packning misslyckas aldrig på grund av detta.

`sha256` i manifestet är **alltid** av originalinnehållet; `enc` namnger bara hur blobben råkar lagras. Enheten dekomprimerar `gz`-blobbar med toybox `gunzip` och kontrollerar sedan hashen mot originalet.

### Omstartsklass och säkerhet

`vdlu-pack` taggar också varje fil med en omstarts-`class` (`live`, `soft`, `reboot`) härledd från dess sökväg, så att motorn vet vad som kan tillämpas utan en omstart och vad som måste förberedas. Reglerna och vad enheten gör med varje klass behandlas i [[Reboot Handling]].

Några saker `vdlu-pack` avsiktligt **inte** gör:

- Den följer inte symlänkar (den hoppar över dem med en varning, så innehåll från utanför trädet, som en länk till en systemfil, kan aldrig läcka in i en blob).
- Den hoppar över icke-reguljära filer (kataloger, fifos, enheter).
- Den respekterar `SOURCE_DATE_EPOCH` för `built`-tidsstämpeln, så att manifest är reproducerbara.
- Den utesluter en fast uppsättning sökvägar helt från flödet (förtroendeankaret, installationsställningen och några andra). Den fullständiga listan, och varför var och en utesluts, finns i [[Feed Format]].

### Listan `delete[]`

Skicka `--prev <previous manifest.json>` så beräknar `vdlu-pack` `delete[]`: de sökvägar som fanns i föregående release men är borta i denna, så att enheten tar bort dem i stället för att lämna föräldralösa filer efter sig. Uteslutna sökvägar skickas aldrig ut som borttagningar, även när de förekommer i föregående manifest (se [[Feed Format]] för den exakta semantiken).

---

## vdlu-keygen

Ett engångssteg. `vdlu-keygen` skapar ed25519-signeringsnyckelparet för ditt flöde.

```sh
vdlu-keygen <id> <out_dir>
```

Det skriver tre filer:

| Fil | Vad det är | Vart det går |
|---|---|---|
| `<id>.pem` | Den **privata** signeringsnyckeln (läge `0600`) | Stannar på din releasemaskin. Aldrig. |
| `<id>.pub` | Den publika nyckeln som PEM | Endast PC-sidans verktyg |
| `<id>.pub.raw` | Den publika nyckeln som **rå 32 byte** | Levereras som modulens nyckelringspost på enheten |

Den råa 32-byte publika nyckeln är det enhetens verifierare läser (den bär ingen `openssl`, så den kan inte läsa PEM). Du bäddar in `<id>.pub.raw` i modulen som `vdlu/keyring/<id>.pub`. PEM är endast för PC-sidans bruk. Denna uppdelning, och hur nyckelrotation fungerar, förklaras i [[Security and Trust Model]].

> **En nyckelring med flera nycklar måste nåla fast `key_id`.** Om modulens nyckelring levererar mer än en nyckel (till exempel release-nyckeln plus en fingeravtrycksflödesnyckel med lägre förtroende) gissar inte motorn vilken som får signera en moduluppdatering. Sätt `key_id`-konfigurationen till nyckeln, eller de kommaseparerade nycklarna under ett rotationsfönster, som får signera uppdateringar; en nyckelring med en enda nyckel nålar fast automatiskt och behöver ingen konfiguration. Detta är moduluppdateringstillåtlistan, som behandlas i [[Security and Trust Model]].

> Den privata `.pem` är den enda hemligheten i hela systemet. Håll den borta från varje enhet och utanför varje repository-push. Se CI-anteckningen nedan.

---

## vdlu-sign

`vdlu-sign` tar det osignerade manifest som `vdlu-pack` producerade och signerar det **på plats**.

```sh
vdlu-sign <manifest.json> <privkey.pem> <key_id>
```

Det sätter `key_id`-fältet, beräknar manifestets kanoniska form och skriver ed25519-signaturen (base64) in i `sig`-fältet. Signaturen är över en precis byte-transformation av manifestet så att PC:n och enheten härleder exakt samma signerade byte utan något JSON-bibliotek på enheten. Den transformationen (**kanoniseringen**) är den enskilt viktigaste invarianten i formatet, och den är dokumenterad i sin helhet i [[Feed Format]].

Den privata nyckeln läses bara här, på din maskin, och lämnar den aldrig.

### Signeringsnyckeln hålls borta från CI

Detta är en avsiktlig designpunkt. CI kan köra `vdlu-pack` och producera en helt giltig **nyckellös baslinje** (ett osignerat seed-manifest; se [[Feed Format]]), så att en ny installation föds aktuell utan att CI någonsin vidrör en privat nyckel. Den faktiska signeringen av det publicerade flödet görs av dig, lokalt, med `vdlu-sign`. På det sättet är signeringsnyckeln 100 procent ute ur CI, och bara flödet du publicerar för hand är signerat.

---

## vdlu-gc

Eftersom blobbar är innehållsadresserade och oföränderliga växer `blobs/` bara: `vdlu-pack` lägger till, den tar aldrig bort. Över många releaser ackumulerar flödet (och den Pages-sajt som är värd för det) blobbar som inget aktuellt manifest längre refererar till. `vdlu-gc` rensar de föräldralösa.

```sh
vdlu-gc <feed_dir> [--keep-last N] [--keep extra.json ...] [--apply]
```

Det bygger den **behållna uppsättningen** manifest: det aktuella `manifest.json`, plus de senaste `N` arkiverade manifesten efter version (standard `N=3`, vilket ger en återställningsmarginal), plus alla du namnger med `--keep`. En blob som refereras av **inget** behållet manifest är föräldralös och är en kandidat för borttagning. Den behållna uppsättningen är en union, så en blob stannar så länge någon behållen release fortfarande behöver den; en enhet som sitter på en äldre behållen version förlorar aldrig sin hämtning.

`vdlu-gc` är byggt för att vara säkert:

- **Torrkörning som standard.** Utan `--apply` skriver det bara ut vad det *skulle* ta bort. Du lägger till `--apply` för att faktiskt radera.
- **Felsäkert.** Om det inte hittar något behållet manifest alls vägrar det att rensa i stället för att riskera att tömma ett flöde.
- **Behållning efter referens, inte efter datum.** En blob behålls för att ett behållet manifest pekar på den, aldrig på grund av en tidsstämpel.

Efter rensning, skicka det mindre flödet till din värd. Sprid ut skrivningen om din värd hastighetsbegränsar batchade skrivningar.

---

## Att sätta ihop det

En typisk release, från början till slut:

```sh
# one-time: make a signing key. Keep the .pem off every device and every repo push.
vdlu-keygen release-2026 ./keys

# each release: pack the final shipped tree (post-whitelist, same tree the .zip ships)
vdlu-pack ./module_tree ./out demo 106 --version-name v106 --channel stable \
          --prev ./prev/manifest.json

# sign the manifest in place (local, private key never leaves your machine)
vdlu-sign ./out/manifest.json ./keys/release-2026.pem release-2026

# publish ./out/{manifest.json,blobs/} to your source (GitHub Pages, rsync, ...).
# occasionally: prune orphan blobs
vdlu-gc ./feed --keep-last 3            # dry-run first
vdlu-gc ./feed --keep-last 3 --apply    # then delete
```

För det fullständiga genomgångna exemplet på att införa VDLU i en modul, se [[Quick Start]]. För formen på tråden för allt producenten skickar ut, se [[Feed Format]]. För resonemanget bakom nyckelhanteringen och vad som hålls utanför flödet, se [[Security and Trust Model]].
