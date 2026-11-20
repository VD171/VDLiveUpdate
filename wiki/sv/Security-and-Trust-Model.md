# Säkerhets- och förtroendemodell

VDLU uppdaterar en modul på plats, över nätverket, som root. Det är mycket makt riktat mot en fil som kommer från ett flöde, så hela motorn är byggd på ett enda antagande:

> **Varje fält i manifestet är fientlig indata.**

Ett flöde kan förgiftas vid källan, eller bytas ut och förvanskas i transit av en MITM. När det händer anländer manifestet ändå och ser ut som ett manifest: det bär filsökvägar, `sha256`-strängar, en `delete[]`-lista, lägen, klasser och en kodningsflagga. VDLU behandlar inget av detta som pålitligt. Den validerar hela planen innan den laddar ner en enda byte, och den låter aldrig ett manifestvärde nå ett skal.

Denna sida är den fullständiga förtroendeberättelsen. Se [[Feed Format]] för manifestschemat den validerar, och [[Engine]] för var dessa kontroller sitter i DIFF -> FETCH -> APPLY -> COMMIT-transaktionen.

---

## Kärnidén: fail-closed, innan något händer

`validate_plan()` körs inuti `check`/diff-fasen, **innan** någon hämtning och **innan** någon tillämpning. Den går igenom varje post i det planerade filträdet och varje post i `delete[]`, och om en enda post är felformad **förkastar den hela manifestet** och transaktionen startar aldrig. Det finns inget partiellt godtagande, inget "hoppa över den dåliga och tillämpa resten". Ett dåligt fält förgiftar hela satsen, med flit.

Ett manifest godtas bara om **alla** dessa gäller för **varje** post:

| Fält | Regel | Varför |
|---|---|---|
| `path` | inte absolut, ingen `..`-komponent, ingen `.`-komponent, inget inledande `./`, inget inbäddat `/./`, inget avslutande snedstreck, inget kontrolltecken (tabb / radbrytning) | en sökväg måste stanna inuti `MODULE_DIR`; en absolut sökväg eller en med `..` är skriv-var-som-helst |
| `sha256` | matchar `^[0-9a-f]{64}$` exakt | en icke-hex-sha skulle annars interpoleras in i en skalsökväg; det är innehållsadressen, så den måste vara en ren hex-digest och inget annat |
| `mode` | endast oktalt (`[0-7]`) | en lägessträng blir ett `chmod`-argument |
| `size` | endast siffror, och `<=` motorns storlekstak | begränsar nedladdningen och dekomprimeringen |
| `class` | exakt `live`, `soft` eller `reboot` | klassen avgör om en fil tillämpas i realtid eller förbereds för omstart |
| `enc` | exakt `raw` eller `gz` | kodningen avgör om blobben gunzippas |
| `delete[]`-poster | samma sökvägsregler som ovan | en `delete[]`-post driver en borttagning; en okontrollerad `..` skulle vara `rm` utanför trädet |

Eftersom detta körs först kan ett förgiftat manifest aldrig skriva utanför modulen, aldrig ta bort utanför modulen, och aldrig injicera ett icke-hex-token in i en kommandorad.

### Manifestvärden vidrör aldrig ett skal

Regelns andra hälft: även efter att ett värde klarat valideringen interpoleras det aldrig in i `sh`, och matas aldrig till `awk system()`. Check-kommandot skrevs avsiktligt om för att inte innehålla något `system()`-anrop. Innehållsadressering gör resten av arbetet: en blob hämtas efter sin `sha256`, skrivs till en cachesökväg namngiven av samma `sha256`, och de nedladdade byten omhashas och jämförs innan något tillämpas. Ett värde som inte är en ren 64-hex-digest kommer aldrig så långt, eftersom `validate_plan()` redan förkastade det.

### En andra försvarslinje vid tillämpningstid

`validate_plan()` blockerar `..` **lexikalt**, men en redan befintlig symlänk inuti trädet kan ändå omdirigera en skrivning. Så vid tillämpningstid löser `contained()` den verkliga målsökvägen och bekräftar att den sitter under modulbasen, och faller stängt när den inte kan lösas. Skrivningar är atomära (skriv till ett temporärt namn, gör sedan `rename` över målet) och varje överskrivning säkerhetskopieras till `rollback/` först; en misslyckad säkerhetskopia avbryter tillämpningen i stället för att skriva över utan skyddsnät.

---

## De två profilerna

VDLU körs i en av två förtroendeprofiler, satt av `profile=` i konfigurationen.

### `hardened` (den publika standarden)

- **Signatur är obligatorisk.** Manifestet måste bära en giltig ed25519-signatur från en nyckel i nyckelringen på enheten, annars avbryts transaktionen.
- **Nedgradering är blockerad.** Ett manifest vars `version` är lägre än den installerade versionen vägras. En angripare kan inte rulla tillbaka dig till ett känt sårbart bygge.
- Detta är profilen för varje modul som distribueras till allmänheten över `https://`.

### `trusted` (privat, SSH-förberedd källa)

- Signaturverifiering är **efter bästa förmåga**: källan är ett privat `file://`- eller SSH-förberett flöde du kontrollerar, så en saknad eller overifierbar signatur avbryter inte hårt.
- **Men varje blobs `sha256` kontrolleras ändå, alltid.** `trusted` slappnar av *vem som signerade manifestet*, aldrig *huruvida byten matchar planen*. Innehållsintegritet är icke förhandlingsbart i båda profilerna.

---

## Fail-closed genom inversion

Detta är den subtila delen, och det är den del de flesta system får fel.

`trusted` är den **enda** strängen som väljer in slappnad verifiering. Motorn testar inte "är detta `hardened`?" Den testar "är detta **inte** `trusted`?":

```sh
prof=$(cfg profile hardened | tr -d '[:space:]')
...
if [ "$prof" != trusted ]; then
    # signature mandatory
fi
```

Så **allt** annat än det bokstavliga `trusted` löser till hardened-beteende:

- raden saknas helt -> hardened
- ett stavfel som `hardend` -> hardened
- `trusted ` med ett avslutande blanksteg, eller ett `\r` från CRLF -> hardened
- `Trusted` med fel skiftläge -> hardened
- ett MITM-förvanskat värde -> hardened

En tidigare version lät en *saknad* rad falla till hardened, vilket ändå lämnade ett korrumperat *värde* att falla igenom till den öppna vägen. Det var en fail-open: en förvanskad profilsträng kunde tyst godta ett osignerat manifest, och ett osignerat manifest betyder en angriparlevererad `.so` inbytt under MITM, vilket är fjärrkörning av kod på root-nivå. Inversionen stänger det. Det enda sättet att få slappnad verifiering är att stava `trusted` exakt, och även då kontrolleras blob-hasharna. Motorn är aldrig ett stavfel från att godta osignerad kod. (`tr -d` avlägsnar strökande blanksteg så att ett legitimt `trusted` med slarvig blanksteg inte felaktigt förkastas, utan att återöppna hålet.)

**Detta test är bärande. Det måste förbli `!= trusted` och aldrig bli `== hardened`.**

---

## Manifestet är bundet till modulen

En enda release-nyckel signerar många moduler. Så ett manifest som är giltigt signerat, för en *annan* modul, skulle i princip kunna serveras till denna (en flödesfelkonfiguration, ett källbyte eller en MITM-omdirigering) och dess signatur skulle checka ut.

VDLU stänger detta med en bindning: det signerade `module`-fältet inuti manifestet måste vara lika med denna installations `MODID`, annars förkastas manifestet som ett flöde mellan moduler. Eftersom `module` är inuti den signerade kanoniska formen kan en angripare inte ändra det utan att bryta signaturen. Ett giltigt signerat flöde för modul B kan helt enkelt inte tillämpas på modul A.

---

## Den slimmade verifieraren på enheten

Verifiering på enheten använder **ed25519-mini**, en pytteliten enbart-verifiera-kontrollerare byggd på TweetNaCl (public domain). Det finns **inget `openssl` på enheten**.

- Nyckelringsposten är den **råa 32-byte publika nyckeln**, lagrad som `keyring/<key_id>.pub`. (Den publika PEM-nyckeln är endast en PC-sidans artefakt; att kopiera en PEM in i enhetens nyckelring bryter verifieringen, eftersom verifieraren förväntar sig exakt 32 råa byte.)
- `vdlu-verify <manifest.json> <keyring_dir>` rekonstruerar den kanoniska formen (manifesttexten med `sig`-fältet borttaget, kompakt, sorterade nycklar), hashar den till det 64-tecken-hex-meddelande signaturen täcker, avkodar base64-signaturen, kontrollerar att den är 64 byte, och frågar `ed25519-mini <pub32> <msg> <sig64>` om ett utlåtande. rc 0 = giltig, allt annat = avslag.
- Binären är statisk per ABI (arm64-v8a, armeabi-v7a, x86, x86_64), med en `PROVENANCE.json` som fastställer de exakta TweetNaCl-källorna, wrapper-hashen och byggflaggorna, så att det som körs som root är granskningsbart.
- `key_id` från manifestet saneras självt (inget `/`, inget `..`, inget citattecken) innan det används för att välja en nyckelringsfil, så det kan inte ta sig ut ur nyckelringskatalogen.

### Nyckelringen är flash-only, verifiera-inte-kopiera, stabil

Nyckelringen levereras inuti modulen vid flashtid och skrivs inte om av uppdateringsmotorn. Vid återinbäddning är regeln **verifiera, kopiera inte**: nyckelringen ändras bara vid en avsiktlig nyckelrotation, aldrig som en bieffekt av en uppdatering.

### Nyckelrotation tegelstenar inte äldre installationer

När en signeringsnyckel roteras levererar nyckelringen **både den aktuella och den föregående råa publika nyckeln**. Verifieraren väljer nyckelfilen efter manifestets `key_id`, så ett flöde som fortfarande är signerat av den gamla nyckeln verifieras mot den gamla pubnyckeln, och ett flöde signerat av den nya nyckeln verifieras mot den nya. En enhet som inte har uppdaterat förbi rotationen fortsätter fungera; inget blir strandat.

---

## Vad verktygsmanifestet stänger

Den slimmade hämtningsstartaren laddar ner en statisk `curl` vid första användningen för moduler som inte levererar sin egen. Eftersom den binären körs som root är dess egen manifestsignatur (ed25519-mini) och dess hash **obligatoriska i varje profil**, inklusive `trusted`, innan den någonsin installeras eller körs. Webviewen är bara transport; förtroende kommer från signatur- och hash-kontrollen på enheten, aldrig från det faktum att en nedladdning lyckades.

---

## Vad en angripare INTE kan göra

Även med ägande av flödet, eller sittande på tråden som en full MITM, kan en angripare inte:

- **Skriva utanför modulen.** Absoluta sökvägar, `..`, `.`, kontrolltecken och avslutande snedstreck förkastas alla innan någon tillämpning, och symlänkomdirigering fångas igen vid tillämpningstid.
- **Ta bort utanför modulen.** `delete[]`-poster klarar samma sökvägsvalidering.
- **Injicera ett kommando.** Inget manifestvärde interpoleras in i ett skal eller `awk system()`; `sha256` måste vara ren 64-hex eller så förkastas hela manifestet.
- **Skicka osignerad kod till en publik installation.** `hardened` gör signaturen obligatorisk, och profilen är fail-closed genom inversion, så inget stavfel eller förvanskat värde nedgraderar det.
- **Servera en annan moduls signerade flöde här.** Det signerade `module`-fältet måste vara lika med detta `MODID`.
- **Rulla tillbaka dig.** Nedgradering är blockerad i `hardened`.
- **Korrumpera en blob oupptäckt.** Varje nedladdad blob omhashas mot manifestets `sha256` i båda profilerna; en avvikelse efter tre försök avbryter fasen utan att något tillämpas.
- **Byta in en falsk root-hämtare.** Den startade `curl` är signatur- och hash-kontrollerad innan den installeras eller körs, i varje profil.
- **Halvtillämpa en korrumperad uppdatering.** Transaktionen når bara `DONE` när en omhashning av allt stämmer; en misslyckad tillämpning rullar tillbaka i stället för att skriva över utan en säkerhetskopia.

---

Se även: [[Feed Format]] för manifestschemat, [[Engine]] för transaktionen dessa kontroller lever i, och [[Architecture]] för helhetsbilden.
