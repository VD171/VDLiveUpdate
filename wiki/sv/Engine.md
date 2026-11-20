# Motor

Motorn är enhetssidan av VDLU: den del som körs på telefonen, avgör vad som ändrats, laddar ner det och tillämpar det. Det är ett enda POSIX-skalskript, `engine/update.sh`, plus en pytteliten signaturkontrollerare, `engine/vdlu-verify`. Båda bäddas in i värdmodulen vid `<module>/vdlu/` och körs av root.

Hela motorn är byggd kring en enda idé: en uppdatering är en **återupptagbar transaktion**. Om telefonen startas om, dödas eller tappar nätverket halvvägs, tar nästa körning vid exakt där den stannade, och modulen lämnas aldrig halvtillämpad medan den låtsas vara klar.

Vill du ha helhetsbilden först, se [[Architecture]]. För hur uppdateringar undviker en omstart när de kan, se [[Reboot Handling]].

## Skriven för enheten, inte för din laptop

`update.sh` är ren POSIX `sh`. Den körs under mksh, busybox eller toybox, utan några bash-exklusiva funktioner, och den klarar `sh -n`. Det spelar roll eftersom miljön på en rootad Android-enhet är liten och strikt.

I synnerhet finns inget `jq`. VDLU tolkar `manifest.json` med en liten gron-liknande utplattare skriven i `awk`: den går igenom JSON ett tecken i taget och skickar ut en `path<TAB>value`-rad per löv (till exempel `files/0/sha256<TAB>ab..` eller `version<TAB>6`). Skalet läser sedan de raderna med `grep` och `cut`. Detta fungerar på både kompakt och snyggformaterad JSON, och det anropar aldrig ett JSON-verktyg som inte finns där.

Motorn är bara beroende av det som toybox redan levererar (`sha256sum`, `gzip`/`gunzip`, `base64`, `date`), den inbäddade `ed25519-mini`-verifieraren, och, för `https://`-flöden, en liten statisk `curl` som hämtas och verifieras en gång. Ett `file://`-flöde behöver ingen `curl` alls.

## De sex kommandona

Du anropar motorn med modulens sökvägar i miljön och ett kommando:

```sh
VDLU_DIR=/data/adb/<mod>/vdlu MODULE_DIR=/data/adb/modules/<mod> MODID=<mod> \
  sh "$MODULE_DIR/vdlu/update.sh" <cmd>
```

Returkod `0` betyder framgång; vilken annan kod som helst betyder ett fel, med orsaken utskriven till stderr.

| Kommando | Vad det gör |
|---|---|
| `check` | Skrivskyddad diff. Laddar ner manifestet, jämför det med det som är installerat och skriver ut en enradig JSON-sammanfattning: `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`. Ändrar inget på disk. Om enheten är nyare än flödet (en blockerad nedgradering) rapporterar den `{"update":false,"ahead":true,...}` med returkod `0`, inte ett fel. |
| `run` | Hela den aktiva cykeln: DIFF, FETCH, APPLY, COMMIT. Tillämpar varje aktiv fil direkt och förbereder de få omstartsklass-filerna. Respekterar `cancel`. Skriver förlopp till `journal.json`. |
| `resume` | Fortsätter en transaktion som avbröts, med start från vilken fas den än var i. Idempotent. Den byter **inte** en förberedd `.so` (det är reserverat för `boot`). |
| `boot` | Vägen före zygote. Gör ett `resume` och byter sedan in alla förberedda `*.vdlu-new`-filer, och stänger `PENDING_REBOOT` till `DONE`. Om det inte finns någon väntande transaktion kör den en ny cykel och tillämpar allt, inklusive `.so`, i den enda booten. |
| `status` | Skriver ut `journal.json`, eller `{"state":"idle"}` när inget pågår. |
| `cancel` | Skapar en `cancel`-markör. En pågående `run` stannar rent vid nästa säkra punkt. |

Kommandot `check` är avsiktligt billigt, så att gränssnittet kan tala om för dig att en uppdatering finns på vilket nätverk som helst. Själva nedladdningen regleras separat (se fetch-fasen nedan).

## Transaktionen, steg för steg

Varje `run` rör sig genom en fast tillståndsmaskin, nedtecknad i `journal.json` så att WebUI (och du) kan följa den:

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)
```

**DIFF.** Motorn hämtar `manifest.json`, validerar varje fält (se nedan och [[Security and Trust Model]]), och jämför det signerade målträdet mot `current.json`, manifestet för den redan installerade versionen. Resultatet är en plan per fil skriven till `plan.tsv`: en rad per fil, som bär dess klass, målhash, läge och förloppstillstånd. Filer som redan har målets hash markeras att hoppas över.

**FETCH.** För varje fil som fortfarande behövs laddar motorn ner dess innehållsadresserade blob från `<source>/blobs/<sha>` (eller `<sha>.gz` när den är komprimerad), till en `.part`-fil. Om blobben är gzippad dekomprimeras den, sedan kontrolleras dess SHA-256 mot manifestet. Bara vid en träff flyttas den atomärt med `mv` till `blobs/<sha>`. En blob som redan finns i cachen med en korrekt hash hoppas över helt, och en oförändrad lokal fil kan seeda cachen utan någon nedladdning. Tre misslyckanden på samma blob avbryter fasen utan att något tillämpas. Fasen når `FETCHED` bara när varje blob i planen finns och är verifierad. För det [[Feed Format]] dessa blobbar kommer från, se den sidan.

Hämtningen regleras av nätverkspolicyn: ett flöde kan begränsas till endast Wi-Fi, endast mobildata eller valfritt nätverk. När det aktuella nätverket inte är tillåtet misslyckas inte hämtningen; den går in i det ofarliga `DEFERRED`-tillståndet, behåller planen och målet fastställda, och återupptas vid nästa kontroll eller boot så fort rätt nätverk dyker upp. Ingen data förbrukas under tiden.

**APPLY.** Nås bara någonsin från `FETCHED`. För varje fil agerar motorn efter klass:

- `live`- och `soft`-filer: säkerhetskopiera den aktuella filen till `rollback/<version>/<path>`, skriv det nya innehållet till en `.vdlu-tmp`-syskonfil, `chmod` den, verifiera dess hash och gör sedan en atomär `rename` över målet. En fil som redan har målets hash hoppas över.
- `reboot`-filer (en `.so`, ett `/system`-överlägg, en `sepolicy.rule`): materialisera till `staged/<path>.vdlu-new`. Den aktiva inoden vidrörs aldrig här. Se [[Reboot Handling]].
- borttagningar: säkerhetskopiera, ta sedan bort. Borttagningar tillämpas bara allra sist, vid ett rent `DONE`, aldrig medan en omstart fortfarande är väntande.

**COMMIT.** Motorn omhashar varje `live`- och `soft`-fil den vidrörde. Bara när alla stämmer skriver den `current.json` och gör den nya versionen till diff-basen. Om någon omstartsklass-fil förbereddes blir tillståndet `PENDING_REBOOT` i stället för `DONE`; bytet och den slutliga omverifieringen sker senare under `boot`-kommandot.

## Felsäker genom konstruktion

De garantier som gör detta säkert att köra utan övervakning:

- **Inget markeras `DONE` utan en matchande omhashning.** `DONE` nås bara efter att varje tillämpad fil lästs tillbaka och dess SHA-256 jämförts med manifestet. En förberedd omstartsfil tvingar fram `PENDING_REBOOT`, aldrig ett falskt `DONE`.
- **Inget går förlorat.** Varje fil säkerhetskopieras till `rollback/<version>/` innan den skrivs över, och de senaste tre versionerna behålls. Om en tillämpning misslyckas återställs de aktiva filerna från säkerhetskopian; modulen lämnas aldrig halvtillämpad medan den ljuger om det. `apply_live` avbryter direkt om säkerhetskopieringssteget misslyckas, i stället för att skriva över utan väg tillbaka.
- **Allt är atomärt.** Nytt innehåll landar via `rename`/`mv` över målet, så en läsare ser antingen den gamla filen eller den nya, aldrig en avhuggen skrivning.
- **Återupptagbar efter krasch eller dödande.** En krasch, ett tappat nätverk eller en omstart mitt i lämnar en giltig journal; `resume` (eller `boot`) fortsätter från den nedtecknade fasen. Designen utgår från att den kommer att avbrytas.
- **Degraderar rent.** En saknad binär, ett nedkopplat nätverk eller en full disk ger ett tydligt fel på stderr och `state:ERROR` i journalen, utan att korrumpera modulen.

## Låset

Bara en transaktion får vidröra tillståndet åt gången. `flock` är inte pålitlig på toybox, så VDLU serialiserar med ett kataloglås: `mkdir "$VDLU_DIR/lock.d"` lyckas för exakt en anropare och misslyckas för resten, vilket är atomärt på vilket vettigt filsystem som helst. Ett föråldrat lås som lämnats av en död process återhämtas genom att kontrollera den nedtecknade PID:en.

Det tålmodiga återförsöket vid boot (som används när enheten är offline vid boot) håller **inte** detta lås medan det väntar. Det tar och släpper låset mellan försöken, så en manuell `run` blockeras aldrig av en boot som väntar på nätverket, och det håller aldrig en wakelock. Batterisäkert genom design. Mer om det i [[Reboot Handling]].

## Signaturkontroll: `vdlu-verify`

`vdlu-verify` är signaturkontrolleraren på enheten, avsiktligt hållen slimmad:

```
vdlu-verify <manifest.json> <keyring_dir>
```

Returkod `0` betyder att manifestets signatur är giltig mot nyckelringens publika nyckel vars id matchar manifestets `key_id`; vilken annan kod som helst är ett avslag.

Det som gör den slimmad är att den använder **inget `openssl` på enheten**. Den läser nyckelringens publika nyckel som en **rå 32-byte**-fil, kanoniserar manifestet (manifesttexten med `sig`-fältet borttaget), hashar det med toybox `sha256sum`, base64-avkodar signaturen och överlämnar den råa nyckeln, meddelandet och den 64-byte långa signaturen till den inbäddade `ed25519-mini`-binären. Kontrolleraren vägrar också allt felformat innan den ens verifierar: ett saknat eller tomt `key_id` eller `sig`, ett `key_id` som innehåller sökvägsseparatorer, en publik nyckel som inte är exakt 32 byte, eller en signatur som inte är exakt 64 byte.

Innan den ens väljer en nyckel upprätthåller motorn en **`key_id`-tillåtlista**: manifestets `key_id` måste vara en som konfigurationen tillåter att signera en *moduluppdatering*, och en nyckel som bara finns i nyckelringen men inte är tillåtlistad förkastas innan dess pubnyckel någonsin laddas. En nyckelring med en enda nyckel nålar automatiskt fast den nyckeln utan konfiguration; en nyckelring med flera nycklar måste nåla fast `key_id` annars fallerar motorn stängt. Den tillåtna mängden skickas ner till `vdlu-verify` som `VDLU_KEYID_ALLOW`, och den gäller i båda profilerna. Detta hindrar en nyckel med lägre förtroende, som en fingeravtrycksflödesnyckel som delar nyckelringen, från att signera en full root-uppdatering; det separata fingeravtrycksflödet behåller sin egen fastnålade nyckel, `FEED_KEY_ID`. Hela berättelsen finns i [[Security and Trust Model]].

Kanoniseringen är byte-för-byte identisk med producentens signerare, vilket är det som gör att en signatur verifieras tvärs över verktyg. Den matchande privata nyckeln vidrör aldrig en enhet eller CI; bara den råa publika nyckeln bäddas in. Hela förtroendeberättelsen, de två profilerna och varför `hardened` är fail-closed genom inversion finns i [[Security and Trust Model]].

Motorn anropar `vdlu-verify` under diff-fasen. Under `hardened`-profilen avbryter en misslyckad verifiering hela uppdateringen; under `trusted` är verifieringen efter bästa förmåga, men varje blobs hash kontrolleras ändå alltid, så korrumperat innehåll fångas oavsett profil.

## Tillstånd på disk

Allt motorns tillstånd lever i `$VDLU_DIR` (utanför modulkatalogen), så modulträdet självt håller bara någonsin färdiga filer:

| Sökväg | Roll |
|---|---|
| `config` | inställningar som key=value (source, profile, channel, nätverkspolicy, boot-återförsök) |
| `current.json` | manifest för den aktiva versionen; detta är diff-basen. Frånvaro betyder aldrig uppdaterad |
| `target.json` | det fastställda manifestet för den pågående transaktionen. Dess närvaro markerar en aktiv transaktion; det blir `current.json` vid `DONE` |
| `plan.tsv` / `plan.del` | planen och förloppet per fil, och listan över sökvägar att ta bort |
| `journal.json` | förlopp för WebUI, omskriven vid varje tillståndsändring |
| `blobs/<sha256>` | cache av verifierat, dekomprimerat originalinnehåll |
| `rollback/<version>/<path>` | säkerhetskopior av överskrivna filer; de senaste tre versionerna behålls |
| `staged/<path>.vdlu-new` | en omstartsklass-fil som väntar på bootbytet |
| `lock.d/` | mkdir-låset |
| `tools/<abi>/curl` | den hämtade, verifierade statiska curl; består mellan uppdateringar |
| `cancel` | en avbrottsbegäran |

## Se även

- [[Reboot Handling]]: hur klassystemet håller de flesta uppdateringar omstartsfria, och hur en förberedd `.so` byts in före zygote.
- [[Security and Trust Model]]: de två profilerna, fail-closed-validering och rånyckel-ed25519-kedjan.
- [[Feed Format]]: manifestet och de innehållsadresserade blobbarna motorn konsumerar.
- [[Architecture]]: hur motorn, producenten och WebUI passar ihop.
