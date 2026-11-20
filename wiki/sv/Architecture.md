# Arkitektur

VDLU har två sidor förenade av en sak i mitten. På PC:n förvandlar [[Producer]] ett modulträd till ett signerat, innehållsadresserat flöde. På enheten läser [[Engine]] det flödet, räknar ut vad som ändrats och tillämpar det. Fogen mellan dem är **det signerade manifestet plus blob-lagret** (se [[Feed Format]]). Inget annat korsar gapet.

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

De två sidorna delar aldrig en körmiljö. Producer använder `python3` och `openssl`; Engine är ren POSIX `sh` med toybox och en inbäddad `ed25519-mini`. De är överens enbart för att båda härleder **samma kanoniska byte** från ett manifest (se [[Security and Trust Model]]). WebUI är en tunn panel i ren JavaScript som driver motorn via root-hanterarens brygga och läser dess förloppsjournal; den innehåller ingen egen uppdateringslogik. Se [[WebUI]].

## De två sidorna

| Sida | Körs på | Byggd av | Uppgift |
|---|---|---|---|
| [[Producer]] | PC / CI | `python3` + `sh` + `openssl` | Gå igenom modulträdet till `manifest.json` + `blobs/`, signera det, rensa föräldralösa blobbar |
| [[Engine]] | enhet | POSIX `sh` + toybox + `ed25519-mini` | Jämför det installerade trädet mot flödet, hämta skillnader, tillämpa, bekräfta |
| [[WebUI]] | enhet (webview) | ren JS/CSS | Utlös uppdateringar, visa förlopp, redigera konfiguration, visa omstartsbannern |

## Uppdateringspipelinen

Varje uppdatering är en transaktion, körd i en fast ordning:

```
  DIFF  ------>  FETCH  ------>  APPLY  ------>  COMMIT
  read feed      download        write live     re-hash all,
  + validate     only missing    files now,      promote target
  + plan         blobs, verify   stage reboot     -> current,
  (no changes)   each sha256     ones             DONE or
                                                  PENDING_REBOOT
```

- **DIFF** (`update.sh check` är denna fas, skrivskyddad). Motorn laddar bara ner manifestet, kör `validate_plan()` över varje fält **innan** den rör något, och jämför sedan flödet mot `current.json` för att bygga en plan per fil. Den ändrar inget på disk. En enhet som ligger före flödet är ett ofarligt "ahead"-resultat, inte ett fel.
- **FETCH.** Laddar bara ner de blobbar som planen saknar, till `<sha>.part`, dekomprimerar `gz`, kontrollerar `sha256sum` mot manifestet och flyttar atomärt varje verifierad blob med `mv` in i cachen. En blob som redan finns i cachen (eller seedats från en oförändrad lokal fil) hoppas över, så en återställning eller en delad fil kostar ingenting. Tre misslyckanden på en blob avbryter fasen utan att något tillämpas. En nedladdning som blockeras av nätverkspolicyn avslutas som `DEFERRED` (återupptagbar), inte som ett fel.
- **APPLY.** Vanliga (`live` / `soft`) filer skrivs nu: säkerhetskopiera till `rollback/<v>/`, skriv en `.vdlu-tmp`, `chmod`, verifiera och gör sedan en atomär `rename` över målet. Omstartsklass-filer materialiseras till `staged/<path>.vdlu-new` och den aktiva inoden lämnas orörd. En `delete[]`-post säkerhetskopieras och tas sedan bort. Varje steg är idempotent: en fil som redan har målets hash hoppas över.
- **COMMIT.** Omhasha varje aktiv fil; bara om allt stämmer befordrar motorn `target.json` till `current.json`. Om något förbereddes slutar transaktionen i `PENDING_REBOOT`; annars `DONE`.

## Innehållsadresserat manifest och blobbar

Flödet är innehållsadresserat: manifestet listar det **fullständiga** målträdet, varje fil bärs av sin `sha256`, och blob-lagret håller en kopia av varje distinkt innehåll under `blobs/<sha256>` (eller `blobs/<sha256>.gz`).

- **Deduplicering.** Identiskt innehåll var som helst i trädet, eller mellan releaser, är en enda blob. Publicering är inkrementell: en blob vars `sha256` redan finns på värden skickas aldrig igen, och enheten hämtar aldrig innehåll den redan har.
- **sha256 är av originalet.** Hashen namnger alltid det okomprimerade innehållet; `enc` (`raw` eller `gz`) registrerar bara hur just den blobben råkar lagras. Enheten dekomprimerar `gz` med toybox `gunzip`, så ingen extra komprimerare paketeras.
- **Variantstabil.** Eftersom enheten jämför mot det som faktiskt är installerat kan flödet bära en hel modulfamilj; varje installation hämtar bara de blobbar som kompletterar dess egen variant.

Fullständig fält-för-fält-layout finns i [[Feed Format]].

## Den återupptagbara journalen

Varje transaktion är kraschsäker eftersom dess förlopp lever i en journal (`journal.json`), och det fastställda målet för den pågående transaktionen lever i `target.json`. Tillståndsmaskinen körs i en fast ordning:

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> ( PENDING_REBOOT | DONE )
                                                               \-> ERROR / DEFERRED
```

| Tillstånd | Betydelse |
|---|---|
| `PLANNED` | Plan byggd, inget hämtat ännu |
| `FETCHING` / `FETCHED` | Laddar ner blobbar / alla blobbar finns och är verifierade |
| `APPLYING` / `APPLIED_LIVE` | Skriver filer / alla aktiva filer skrivna |
| `PENDING_REBOOT` | En omstartsklass-fil är förberedd och väntar på bootbytet |
| `DONE` | Omhashning av allt stämde; `current.json` befordrad |
| `ERROR` | Hårt fel; modulen lämnad okorrumperad, aktiva filer återställda från `rollback/` |
| `DEFERRED` | Nedladdning hålls tillbaka av nätverkspolicyn; planen består, återupptas senare |

`DONE` nås **bara** när en omhashning av allt stämmer, så journalen påstår aldrig att en halvtillämpad uppdatering är klar. En krasch, ett tappat nätverk eller en omstart mitt i lämnar en återupptagbar journal; `update.sh resume` (eller `boot`) tar vid från den aktuella fasen. Se [[Engine]] för kommandouppsättningen och tillståndsfilerna på enheten.

## Atomäritet och återställning

Inget skrivs någonsin över på plats och inget går förlorat:

- **Atomära skrivningar.** Varje fil landar via en temporär fil (`.vdlu-tmp`) och en atomär `rename` / `mv`, så en läsare ser aldrig en halvskriven fil.
- **Säkerhetskopia före överskrivning.** Det tidigare innehållet går till `rollback/<version>/<path>` innan den nya filen döps om över det (de senaste versionerna behålls). Om en tillämpning misslyckas återställs de aktiva filerna från rollback-kopian i stället för att lämnas korrumperade. En misslyckad säkerhetskopia **avbryter** tillämpningen i stället för att skriva över utan skyddsnät.
- **Serialiserad.** Ett `mkdir`-baserat lås (`lock.d/`, eftersom `flock` inte fungerar på toybox, med återhämtning från föråldrat lås via PID) serialiserar samtidiga körningar.

## Omstartsfrihetsprincipen

De flesta filer kan bytas ut medan modulen är aktiv, så VDLU tillämpar dem direkt. Bara tre klasser behöver en omstart, eftersom en aktiv process redan har mappat dem: en `.so` (laddad av Zygisk), ett `/system`-överlägg och en `sepolicy.rule`. Dessa **förbereds, skrivs aldrig över en aktiv inod**, och byts in i ett enda steg före zygote vid nästa boot. Hela taxonomin och bootflödet finns i [[Reboot Handling]].

## Fail-closed-förtroendehållningen

Flödet är det enda som korsar från PC:n till enheten, så motorn behandlar varje byte av det som fientligt. `validate_plan()` körs i DIFF-fasen, före varje nedladdning, och förkastar hela manifestet vid vilket felformat fält som helst. Signaturverifiering använder en inbäddad `ed25519-mini` (inget `openssl` på enheten), den privata nyckeln vidrör aldrig en enhet eller CI, och `hardened`-profilen är fail-closed genom inversion så att ett korrumperat profilvärde aldrig tyst kan godta ett osignerat flöde. Den fullständiga modellen, de två profilerna och de hot var och en svarar mot finns i [[Security and Trust Model]].
