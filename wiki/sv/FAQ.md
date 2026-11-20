# Vanliga frågor

Korta svar på de frågor som dyker upp oftast. Var och en länkar till sidan med
den fullständiga berättelsen.

## Vad betyder "flashfri"? Måste jag ändå flasha första gången?

Ja, du flashar en gång. Modulen installeras på det vanliga sättet (flasha zippen i
din root-hanterare). "Flashfri" beskriver varje uppdatering därefter: VDLU hämtar
bara de filer som ändrats och tillämpar dem på plats, så att du aldrig flashar om en
full zip bara för att skicka några få ändrade rader. Se [[Architecture]].

## Behöver en uppdatering en omstart?

Vanligtvis inte. De flesta filer (din WebUI, binärer, bibliotek, konfigurationer, `module.prop`)
är **live**-klass och tillämpas atomärt utan omstart. Bara omstartsklass-filer
(en `.so` under `zygisk/`, ett `/system/**`-överlägg, en `*.rule`-sepolicy-fil) är
**förberedda** och byts in vid nästa boot, eftersom en körande process redan har
mappat den aktiva inoden. När det händer visar WebUI en bestående "reboot to
activate"-banner. Se [[Reboot Handling]].

## Är det säkert om flödet MITM:as eller förgiftas?

Ja, på ett `hardened`-flöde. Varje manifestfält behandlas som fientlig indata.
Manifestet måste bära en giltig ed25519-signatur över sin kanoniska form, och
`validate_plan()` körs fail-closed **före någon nedladdning**: den förkastar hela
manifestet vid en absolut sökväg eller en med `..`, en `sha256` som inte är 64 hex-tecken,
eller ett ogiltigt läge, klass eller kodning. Manifestet är också bundet till ditt modul-
id, så ett giltigt signerat flöde för en annan modul kan inte serveras i dess ställe.
Varje blobs sha256 verifieras efter nedladdning oavsett profil. Se
[[Security and Trust Model]].

## Vad behöver det på enheten (beroenden)?

Väldigt lite. Ren POSIX sh (mksh / busybox / toybox) plus toybox `sha256sum`,
`gzip`, `base64` och `date`; den inbäddade `ed25519-mini`-verifieraren; och, endast för
en `https`-källa, en statisk `curl` som hämtas en gång och cachas i Tier-2.
En `file://`-källa behöver ingen curl alls. Det finns **inget beroende av `jq`**: motorn
tolkar JSON med en gron-liknande utplattare skriven i `awk`. Se [[Engine]].

## Krävs openssl på enheten?

Nej. `openssl` används bara på PC-/releasesidan (`vdlu-keygen`, `vdlu-sign`).
På enheten använder signaturverifiering den slimmade inbäddade `ed25519-mini`-
binären, som läser en RÅ 32-byte publik nyckel. Se [[Producer]] och
[[Security and Trust Model]].

## Hur roterar jag signeringsnyckeln?

Generera ett nytt nyckelpar med `vdlu-keygen`, lägg till den nya RÅA 32-byte publika nyckeln i
enhetens nyckelring vid sidan av den föregående, och börja signera med det nya
`key_id`. Enheten väljer `<keyring>/<key_id>.pub` efter manifestets `key_id`,
så ingen motorändring behövs. Att leverera både den aktuella och föregående publika nyckeln
betyder att en roterad nyckel aldrig tegelstenar äldre installationer. Se [[Security and Trust Model]].

## hardened vs trusted - vilken använder jag?

Använd `hardened` för varje publikt flöde (serverat över `https`, t.ex. GitHub Pages).
Den gör signaturen obligatorisk och blockerar nedgraderingar. Använd `trusted` bara för en
privat `file://`- eller SSH-förberedd källa du redan kontrollerar, där signaturen
är efter bästa förmåga (varje blob-hash kontrolleras fortfarande). Vid tvivel, använd `hardened`:
det är fail-closed-standarden, och varje icke-`trusted`-värde behandlas som
`hardened`. Se [[Security and Trust Model]].

## Vad händer om en blob manipuleras eller manifestet är felformat?

Uppdateringen avbryts och inget tillämpas. Ett felformat manifest förkastas helt
av `validate_plan()` före någon hämtning. En blob vars sha256 inte matchar
manifestet förkastas; tre misslyckanden på samma blob avbryter fetch-fasen med
inget tillämpat. Vid vilket hårt fel som helst registrerar journalen `ERROR` och modulen
lämnas intakt. Se [[Engine]].

## Kan en uppdatering ta bort mina filer eller tegelstena enheten?

Risken är innesluten genom design. Överskrivna och borttagna filer säkerhetskopieras först
till `rollback/<version>/`, och `apply` avbryter i stället för att skriva över utan en
lyckad säkerhetskopia. Borttagningar körs bara när en transaktion når `DONE`, aldrig
medan en omstart fortfarande är väntande. En misslyckad tillämpning återställer de live-filer den redan
skrev. Sökvägar valideras för inneslutning inuti modulkatalogen innan användning,
så ett manifest kan inte skriva eller ta bort utanför trädet. Se [[Engine]] och
[[Security and Trust Model]].

## Fungerar det på KernelSU OCH Magisk OCH APatch?

Ja. VDLU är ren POSIX sh plus ett WebUI, inbäddat i modulen, så det körs på
KernelSU, APatch och Magisk lika. Det använder root-hanterarens WebUI-brygga
(`ksu.exec`) för att driva motorn och polla förlopp. Se [[Architecture]] och
[[WebUI]].

## Hur stort är fotavtrycket på enheten?

Litet. Motorn är skript; de enda binärerna är per-ABI-`ed25519-mini`-
verifieraren (pytteliten) och, för en `https`-källa, en statisk `curl` (~1MB) som
hämtas en gång och cachas. En modul som redan paketerar sin egen `curl` återanvänder den
och lägger till ingen nedladdning alls. Tier-2-blob-cachen håller verifierat innehåll plus
de senaste 3 rollback-versionerna. Se [[Engine]] och [[Architecture]].
