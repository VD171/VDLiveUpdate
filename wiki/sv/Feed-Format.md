# Flödesformat

**Flödet** är det VDLU serverar över tråden och det enheten uppdaterar från. Det är en vanlig statisk katalog, serverbar av vad som helst (GitHub Pages, ett rsync-mål, en `file://`-sökväg):

```
<source>/
  manifest.json          # the signed description of the current release
  blobs/<sha256>         # one blob per distinct file content
  blobs/<sha256>.gz      # (when the blob is stored gzipped)
```

Modulen själv levererar också en extra fil, `baseline.json`, inuti `.zip`-filen (inte serverad från flödet). Producenten som bygger allt detta beskrivs i [[Producer]]; denna sida är kontraktet över tråden.

---

## manifest.json

Manifestet är den fullständiga beskrivningen av en release: varje fil i målträdet, vad som ska tas bort, och signaturen över hela saken.

```json
{
  "schema": 1,
  "module": "demo",
  "version": 106,
  "version_name": "v106",
  "built": "2026-11-19T12:00:00Z",
  "engine_min": 3,
  "channel": "stable",
  "key_id": "release-2026",
  "files": [
    {
      "path": "webroot/index.html",
      "sha256": "<hex64>",
      "size": 1234,
      "mode": "0644",
      "enc": "raw",
      "class": "live"
    }
  ],
  "delete": ["webroot/old.html"],
  "sig": "<base64>"
}
```

### Fält

| Fält | Betydelse |
|---|---|
| `schema` | Formatversion av själva manifestet (för närvarande `1`). |
| `module` | Modulens id. Enheten förkastar manifestet om det inte matchar dess eget modul-id, så ett giltigt signerat flöde för en annan modul kan inte serveras i dess ställe. |
| `version` | Heltalsversion. Motorn uppdaterar bara framåt; ett flöde äldre än enheten är ett ofarligt "ahead"-tillstånd, inte ett fel. |
| `version_name` | Människoläsbar versionssträng (till exempel `v106`). |
| `built` | ISO 8601-byggtidsstämpel. Respekterar `SOURCE_DATE_EPOCH` för reproducerbarhet. |
| `engine_min` | Den minsta motorversion som krävs för att tillämpa detta manifest. |
| `channel` | Releasekanal (till exempel `stable`). |
| `key_id` | Vilken nyckel i enhetens nyckelring som signerade detta manifest. Väljer den publika nyckeln för verifiering, och måste finnas i motorns moduluppdateringstillåtlista (se [[Security and Trust Model]]); en nyckel som bara finns i nyckelringen men inte är tillåtlistad förkastas innan dess pubnyckel laddas. |
| `files[]` | Det **fullständiga** målträdet (inte en diff). Varje post: `path`, `sha256`, `size`, `mode`, `enc` (`raw`/`gz`), `class` (`live`/`soft`/`reboot`). |
| `delete[]` | Sökvägar som fanns i föregående release men är borta nu, för enheten att ta bort. |
| `sig` | ed25519-signaturen, base64. Se kanoniseringen nedan. |

`files[]` beskriver **hela** trädet, inte en delta. Enheten beräknar deltat själv genom att jämföra manifestet mot det den redan har, och hämtar bara de blobbar vars `sha256` den saknar. `sha256` är alltid av det ursprungliga (okomprimerade) innehållet; `enc` säger bara hur den blobben lagras i `blobs/`. Betydelsen av `class` och vad enheten gör med varje värde behandlas i [[Reboot Handling]].

---

## Kanonisering (de signerade byten)

Detta är den enskilt viktigaste invarianten i formatet. PC-signeraren och verifieraren på enheten körs på helt olika körmiljöer (openssl på PC:n, toybox + en pytteliten inbäddad verifierare på enheten, och **inget JSON-bibliotek alls** på enheten). De måste ändå härleda exakt samma byte att signera och att verifiera. Regeln är därför en avsiktlig **byte-transformation**, inte en JSON-omserialisering.

**Steg 1: en fast lagringsform.** `vdlu-pack` skriver `manifest.json` kompakt, med sorterade nycklar, UTF-8, inkluderar alltid `key_id` och `sig` (som tomma strängar tills de signeras):

```
json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
```

**Steg 2: ta bort endast `sig`.** Den kanoniska formen är den exakta texten med **endast `"sig"`-fältet borttaget**. Eftersom nycklarna är sorterade förekommer `sig` alltid som `,"sig":"<value>",` inramat av `"schema"` före det och `"version"` efter det (båda alltid närvarande), så att ta bort det lämnar välformad text. JSON escapar varje `"` inuti ett strängvärde som `\"`, så det strukturella token `"sig":"` är entydigt även mot ett filnamn som bokstavligen innehåller `"sig":"`.

Borttagningen är en handfull POSIX-parameterexpansioner, identiska i signeraren och verifieraren, utan `sed` och utan `jq`:

```sh
# $1 = the full manifest text
_pre=${_c%%\"sig\":\"*}     # up to  ...,"schema":N,
_rest=${_c#*\"sig\":\"}      # after "sig":"
_tail=${_rest#*\",}          # after <value>",  ->  "version":...
printf '%s%s' "$_pre" "$_tail" | sha256sum | cut -d' ' -f1
```

**Steg 3: signera hashen av det.** Det signerade/verifierade meddelandet är **sha256-hexen** (64 ASCII-tecken, ingen radbrytning) av den kanoniska formen. ed25519 signerar den hexen.

Två konsekvenser faller ut av detta genom konstruktion:

- `key_id` är en del av den kanoniska formen (bara `sig` tas bort). `vdlu-sign` sätter `key_id` **innan** hashning, så nyckelidentiteten täcks av signaturen.
- Oavsett om `sig`-platshållaren är tom (`"sig":""`, vid signeringstid) eller fylld (vid verifieringstid), ger borttagning av den de identiska kanoniska byten. Signering och verifiering är överens automatiskt.

De två POSIX sh-verktygen är auktoritativa. En Python-motsvarighet, `re.sub(r'"sig":"[^"]*",', '', text, count=1)` och sedan sha256, finns bara för att korsverifiera dem.

Förtroenderesonemanget kring allt detta (varför verifiering är på enheten, hur `hardened` faller stängt) lever i [[Security and Trust Model]].

---

## baseline.json (installationsseed)

När en modul är nyinstallerad bör den redan vara "aktuell" för sin egen levererade version, utan en onödig självuppdatering av den version den just installerade. Det är vad `baseline.json` gör.

`baseline.json` levereras **inuti modul-zippen** (vid `vdlu/baseline.json`), inte på flödet. Vid en nyinstallation seedar motorn sin "aktiva version"-post från den, så att enheten föds aktuell, utan någon `from:0` och ingen omhämtning av det den redan har.

Nyckelegenskaper:

- Det är en **nyckellös kopia av det signerade manifestet** för den levererade versionen: samma `vdlu-pack`-utdata, lämnad osignerad (`key_id` och `sig` förblir tomma).
- Det är **inte verifierat**. Motorn behandlar det som ett lokalt betrott seed eftersom det anlände inuti den flashade zippen, vilket är installationens förtroendegräns. Bara ett manifest *hämtat från flödet* går genom signaturverifiering.
- Eftersom det inte behöver någon signatur kan **CI generera det nyckellöst**, vilket är det som håller signeringsnyckeln helt ute ur CI (se [[Producer]]).
- `vdlu-pack` **utesluter `baseline.json` från sitt eget manifest**, så manifestet refererar aldrig baslinjen (det skulle vara en självreferensloop: manifest till baslinje till manifest).
- Det är **icke-fatalt om det saknas**. Utan det startar enheten helt enkelt från `from:0` vid sin första uppdatering och hämtar det den behöver. Aldrig trasigt, bara mindre optimalt.

---

## Blobbar

Varje distinkt filinnehåll är en blob under `blobs/`, namngiven av **sha256 av originalinnehållet**:

- `blobs/<sha256>` för en rå blob.
- `blobs/<sha256>.gz` för en gzippad blob (gzip behålls bara när filen är minst 4096 byte och komprimering sparar minst 10 procent).

En blob lagras en gång, i ett format. Innehållsadressering ger deduplicering gratis: oförändrat, delat eller återställt innehåll mappar till en blob som redan finns, så att flödet bara växer med genuint nytt innehåll, och enheten laddar bara ner de hashar den saknar. Enheten kontrollerar varje nedladdad blobs `sha256` mot manifestet (efter att ha dekomprimerat en `gz`-blob) innan den används.

---

## Vad som utesluts från flödet, och varför

Flödet bär **bara modulens eget innehåll**. En fast uppsättning sökvägar hålls utanför det med flit. `vdlu-pack` tillämpar ett uteslutningspredikat både när det går igenom trädet och när det beräknar `delete[]`.

| Uteslutet | Varför |
|---|---|
| `vdlu/keyring/`, `vdlu/verify/` (förtroenderoten: råa publika nycklar + verifierarbinären) | **Detta är kärnans säkerhetsskäl.** Förtroendeankaret är **flash-only**. Om nyckelringen eller verifieraren vore flödesleveranserbara skulle ett manifest kunna skriva över just det som validerar det. Att hålla dem borta från tråden betyder att ett manifest aldrig kan skriva om förtroendeankaret på enheten. |
| `vdlu/baseline.json` | Det är en kopia av det signerade manifestet (installationsseed); att packa det skulle vara en självreferensloop. |
| `.vd/`-flashinfrastruktur | Flash-gate-ställning som levereras i zippen, aldrig tillämpad i realtid. |
| `update.json`, `update-mmrl.json` | Deras storlek/sha fylls i av CI *efter* att zippfilerna byggts, så att den levererade kopian skiljer sig från varje flödeskopia. Att mata dem skulle orsaka en fantom-hämtning av en enda fil vid varje installations första självuppdatering, och de är ändå rudimentära på enheten (hanteraren läser den fjärranslutna råa uppdaterings-JSON:en). |
| `META-INF/`, `customize.sh` (installationsställning) | Konsumeras av hanteraren vid **flash**tid och behålls inte i den installerade modulen. De är inte VDLU-innehåll; att servera dem slösar blobbar och, om en någonsin ändrades mellan versioner, skulle den skrivas som en installationsfil in i den aktiva modulkatalogen. |
| Per-fil-`.sha256`-följeslagare | De hör bara till den flashbara zippen, blir föråldrade efter en inkrementell uppdatering, och skulle fördubbla manifestet. |
| Dev-/doc-filer (`RELEASE.md`, `CLAUDE.md`, `.gitignore`) | Levereras aldrig till enheten; att servera dem slösar blobbar och kärnar det signerade manifestet vid varje doc-redigering. |

Resonemanget bakom uteslutningen av förtroenderoten utvecklas i [[Security and Trust Model]].

---

## delete[]-semantik

`delete[]` talar om för enheten vilka sökvägar som ska tas bort, så att en fil som tappas mellan releaser inte dröjer kvar på enheten som en föräldralös. Det beräknas genom att skicka `--prev <previous manifest.json>` till `vdlu-pack`: en sökväg som fanns i föregående release och inte finns i den aktuella blir en delete-post.

Den viktiga regeln: **uteslutna sökvägar skickas aldrig ut som borttagningar, inte ens med `--prev`.** Varje föregående sökväg körs genom samma uteslutningspredikat som används när trädet gås igenom. Om ett `--prev` pekar på ett äldre manifest som fortfarande listade nu-uteslutna sökvägar (en kvarglömd `baseline.json`, `META-INF/*`, en nyckelringspost och så vidare), förvandlas dessa sökvägar **inte** till delete-poster. En utesluten sökväg var aldrig flödesinnehåll, så den är inte VDLU:s att ta bort, och enheten beordras aldrig att ta bort en fil som inte serverades genom flödet. Detta är det som håller uteslutningslistan från att någonsin vända tillbaka som en destruktiv instruktion.
